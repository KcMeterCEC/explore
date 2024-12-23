---
title: Swupdate 的简易使用
tags: 
- swupdate
categories: 
- linux
- make
- swupdate
date: 2024/12/19
updated: 2024/12/20
layout: true
comments: true
---

这里记录 Swupdate 的简易使用说明。

<!--more-->

# 初识

## 流程

SWUpdate 是位于用户空间的应用程序，用于升级嵌入式系统（不包含 bootloader）。

它以事务的方式标识整个升级过程，事务的标识会写入到 bootloader 中，bootloader 会根据事务标记的值来确认当前升级是否成功。

比如 SWUpdate 通过设置环境变量`recovery_status`，来表示升级过程：

1. 开始升级时，其值为`progress`

2. 升级成功后，其值会被擦除

3. 升级失败，其值为`failed`

bootloader 通过查看其值为`progress`或`failed`则代表其升级未完成：

- 如果当前为`single-copy`模式，则会再次启动升级流程

- 如果当前为`double-copy`模式，则会启动上一个版本的程序

## 文件格式

![](./pic/swupdate_file_struct.jpg)

上图为其打包后的文件版本，主要是`sw-description`来实现多个镜像文件的描述。

可以看到它是将多个文件打包为一个`cpio`文件，那么这里再来复习一下`cpio`工具的操作：

```shell
### 打包
# 创建打包：通过 find 遍历当前文件及文件夹输出给 cpio
find . -depth -print | cpio -o > /path/archive.cpio


### 解包
# 可以解包所有文件
cpio -i -vd < archive.cpio
# 也可以只提取指定文件
cpio -i -d /etc/fstab < archive.cpio


### 查看
# 仅查看内容不解包
cpio -t < archive.cpio
```

**需要注意的是：** cpio 打包后的文件大小不能超过 4GB.

## 编译

在 `buildroot`中只需要搜`swupdate`就可以找到该包并使能，如果想要更细致的配置，可以通过以下命令配置：

```shell
make swupdate-menuconfig
```

在输出路径`output/build/swupdate/tools`中有文件`swupdate-progress.c`可以作为很好的参考，用于与`swupdate`交互获取当前的状态。

## 使用

`swupdate`的一般流程如下：

1. 提取`sw-description`并校验，如果还使能了签名验证，还会提取`sw-description.sig` 文件进行签名验证。

2. 根据`sw-description`中提供的信息，读取当前设备的硬件版本，来验证是否有兼容该硬件版本的软件包。

3. 根据`sw-description`中的信息识别哪些软件包需要被安装，如果具有`embedded-script`则会在解析这些软件包前执行这些脚本，如果具有`hooks`则会在解析软件包时执行（即使这些软件包会被跳过）。最终生成一张执行列表和对应的哪些`handler`需要被调用。

4. 如果有`pre update command`，则先执行这些命令

5. 如果有分区的必要，则执行`partition handlers`

6. 依次从`cpio`文件中提取需要安装的软件包，在读取软件包时还会进行内容校验，如果检验失败则报错。

7. 在安装软件包之前，如果具有`pre-install`脚本，则会先执行这些脚本

8. 执行对应软件包的`handler`来安装软件包

9. 安装完成后，如果具有`post-install`脚本，则会执行这些脚本

10. 更新 bootloader 的环境变量

11. 向外部接口输出升级状态

12. 如果具有`post update command`则执行这些命令

使用`swupdate`执行升级命令为：

```shell
swupdate -i <filename>
```

也可以启动一个网络服务，通过网页来升级：

```shell
# 启动后就可以通过 http://<target_ip>:8080 来访问
swupdate -w "--document-root ./www --port 8080"
```

## 改变 U-BOOT

`U-BOOT`可以保存两份环境变量，便于保证在更新环境变量时的安全性，要使能这个特性，需要配置`CONFIG_ENV_OFFSET_REDUND`或`CONFIG_ENV_ADDR_REDUND`。

除此之外，还可以在`U-BOOT`中增加一个启动计数器，如果计数器没有正确的被应用程序清零则意味着这个版本升级的应用没有正常运行，然后可以切换到之前备份的应用。

## 构建升级包

升级包需要`sw-updescription`是第一个文件，其余的镜像可以依次往后放即可。使用类似下面的脚本就可以打包：

```shell
CONTAINER_VER="1.0"
PRODUCT_NAME="my-software"
FILES="sw-description image1.ubifs  \
       image2.gz.u-boot uImage.bin myfile sdcard.img"
for i in $FILES;do
        echo $i;done | cpio -ov -H crc >  ${PRODUCT_NAME}_${CONTAINER_VER}.swu
```

也可以通过[GitHub - sbabic/swugenerator: A host tool to generate SWU update package for SWUpdate](https://github.com/sbabic/swugenerator/)来打包生成升级包。

升级包的查看可以通过下面的命令完成：

```shell
swupdate -c -i my-software_1.0.swu
```

# 升级策略

## single copy

![](./pic/swupdate_single_copy.jpg)

正常情况下，bootloader 直接启动用户的内核，进入文件系统运行应用程序。

当需要升级时：

1. 通知 bootloader 需要启动`swupdate`，然后重启系统
   
   - 通知的方式多种多样，比如通过环境变量、GPIO等

2. bootloader 启动带 swupdate 的内核和 RAMFS

3. 在 RAMFS 中启动`swupdate`分析升级包并升级

如果升级过程失败，应用程序无法正确清空 bootloader 的启动计数器，则 bootloader 会主动进入升级系统。

## double copy

![](./pic/swupdate_double_copy.jpg)

bootloader 交替的启动切换最新的软件，`swupdate`则升级那个未被启动的软件分区。

当当前应用程序没有正确清空 bootloader 的启动计数器时，bootloader 会主动切换回上一个版本的应用程序。

## double-copy with rescue system

![](./pic/swupdate_double_copy_rescue.jpg)

在`double-copy`的基础上，还可以增加一个救援系统，这样当两个版本都无法正确运行（或那个硬盘损坏）的情况下，仍然可以启动救援系统来重新格式化、更新系统。

> 这个救援系统也是可以被更新的

# 语法

## 示例

一个典型的`sw-description`文件内容如下：

```shell
software =
{
        version = "0.1.0";
        description = "Firmware update for XXXXX Project";

        hardware-compatibility: [ "1.0", "1.2", "1.3"];

        /* partitions tag is used to resize UBI partitions */
        partitions: ( /* UBI Volumes */
                {
                        name = "rootfs";
                        device = "mtd4";
                        size = 104896512; /* in bytes */
                },
                {
                        name = "data";
                        device = "mtd5";
                        size = 50448384; /* in bytes */
                }
        );


        images: (
                {
                        filename = "rootfs.ubifs";
                        volume = "rootfs";
                },
                {
                        filename = "swupdate.ext3.gz.u-boot";
                        volume = "fs_recovery";
                },
                {
                        filename = "sdcard.ext3.gz";
                        device = "/dev/mmcblk0p1";
                        compressed = "zlib";
                },
                {
                        filename = "bootlogo.bmp";
                        volume = "splash";
                },
                {
                        filename = "uImage.bin";
                        volume = "kernel";
                },
                {
                        filename = "fpga.txt";
                        type = "fpga";
                },
                {
                        filename = "bootloader-env";
                        type = "bootloader";
                }
        );

        files: (
                {
                        filename = "README";
                        path = "/README";
                        device = "/dev/mmcblk0p1";
                        filesystem = "vfat"
                }
        );

        scripts: (
                {
                        filename = "erase_at_end";
                        type = "lua";
                },
                {
                        filename = "display_info";
                        type = "lua";
                }
        );

        bootenv: (
                {
                        name = "vram";
                        value = "4M";
                },
                {
                        name = "addfb";
                        value = "setenv bootargs ${bootargs} omapfb.vram=1:2M,2:2M,3:2M omapdss.def_disp=lcd"
                }
        );
}
```

以`software`tag为顶层描述，下面的就是为各个镜像的单独说明。

上面中的`hardware-compatib`是为了软件与硬件的兼容，而硬件的信息则存储于`/etc/hwrevision`中，其格式为：

```shell
# boardname：设备名称，为了便于一个升级包还可以升级多种不同设备
# revision：设备的硬件版本
<boardname> <revision>
```

对于 double copy 的升级策略，一个升级包可能会对应两个分区，那么配置文件应该这样描述：

```shell
software =
{
        version = "0.1.0";

        stable = {
                copy-1: {
                        images: (
                        {
                                device = "/dev/mtd4"
                                ...
                        }
                        );
                }
                copy-2: {
                        images: (
                        {
                                device = "/dev/mtd5"
                                ...
                        }
                        );
                }
        };
}
```

在实际升级时，到底应该是选择哪个分区，则是由应用程序来区分（比如查看当前程序是挂载在哪个分区），然后给`swupdate`发送消息。

## 硬件兼容性

一个软件包可以兼容多个版本的硬件，则可以像前面一样，在文件内容开始一次性给出。但也有可能在不同的硬件版本下的文件会略有不同，那么还可以再进一步说明：

```shell
software =
{
        version = "0.1.0";

        myboard = {
            stable = {

                hardware-compatibility: ["1.0", "1.2", "2.0", "1.3", "3.0", "3.1"];
                rev-1.0: {
                        images: (
                                ...
                        );
                        scripts: (
                                ...
                        );
                }
                rev-1.2: {
                        hardware-compatibility: ["1.2"];
                        images: (
                                ...
                        );
                        scripts: (
                                ...
                        );
                }
                rev-2.0: {
                        hardware-compatibility: ["2.0"];
                        images: (
                                ...
                        );
                        scripts: (
                           ...
                        );
                }
                rev-1.3: {
                        hardware-compatibility: ["1.3"];
                        images: (
                            ...
                        );
                        scripts: (
                            ...
                        );
                }

                rev-3.0:
                {
                        hardware-compatibility: ["3.0"];
                        images: (
                                ...
                        );
                        scripts: (
                                ...
                        );
                }
                rev-3.1:
                {
                        hardware-compatibility: ["3.1"];
                        images: (
                                ...
                        );
                        scripts: (
                                ...
                        );
                }
             }
        }
}
```

如果其中有部分版本完全一致，那么还可以使用引用的方式：

```shell
software =
 {
         version = "0.1.0";

         myboard = {
             stable = {

                 hardware-compatibility: ["1.0", "1.2", "2.0", "1.3", "3.0", "3.1"];
                 rev-1x: {
                         images: (
                            ...
                         );
                         scripts: (
                             ...
                         );
                 }
                 rev1.0 = {
                         ref = "#./rev-1x";
                 }
                 rev1.2 = {
                         ref = "#./rev-1x";
                 }
                 rev1.3 = {
                         ref = "#./rev-1x";
                 }
                 rev-2x: {
                         images: (
                              ...
                         );
                         scripts: (
                              ...
                         );
                 }
                 rev2.0 = {
                         ref = "#./rev-2x";
                 }

                 rev-3x: {
                         images: (
                              ...
                         );
                         scripts: (
                               ...
                         );
                 }
                 rev3.0 = {
                         ref = "#./rev-3x";
                 }
                 rev3.1 = {
                         ref = "#./rev-3x";
                 }
              }
         }
}
```

`ref`是表示引用的关键字，后面的`#`是必须的。可以用`./`表示当前层级，用`../`表示上一个层级。

`swupdate`获取版本号是在`/etc/hwrevision`文件中，但是这个文件的内容则可以在应用程序启动时通过各种方式进行更新，比如读取当前硬件上的 EEPROM 获取版本号等。

## images

`images`标识表示要更新到系统中的镜像文件，其语法为：

```shell
images: (
        {
                filename[mandatory] = <Name in CPIO Archive>;
                volume[optional] = <destination volume>;
                device[optional] = <destination volume>;
                mtdname[optional] = <destination mtd name>;
                type[optional] = <handler>;
                /* optionally, the image can be copied at a specific offset */
                offset[optional] = <offset>;
                /* optionally, the image can be compressed if it is in raw mode */
                compressed;
        },
        /* Next Image */
        .....
);
```

对于 emmc 而言，其内容大体如下：

```shell
{
        filename = "core-image-base.ext3";
        device = "/dev/mmcblk0p1";
}
```

对于 flash 而言，其内容大体如下：

```shell
{
        filename = "u-boot.bin";
        device = "/dev/mmcblk0p1";
        offset = "16K";
}
```

## Files

`files`标识用于拷贝文件到系统，其语法如下：

```shell
files: (
        {
                filename = <Name in CPIO Archive>;
                path = <path in filesystem>;
                device[optional] = <device node >;
                filesystem[optional] = <filesystem for mount>;
                properties[optional] = {create-destination = "true";}
        }
);
```

主要就是将文件拷贝到对应路径。

## scripts

`scripts`标记用于执行一系列的脚本，默认情况下如果没有标注脚本的类型，`swupdate`会认为是`lua`脚本。

### lua

```shell
scripts: (
        {
                filename = <Name in CPIO Archive>;
                type = "lua";
        }
);
```

lua 脚本必须至少包含 3 个函数：

- `function preinst()`：安装镜像前会被执行

- `function postinst()`：安装镜像后会被执行

- `function postfailure()`：升级失败后会被执行

### shellscript

```shell
scripts: (
        {
                filename = <Name in CPIO Archive>;
                type = "shellscript";
        }
);
```

`swupdate`会在镜像安装前后执行脚本，在执行时会传入参数"preinst"、"postinst"或"postfailure"，脚本可以依据这些参数进行不同的操作。

除此之外，也可以单独编写`preinstall`和`postinstall`脚本：

```shell
scripts: (
        {
                filename = <Name in CPIO Archive>;
                type = "preinstall";
        }
);
```

```shell
scripts: (
        {
                filename = <Name in CPIO Archive>;
                type = "postinstall";
        }
);
```

## 升级过程中的标记状态

默认情况下`swupdate`通过设置 bootloader 的环境变量`recovery_status`来表示升级的过程，其值有以下几种情况：

- `in_progress`：正在升级过程中

- 值被清空：升级成功

- `failed`：升级失败

如果想关闭这些状态记录，可以在配置文件中设置：

```shell
software =
{
        version = "0.1.0";
        bootloader_transaction_marker = false;
        ...
```

除了这种字符串标记外，还有将 bootloader 的环境变量`ustate`来设数值方式：

- `1`：安装成功

- `3`：安装失败

关闭`ustate`也是在配置文件中设置：

```shell
software =
{
        version = "0.1.0";
        bootloader_state_markerer = false;
       
```

## 更新 bootloader 的环境变量

有两种方式可以更新 bootloader 的环境变量，一种方式是将变量写在文件中，然后将此文件在配置文件中标注一下：

```shell
images: (
        {
                filename = "bootloader-env";
                type = "bootloader";
        }
)
```

文件中变量赋值的格式为：`<name of variable>=<value>`，如果值不设置，则该变量会被清除掉。

就像下面这样：

```shell
# Default variables
bootslot=0
board_name=myboard
baudrate=115200

## Board Revision dependent
board_revision=1.0
```

另一种方式是直接在配置文件中就写变量：

```shell
bootenv: (
        {
                name = <Variable name>;
                value = <Variable value>;
        }
)
```

## 版本管理

`swupdate`可以进行版本号比较，默认格式为：`<major>.<minor>.<revision>.<build>`

每个小段都是由数值组成的，其值为 0~65535，4 个 16 位组合成 64 位进行大小比较。



在启动`swupdate`之前，应用软件需要更新`/etc/sw-versions`来保存各个软件包的版本，然后再来启动`swupdate`进行版本管理，文件内容格式为：

```shell
<name of component>     <version>
```

## 嵌入式脚本(Embedded Script)

嵌入式脚本指的是在`sw-description`中嵌入脚本，该脚本是对配置文件全局可见的。

```shell
embedded-script = "<Lua code>"
```

在编写脚本时需要注意：双引号应该使用转义字符进行转义，以避免影响脚本的解析。

比如：

```shell
print (\"Test\")
```

在配置文件中的镜像文件或普通文件类型都可以调用一个嵌入式脚本的函数，通过`hook`标记函数名：

```shell
files: (
        {
                filename = "examples.tar";
                type = "archive";
                path = "/tmp/test";
                hook = "set_version";
                preserve-attributes = true;
        }
);
```

一个脚本的示例如下：

```lua
function set_version(image)
        print (\"RECOVERY_STATUS.RUN: \".. swupdate.RECOVERY_STATUS.RUN)
        for k,l in pairs(image) do
                swupdate.trace(\"image[\" .. tostring(k) .. \"] = \" .. tostring(l))
        end
        image.version = \"1.0\"
        image.install_if_different = true
        return true, image
end
```

上述的`image`则为传入的参数列表，该脚本设置了版本和安装属性然后返回。
---
title: 编译内核
tags: 
- yocto
categories: 
- linux
- make
- yocto
  date: 2024/2/19
  updated: 2024/2/19
  layout: true
  comments: true
---

重新来梳理一下内核编译。

> 简单粗暴的选择 SOC / 开发板厂商所提供的内核是明智的。

<!--more-->

编译内核和编译 U-boot 类似，都是以下 3 个步骤：

1. 引用默认配置
2. 在配置上做修改
3. 编译得到镜像文件

# 内核文件分布

- `arch`：与不同架构相关的文件
- `Documentation`：内核相关文档，虽然有些文档很老了，但是依然是第一参考资料。
- `drivers`：设备驱动
- `fs`：文件系统
- `include`：内核头文件
- `init`：内核启动相关代码
- `kernel`：内核核心代码，包括调度、锁、定时器、电源管理、调试代码。
- `mm`：内存管理
- `net`：网络协议
- `scripts`：很有用的脚本
- `tools`：对开发和检查内核很有用的工具集

# KConfig

内核通过`Kbuild`来读取`Kconfig`文件进行配置。

> `Documentation/kbuild`对此做了详细解释

- `ARCH`：指定要编译的架构
  
  > 其值就是在 `arch` 目录下的子目录名

- `xxxx_defonfig`：默认的配置

## 选项类型

KConfig 的配置具有以下几种类型：

- `bool`：其值要么是`y`要么就是不会被定义
  
  > CONFIG_DEVMEM=y

- `tristate`：用于指定一个模块是被设置为模块（`m`），还是被编译进内核（`y`）

- `int`：10 进制的值

- `hex`： 16 进制的值

- `string`：字符串值

## 依赖与选择

`depends`代表当前选项依赖于其他选项：

```shell
config MTD_CMDLINE_PARTS
    tristate "Command line partition table parsing"
    # 当 CONFIG_MTD 被使能后，当前选项才会被显示
    depends on MTD
```

`select`则是用于使能其他选项：

```shell
# 当 ARM 选项被使能时，其他 select 选项指明的选项也会被使能
config ARM
    bool
    default y
    select ARCH_CLOCKSOURCE_DATA
    select ARCH_HAS_DEVMEM_IS_ALLOWED
[…]
```

## 使用 menuconfig

使用 menuconfig 需要确保`ncurses,flex,bison`被安装：

```shell
$ sudo apt install libncurses5-dev flex bison
# 然后便是基于默认配置来进一步配置
$ make ARCH=<arch> <xxx_defconfig> menuconfig
```

当开始编译内核后，会自动生成`include/generated/autoconf.h`文件，包含配置文件的宏定义，这是一个很好的用于检查的文件。

## 标记自己内核的版本

可以通过修改`General setup -> Local version`来为版本增加自己的后缀。

然后使用`make`来查看是否生效：

```shell
$ make ARCH=arm kernelrelease
```

这个输出可以与运行时的 `uname` 进行对比，以排查是否相同的内核。

# 编译内核

内核构建系统`Kbuild`从`.config`文件中获取配置，然后进行编译。

## 编译的输出类型

根据不同的 bootloader，其所需要一般内核压缩包是不一样的：

- U-Boot：一般可以适配`uImage`和`zImage`
  
  > $ make -j 4 ARCH=arm CROSS_COMPILE=arm-cortex_a8-linux-gnueabihf-  zImage

- x86：`bzImage`

- 其他的 bootloader：`zImage`

## 编译输出内核文件

编译完成后，在顶层目录会有`vmlinux`和`System.map`文件。

`vmlinux`是内核的 ELF 二进制文件，如果使能了`CONFIG_DEBUG_INFO`，那么此文件将会包含很多调试信息，可以使用`kgdb`这种工具对内核进行调试。

`System.map`文件包含内核完整的符号表。

- `Image`：`vmlinux`去掉所有调试信息后的纯净的二进制文件
- `zImage`：将`Image`文件压缩后的文件
- `uImage`：`zImage`加上 64 字节的 U-boot 头

在编译过程中，如果有编译错误，那么可以加上`V=1`选项来查看编译命令：

```shell
$ make -j 4 ARCH=arm CROSS_COMPILE=arm-cortex_a8-linux-
gnueabihf- V=1 zImage
```

## 编译设备树

设备树编译的搜寻路径也是`arch/$ARCH/boot/dts/`，所以编译设备树指定`ARCH`变量即可：

```shell
$ make ARCH=arm dtbs
```

## 编译模块

编译模块和编译内核是一样的，只是指定其编译类型是模块即可：

```shell
$ make -j 4 ARCH=arm CROSS_COMPILE=arm-cortex_a8-linux-gnueabihf- modules
```

默认情况下，`.ko`的模块文件会与源码目录在一起。

可以设置`INSTALL_MOD_PATH`来指定安装目录，模块会安装在目录的`./lib/modules/<kernel_version>`文件夹中。

```shell
$ make -j4 ARCH=arm CROSS_COMPILE=arm-cortex_a8-linux-gnueabihf- \
INSTALL_MOD_PATH=$HOME/rootfs modules_install
```

## 清理编译输出

`make`根下面几种选择来进行清理：

- `clean`：删除目标文件和其他中间文件
- `mrproper`：删除所有的中间文件，包含`.config`文件
- `distclean`：在`mrproper`的基础上，删除基本的备份文件、补丁文件等

## 编译 imx8mm 内核

为了简化编译，这里使用[米尔科技的内核分支](https://github.com/MYiR-Dev/myir-imx-linux)。

先安装基础包：

```shell
$ sudo apt install -y libssl-dev libelf-dev
```

首先需要将交叉编译工具链，加入当前 SHELL 的环境变量中：

```shell
$ export PATH=/home/cec/x-tools/aarch64-unknown-linux-gnu/bin:${PATH}
```

然后按照惯例，先清理一下中间文件：

```shell
$ make distclean
```

配置常使用的全局变量：

```shell
$ export CROSS_COMPILE=aarch64-unknown-linux-gnu-
$ export ARCH=arm64
```

接下来为内核指定要编译的构架，及其使用的默认配置：

```shell
$ make myd_imx8mm_defconfig
```

最后就是编译内核文件、模块、设备树：

```shell
$ make -j8 dtbs Image modules
```

- `Image`文件编译后位于`arch/arm64/boot/Image`
- 设备树位于`arch/arm64/boot/dts/myir/`

## 编译 bbb 内核

按照以下步骤即可：

```shell
# 清除中间文件
$ make ARCH=arm CROSS_COMPILE=arm-cortex_a8-linux-gnueabihf- 
mrproper
# 生成配置文件
$ make ARCH=arm multi_v7_defconfig
# 编译内核
$ make -j4 ARCH=arm CROSS_COMPILE=arm-cortex_a8-linux-
gnueabihf- zImage
# 编译模块
$ make -j4 ARCH=arm CROSS_COMPILE=arm-cortex_a8-linux-
gnueabihf- modules
# 编译设备树
$ make ARCH=arm CROSS_COMPILE=arm-cortex_a8-linux-gnueabihf- 
dtbs
```

# 启动内核

## 当没有文件系统时

当仅启动了内核，而没有文件系统时，就会出现内核`panic`以表示无法挂载根文件系统：

```shell
[ 1.886379] Kernel panic - not syncing: VFS: Unable to mount 
root fs on unknown-block(0,0)
[ 1.895105] ---[ end Kernel panic - not syncing: VFS: Unable to 
mount root fs on unknown-block(0, 0)
```

为了将系统从内核态切换到用户态，内核需要挂载根文件系统，然后执行根文件系统中的初始化程序。

这个是开始于执行`init/main.c`中的`rest_init()`函数，它会创建一个 PID 为 1 的进程，然后执行`kernel_init()`。

接着尝试执行`/init`程序，如果执行失败则会尝试执行`prepare_namespace()`函数，这个函数会读取`root=`命令行参数，挂载对应的分区，`root`命令一般如下：

```shell
root=/dev/<disk name><partition number>
# 或者对于 emmc/sd 设备
root=/dev/<disk name>p<partition number>
```

挂载成功后，将会依次尝试执行`/sbin/init,/etc/init,/bin/init,/bin/sh`，其中任何一个执行成功了，后面的便不会被执行了。

> 当然也可以设定`init=`参数来指定执行哪个特定的程序。

## 内核的命令行参数

目标内核的命令行参数都是通过设备树中的`bootargs`属性来设定了，在`Documentation/kernel-parameters.txt`有参数的详细说明，下面是一些常用的参数：

- `debug`：设置调试信息输出等级，小于该数值的调试信息将被输出

- `init=`：在挂载根文件系统后，所运行的`init`程序路径

- `lpj=`：设置`loops_per_jiffy`以降低开机测试所消耗的时间

- `panic=`：当内核出现 panics 时的行为
  
  > 小于 0：当出现 panic 则立即重启
  > 
  > 等于 0（默认）：当出现 panic 不重启
  > 
  > 大于 0：当出现 panic 时，等待多少秒后重启

- `quiet`：除了紧急信息，其他的调试信息都不输出

- `rdinit=`：与`init=`一致，不过这个是针对 `ramdisk`的

- `ro`：以只读的方式挂载根文件系统

- `root=`：指定挂载根文件系统的设备

- `rootdelay=`：等待多少秒后才挂载根文件系统，用于等待设备初始化完成

- `rootfstype=`：指定根文件系统的类型，默认情况下都是自动检测的

- `rootwait`：一直等到设备初始化完毕以后，才挂载根文件系统

- `rw`：以读写的方式挂载根文件系统

## imx8mm 内核启动

### 制作启动 SD 卡

从 Uboot 中的启动命令可知：它将在 mmc 的 1 分区中寻找`Image`文件和对应的设备树。

并且，前面我们将由[imx-mkimage](https://source.codeaurora.org/external/imx/imx-mkimage)打包的 bootloader 拷贝到了 SD 卡的 33K 偏移处，也就是说需要保留这部分裸数据，前面制作好的`flash.bin`有 1M 多的大小，需要考虑好这个偏移。

1. 由于 SD 卡是 512 字节的扇区，先用 fdisk 简单粗暴的将第一个分区的起始扇区设为 20480，这样就预留了有 10MB 的空间给 bootloader。

2. 使用`sudo mkfs.vfat /dev/sdd1`将分区格式化为 FAT32 格式

3. 将编译得到的`Image`和`myb-imx8mm-base.dtb`拷贝到 SD 卡分区
   
   > 这里选择 `myb-imx8mm-base.dtb`，是因为前面打包 bootloader 也是这个设备树

4. 修改 U-boot 默认环境变量`fdt_file`的值为`myb-imx8mm-base.dtb`，这样才能一一对应

## bbb 启动

将编译好的`zImage`和`am335x-boneblack.dtb`拷贝到 SD 卡中，启动 u-boot 后。

首先，读取内核到内存：

```shell
fatload mmc 0:1 0x80200000 zImage
```

然后，读取设备树到内存：

```shell
fatload mmc 0:1 0x80f00000 am335x-boneblack.dtb
```

设置终端设备：

```shell
setenv bootargs console=ttyO0
```

使用 `bootz` 启动：

```shell
bootz 0x80200000 - 0x80f00000
```



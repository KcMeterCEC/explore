---
title: 构建根文件系统
tags: 
- yocto
categories: 
- linux
- make
- yocto
date: 2024/2/27
updated: 2024/2/27
layout: true
comments: true
---

重新来梳理一下根文件系统编译。

<!--more-->

# 根文件系统里面有什么？

内核挂载根文件系统，可以以`initramfs`的方式，或者通过`root=`参数指定的设备来挂载，然后执行其`init`程序来进行接下来的初始化。

最小的根文件系统包含下面这些基本组件：

- `init`：用于初始化系统基本环境的程序，通常会调用一系列的脚本
- `shell`：提供一个用于交互的命令行环境，以执行其他的程序
- `Daemons`：守护进程为其他程序提供基础服务
- `Shared libraries`：很多程序都会使用到共享库，所以这个是必须的
- `Configuration files`：对守护进程对应的配置文件，通常位于`/etc`目录下
- `Device nodes`：设备节点提供应用程序的访问设备驱动的通道
- `proc and sys`：提供对内核参数的检测和控制文件夹
- `Kernel modules`：内核模块会被安装于`/lib/modules/<kernel versoin>/`中

## 目录的分布

为满足 FHS（Filesystem Hierarchy Standard）标准，一般目录分布如下：

- `/bin`：对所有用户都适用的基础命令
- `/dev/`：存放设备节点和其他特殊文件
- `/etc/`：系统配置文件
- `/lib`：系统基本的共享库
- `/proc`：对进程等内核参数进行交互的虚拟文件
- `/sbin`：对系统管理员所适用的基础命令
- `/sys`：描述设备何其驱动对应关系的虚拟文件
- `/tmp`：用于存放临时文件的 RAM fs
- `/usr`：更多的命令、库、管理员工具等
- `/var`：存放在运行时会被改变的文件

对于 `proc`和`sysfs`是需要挂载的：

```shell
$ mount [-t vfstype] [-o options] device directory
# 挂载存储设备时，大部分情况下不用主动指明文件系统
# 而对于 proc,sysfs 这种伪文件系统，则需要指明
# mount -t proc proc /proc
# mount -t sysfs sysfs /sys
```

## 创建`staging`文件夹

所谓的`staging`文件夹，就是一个根文件系统的基础框架，在最开始可以创建它：

```shell
$ mkdir ~/rootfs
$ cd ~/rootfs
$ mkdir bin dev etc home lib proc sbin sys tmp usr var
$ mkdir usr/bin usr/lib usr/sbin
$ mkdir -p var/log
# 对于 ARM64 lib 引用的是 lib64，其实只需要为 lib 创建软链接即可
$ ln -s lib lib64
```

接下来就是要考虑一些文件的权限问题了，对于一些重要文件应该限制为`root `用户才能操作。而其他程序应该运行在普通用户模式。

## 目录中具有的程序

### `init`程序

`init`程序是进入根文件系统后运行的第一个程序。

> 对于 busybox 而言，就是`/sbin/init`，最终还是指向 busybox 这个独立可执行程序。

`init`程序首先会读取`/etc/inittab`中的配置，然后依次启动对应的程序。

### Shell

`Shell`用户运行脚步，和用户交互等。在嵌入式系统中，有这么几个常用的`Shell`：

- `bash`：功能强大，但是体积占用也大，一般运行于桌面系统中。
- `ash`：和`bash`兼容性很好，且体积占用小，适合于嵌入式系统。
- `hush`：用于 bootloader，占用很小的 shell。

其实只要空间不紧张，嵌入式也使用`bash`就好，因为和桌面系统完全一致，避免在桌面可以正常运行的脚本在嵌入式端运行就不正常了。

### 工具程序

工具程序用于支撑其他程序的正常运行。

## BusyBox

### 原理

这些程序要是手动编译一个个放入文件系统会累死，而`BusyBox`就将这些工具精简编译到一个可执行程序中，这个程序就包含了常用的命令。

```shell
 busybox.nosuid
 cat -> /bin/busybox.nosuid
 chgrp -> /bin/busybox.nosuid
 chmod -> /bin/busybox.nosuid
 chown -> /bin/busybox.nosuid
 cp -> /bin/busybox.nosuid
 cpio -> /bin/busybox.nosuid
 date -> /bin/busybox.nosuid
 dd -> /bin/busybox.nosuid
 df -> /bin/busybox.nosuid
 dmesg -> /bin/busybox.nosuid
```

当用户输入`cat`时，实际上是调用了`busybox`这个可执行文件，该文件按照如下流程处理：

- 获取`argv[0]`得到字符串`cat`
- 然后根据该字符串获取到对应入口函数`cat_main`
- 执行`cat_main`

### 构建 BusyBox

首选获取源码：

```shell
$ git clone https://git.busybox.net/busybox
```

然后切换到最新稳定版：

```shell
$ git checkout 1_34_stable
```

按照惯例，当然是先clean 一下：

```shell
$ make distclean
```

使用其默认配置即可：

```shell
$ make defconfig
```

然后使用`make menuconfig` 进入`Settings -> Cross compiler prefix`来设置安装路径到前面的 staging 目录。

接下来便是编译及安装：

```shell
$ export CROSS_COMPILE=arm-cortex_a8-linux-gnueabihf-
$ export ARCH=arm
$ make
$ make install
```

可以看到 staging 目录中已经安装好了，且那些文件都以软连接的形式指向了`busybox`这个可执行文件。

## 根文件系统中的库

应用程序要运行，就要依赖部分编译工具链中的库，简单粗暴的解决方式就是把这些库都拷贝到 staging 目录中。

```shell
# 以 SYSROOT 存储路径，比较方便
$ export SYSROOT=$(arm-cortex_a8-linux-gnueabihf-gcc -print-sysroot)
```

其中`lib`文件夹存储得是共享链接库，将它们复制进去即可：

```shell
# 使用 -a ，不破坏其软连接
cec@box:~/lab/rootfs$ cp -aR ${SYSROOT}/lib/** ./lib/
```

## 设备节点

创建设备节点使用命令`mknod`：

```shell
# 依次是设备节点名称，类型，主设备号，次设备号
$ mknod <name> <type> <major> <minor>
```

> 主设备号和次设备号可以在 `Documentation/devices.txt`文件中找到

对于 BusyBox 而言，所需要的两个节点是`console`和`null`：

```shell
# null 节点所有用户都可以读写，所以权限是 666
$ sudo mknod -m 666 dev/null c 1 3
# console 节点只允许 root 操作，所以权限是 600
$ sudo mknod -m 600 dev/console c 5 1
```

## 内核模块

内核模块也需要被安装在根文件系统中，需要被内核设置`INSTALL_MOD_PATH`：

```shell
# 由于前面已经设置了 ARCH 和 CROSS_COMPILE 所以这里就不用设置了
$ make INSTALL_MOD_PATH=/home/cec/lab/rootfs modules_install
```

可以看到模块都被安装到了根文件系统的`lib/modules/<kernel_version>`目录下了。

> 但是会发现还安装了`source`和`build`文件夹，这个是嵌入式中不需要的，可以把它们删除。

# 创建 initramfs

在使用`initramfs`之前需要确保`CONFIG_BLK_DEV_INITRD=y`，以表示内核支持`initramfs`。

创建`initramfs`有以下 3 种方法：

1. 独立打包为`cpio`格式的文件包：这种方式最为灵活
2. 将`initramfs`嵌入到内核镜像文件中
3. 由内核构建系统将其编译进去

## 创建一个独立包

先打包到上级目录：

```shell
# 指定了 GID 和 UID 都是 root
cec@box:~/lab/rootfs$ find . | cpio -H newc -ov --owner root:root >  ../initramfs.cpio
```

然后再进行一次压缩：

```shell
cec@box:~/lab/rootfs$ gzip initramfs.cpio
```

最后使用工具`mkimage`来为文件加入头：

```shell
cec@box:~/lab$ mkimage -A arm -O linux -T ramdisk -d initramfs.cpio.gz uRamdisk
Image Name:   
Created:      Fri Mar  1 09:18:49 2024
Image Type:   ARM Linux RAMDisk Image (gzip compressed)
Data Size:    27835346 Bytes = 27182.96 KiB = 26.55 MiB
Load Address: 00000000
Entry Point:  00000000
```

需要注意的是：**initramfs 包体积不能太大，因为压缩包和解压后的文件都会全部存在于内存中！** 

> [这篇文章](https://www.lightofdawn.org/blog/?viewDetailed=00128)有讲到，`initramfs`包最好小于内存的 25%

## 启动独立包

### 拷贝进 SD 卡

作为测试目的，我们可以将`uRamdisk`也拷贝到 SD 卡的第一分区，然后在 U-boot 中载入。

### 载入到 DDR

然后需要将`initramfs`载入到 DDR 中，前面我们将：

- Image 载入到 `0x80200000`
- FDT 载入到 `0x80f00000`

而 FDT 目前大小只有 58KB，那么可以将`uRamdisk`载入到`0x81000000`

```shell
$ fatload mmc 0:1 0x80200000 zImage
$ fatload mmc 0:1 0x80f00000 am335x-boneblack.dtb
$ fatload mmc 0:1 0x81000000 uRamdisk
```

3. 指定启动的`init`程序

需要在`bootargs`中加入启动程序是 shell：`rdinit=/bin/sh`

```shell
$ setenv bootargs console=ttyO0,115200 rdinit=/bin/sh
```

3. 使用 booti 启动

也就是说在原来的基础上，加上`initramfs`的地址即可：

```shell
# $ bootz ${loadaddr} ${initrd_addr} ${fdt_addr}
$ bootz 0x80200000 0x81000000 0x80f00000
```

这个时候会发现没有工作控制流而给出警告：

```shell
/bin/sh: can't access tty; job control turned off
```

## 将 initramfs 嵌入内核

将`initramfs`嵌入内核非常简单：在`General setup -> Initramfs source file(s)`中指定**未压缩的 cpio 文件**，然后再次运行 make 即可。

这样设置以后，便可以在 bootloader 中指定内核和设备树地址就行了。

> 这里需要注意内核 + initramfs 所占用的空间，设备树需要预留足够多的空间以避免相互覆盖。
> 
> 比如当前内核 + initramfs 就有 50MB，那么设备树的载入位置需要再往后放一点。
> 
> 当前开发板具有 512MB 内存，那 DDR 寻址范围是 0x80000000 ~ 0xA0000000。
> 
> 所以设备树的位置预留足够位置即可，比如放置在 0x8CA00000 处，就预留了 200MB 的空间。

编译进内核以后，启动命令就简单了一点：

```shell
fatload mmc 0:1 0x80200000 zImage
fatload mmc 0:1 0x8CA00000 am335x-boneblack.dtb
setenv bootargs console=ttyO0,115200 rdinit=/bin/sh
bootz 0x80200000 - 0x8CA00000
```

## 以设备列表的形式构建 initramfs

设备列表就是一个配置文件，用以列出文件、文件夹、设备节点、链接等等。

在构建内核的时候，也就会生成按照设备列表配置的 cpio 文件。

和上面的方式一样，在内核的`Initramfs source file(s)`处指向该配置文件。

`cpio`文件就会在编译时创建。

下面是一个简单的示例：

```shell
# dir <name> <mode> <uid> <gid>
dir /bin 775 0 0
dir /sys 775 0 0
dir /tmp 775 0 0
dir /dev 775 0 0
# nod <name> <mode> <uid> <gid> <dev_type> <maj> <min>
nod /dev/null 666 0 0 c 1 3
nod /dev/console 600 0 0 c 5 1
dir /home 775 0 0
dir /proc 775 0 0
dir /lib 775 0 0
# slink <name> <target> <mode> <uid> <gid>
slink /lib/libm.so.6 libm-2.22.so 777 0 0
slink /lib/libc.so.6 libc-2.22.so 777 0 0
slink /lib/ld-linux-armhf.so.3 ld-2.22.so 777 0 0
# file <name> <location> <mode> <uid> <gid>
file /lib/libm-2.22.so /home/chris/rootfs/lib/libm-2.22.so 755 
0 0
file /lib/libc-2.22.so /home/chris/rootfs/lib/libc-2.22.so 755 
0 0
file /lib/ld-2.22.so /home/chris/rootfs/lib/ld-2.22.so 755 0 0
```

可以使用内核文件`/usr/gen_initramfs_list.sh`来根据前面的 rootfs 生成一个配置文文件：

```shell
$ ./usr/gen_initramfs_list.sh -u 1000 -g 1000 ~/lab/rootfs > initramfs-device-table
```

# 完整启动 initramfs

前面的启动过程，会由于 initramfs 缺少文件而退出 shell，而正确的启动流程是：

1. 内核启动`/sbin/init`程序
2. `/sbin/init`读取`/etc/inittab`确定启动级别及运行 shell
3. 根据`/etc/inittab`中的内容找到`/etc/init.d/rcS`然后依次运行对应脚本进行环境初始化

而`busybox`在其源码`examples/bootfloppy/etc/`中就提供了通用的示例，将其拷贝到我们创建的`rootfs`中是比较简单的方法：

```shell
cec@box:~/lab/rootfs$ cp -aR ../busybox/examples/bootfloppy/etc/** etc/
```

## inittab 修改

作为测试目的，对其进行简单修改：

```shell
# 启动初始化脚本为 /etc/init.d/rcS
::sysinit:/etc/init.d/rcS
# 虚拟终端作为 shell
::askfirst:-/bin/sh
```

## rcS 修改

在 `rcS`脚本中，需要至少挂载`proc,sys`两个虚拟文件系统：

```shell
#!/bin/sh
mount -t proc proc /proc 
mount -t sysfs sysfs /sys
```

修改以后再次打包为 cpio 文件，对应的 bootargs 就可以修改：

```shell
fatload mmc 0:1 0x80200000 zImage
fatload mmc 0:1 0x8CA00000 am335x-boneblack.dtb
setenv bootargs console=ttyO0,115200 rdinit=/sbin/init
bootz 0x80200000 - 0x8CA00000
```

## 增加用户配置

`busybox`默认会支持 shadow 特性，这需要添加用户配置文件。

用户名及相关信息被配置于`/etc/passwd`文件中，每个用户一行，中间以冒号分开，依次是：

- 用户名

- `x`代表密码存储于`/etc/shadow`
  
  > `/etc/passwd`是所有人可读的，而`/etc/shadow`则只能是 root 用户和组可以读，以此来保证安全性。

- 用户 ID

- 组 ID

- 注释

- 用户的`home`目录

- 用户所使用的 shell

```shell
root:x:0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/bin/false
```

组名称则存储于`/etc/group`中，也是每个组一行，中间以冒号分开：

- 组名
- 组密码，`x`代表该组没有密码
- 组 ID
- 那些用于属于该组

```shell
root:x:0:
daemon:x:1:
```

`/etc/shadow` 中的示例内容如下：

```shell
root::10933:0:99999:7:::
daemon:*:10933:0:99999:7:::
```

在 rootfs 中加入这几个文件，其中 **/etc/shadow** 需要修改权限为 600，以便只有 root 可以打开此文件。

然后再编辑 `etc/inittab` 让初始启动程序为 getty 获取用户名及密码验证：

```shell
::sysinit:/etc/init.d/rcS
# respawn 代表当一个用户退出后，又重新启动 getty
::respawn:/sbin/getty 115200 console
```

# 创建设备节点更好的方法

`mknod`创建设备节点比较繁琐，还有其他更好的办法：

- `devtmpfs`：这是在启动时被挂载到`/dev`的伪文件系统。内核通过它来动态的增加和删除设备节点。
- `mdev`：由 busybox 提供的工具，通过读取`/etc/mdev.conf`来达到自动挂载节点的目的
- `udev`：功能和`udev`类似，现在属于`systemd`的一部分

在实际使用中，一般是通过`devtmpfs`来自动创建节点，而`mdev/udev`来设置节点的属性。

## `devtmpfs`

在使用`devtmpfs`之前，需要确保内核已经使能了`CONFIG_DEVTMPFS`。

> 如果使能了 CONFIG_DEVTMPFS_MOUNT 内核会自动挂载该文件系统，只是不适用于 initramfs

然后在启动脚本中挂载`devtmpfs`：

```shell
mount -t devtmpfs devtmpfs /dev
```

## `mdev`

在使用`mdev`之前，需要在启动脚本中将其设置为接收内核发送的`hotplug`事件，然后再启动`mdev`：

```shell
echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s
```

`mdev`会根据`/etc/mdev.conf`文件来配置节点的属性：

```shell
# file /etc/mdev.conf
null root:root 666
random root:root 444
urandom root:root 444
```

关于 `mdev`更多说明，参考 busybox 源码中的 `docs/mdev.txt`文件。

# 网络配置

## 基本配置

与网络配置相关的文件有：

```shell
etc/network
etc/network/if-pre-up.d
etc/network/if-up.d
etc/network/interfaces
var/run
```

其中`interfaces`中是对网络的配置：

```shell
auto lo
iface lo inet loopback

# 配置 eth0 为静态 IP
auto eth0
iface eth0 inet static
    address 192.168.1.101
    netmask 255.255.255.0
    network 192.168.1.0

# 也可以这样配置，使用动态 IP
# auto eth0
# iface eth0 inet dhcp
# iface eth1 inet dhcp    
```

对于动态 IP，busybox 使用 `udchpcd`运行`/usr/share/udhcpc/default.script`来完成配置，可以拷贝`examples/udhcp/simple.script`来完成。

## 字符串映射

glibc 使用 `name service switch（NSS）`来实现从名称到特定数值的转换。

比如从用户名转换到 UID，从服务器名称转换到端口号，从主机名称转换到 IP 地址等。

这些配置被存储于`/etc/nssswitch.conf`文件中：

```shell
passwd:    files # 查询 UID ，就在 /etc/passwd
group:     files
shadow:    files
hosts:     files dns # 查询主机就在 /etc/hosts，如果查询不到就从 DNS 查询
networks:  files
protocols: files
services:  files # 查询端口号，就在 /etc/services
```

这些文件完全可以在当前主机中拷贝，这些文件都是有统一格式的。

最后还需要安装库以便于正确执行名称查找：

```shell
$ cd ~/rootfs
$ cp -a $SYSROOT/lib/libnss* lib
$ cp -a $SYSROOT/lib/libresolv* lib
```

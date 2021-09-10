---
title: '[What]Building a Root Filesystem'
tags: 
- CS
categories: 
- book
- Embedded Linux Programming
layout: true
---

学习书籍：[Mastering Embedded Linux Programming: Create fast and reliable embedded solutions with Linux 5.4 and the Yocto Project 3.1 (Dunfell), 3rd Edition](https://www.amazon.com/Mastering-Embedded-Linux-Programming-potential/dp/1789530385)
> 通过阅读这部书，将整个嵌入式 Linux 的开发知识串联起来，以整理这些年来所学的杂乱知识。

- 开发主机：ubuntu 20.04 LTS
- 开发板：[myc-c8mmx-c](http://www.myir-tech.com/product/myc-c8mmx.htm) imx8mm（4核 A53 + M4）
- 系统：Linux 5.4
- yocto：3.1

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

``` shell
$ mkdir ~/rootfs
$ cd ~/rootfs
$ mkdir bin dev etc home lib proc sbin sys tmp usr var
$ mkdir usr/bin usr/lib usr/sbin
$ mkdir -p var/log
```

接下来就是要考虑一些文件的权限问题了，对于一些重要文件应该限制为`root `用户才能操作。而其他程序应该运行在普通用户模式。



## 目录中具有的程序

### `init`程序

`init`程序是进入根文件系统后运行的第一个程序。

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

然后使用`make menuconfig` 进入`Busybox Settings -> Installation Options`来设置安装路径到前面的 staging 目录。

接下来便是编译及安装：

```shell
$ export CROSS_COMPILE=aarch64-unknown-linux-gnu-
$ export ARCH=arm64
$ make
$ make install
```

可以看到 staging 目录中已经安装好了，且那些文件都以软连接的形式指向了`busybox`这个可执行文件。

## 根文件系统中的库

应用程序要运行，就要依赖部分编译工具链中的库，简单粗暴的解决方式就是把这些库都拷贝到 staging 目录中。

```shell
# 以 SYSROOT 存储路径，比较方便
$ export SYSROOT=$(aarch64-unknown-linux-gnu-gcc -print-sysroot)
```

其中`lib`文件夹存储得是共享链接库，将它们复制进去即可：

```shell
# 使用 -a ，不破坏其软连接
cec@imx8:~/myb/rootfs$ cp -aR ${SYSROOT}/lib/** ./lib/
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
$ make INSTALL_MOD_PATH=/home/cec/myb/rootfs modules_install
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
cec@imx8:~/myb/rootfs$ find . | cpio -H newc -ov --owner root:root >  ../initramfs.cpio
```

然后再进行一次压缩：

```shell
cec@imx8:~/myb$ gzip initramfs.cpio
```

最后使用工具`mkimage`来为文件加入头：

```shell
cec@imx8:~/myb$ ./bootloader/myir-imx-uboot/tools/mkimage -A arm64 -O linux -T ramdisk -d initramfs.cpio.gz uRamdisk

disk
Image Name:   
Created:      Fri Sep 10 13:53:24 2021
Image Type:   AArch64 Linux RAMDisk Image (gzip compressed)
Data Size:    193404777 Bytes = 188871.85 KiB = 184.45 MiB
Load Address: 00000000
Entry Point:  00000000
```

## 启动独立包

### 拷贝进 SD 卡

作为测试目的，我们可以将`uRamdisk`也拷贝到 SD 卡的第一分区，然后在 U-boot 中载入。

### 载入到 DDR

然后需要将`initramfs`载入到 DDR 中，前面我们将：

- Image 载入到 `0x40480000`
- FDT 载入到 `0x43000000`

而 FDT 目前大小只有 42KB，那么可以将`uRamdisk`载入到`0x43800000`

```shell
$ env set initrd_addr 0x43800000
$ env save
$ fatload mmc ${mmcdev}:${mmcpart} ${initrd_addr} uRamdisk

193404841 bytes read in 2230 ms (82.7 MiB/s)
```

3. 指定启动的`init`程序

需要在`bootargs`中加入启动程序是 shell：`rdinit=/bin/sh`

```shell
$ env set bootargs console=ttymxc1,115200 earlycon=ec_imx6q,0x30890000,115200 rdinit=/bin/sh
$ env save
```

3. 使用 booti 启动

也就是说在原来的基础上，加上`initramfs`的地址即可：

```shell
$ booti ${loadaddr} ${initrd_addr} ${fdt_addr}
```






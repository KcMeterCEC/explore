---
title: Buildroot 的定制化使用
tags: 
- yocto
categories: 
- linux
- make
- yocto
date: 2024/4/9
updated: 2024/4/9
layout: true
comments: true
---

这里记录 Buildroot 的进一步使用说明。

<!--more-->

# 构建过程时修改源码

Buildroot 构建的过程是下载压缩包、解压、配置、编译、安装，就算包的源是 git 这种版本管理工具，它也会克隆并压缩，然后按照之前的流程进行。

默认情况下，解压缩后的源码会位于 `output/build/<package>-<version>`，当使用 `make clean` 之后，该目录的内容会被清空！

所以，如果想修改源码再进行打包验证的话，直接在这个目录下操作是不合理的。

Buildroot 提供了 `<pkg>_OVERRIDE_SRCDIR` 机制，让 Buildroot 选择指定的源码路径。

默认在通过 `BR2_PACKAGE_OVERRIDE_FILE` 配置的覆盖文件是 `$(CONFIG_DIR)/local.mk`，而 `$(CONFIG_DIR)` 指的就是 `.config` 文件所在的路径。

所以 `local.mk` 也就是默认和 `.config` 在一个文件夹下。`local.mk` 的文件格式为：

```shell
<pkg1>_OVERRIDE_SRCDIR = /path/to/pkg1/sources
<pkg2>_OVERRIDE_SRCDIR = /path/to/pkg2/sources
```

比如:

```shell
LINUX_OVERRIDE_SRCDIR = /home/bob/linux/
BUSYBOX_OVERRIDE_SRCDIR = /home/bob/busybox/
```

当指定了特定包的路径后，Buildroot 就不会走下载、解压的步骤，而是直接使用指定路径的源码。在执行编译时，buildroot 会将源码拷贝到指定目录下的 `<package>-custom`。

然后就可以使用：

- make <pkg>-rebuild ： 重新编译
- make <pkg>-reconfig ： 重新配置
- make <pkg>-rebuild all : 重新配置并编译

# 常用的配置步骤

使用 Buildroot 的一般配置步骤如下：

- 配置 Buildroot 基本配置，比如工具链、bootloader、内核、文件系统等

- 配置其他组件，比如 BusyBox、Qt 等

- 进行文件系统定制化配置
  
  - 根据配置`BR2_ROOTFS_OVERLAY`,将需要覆盖的配置文件、应用程序按照文件系统结构放置
  
  - 根据配置`BR2_ROOTFS_POST_BUILD_SCRIPT`指定的脚本，修改或删除文件
  
  - 根据配置`BR2_ROOTFS_DEVICE_TABLE`来修改特定文件的权限
  
  - 根据配置`BR2_ROOTFS_STATIC_DEVICE_TABLE`来增加特定的设备节点
  
  - 根据配置`BR2_ROOTFS_USERS_TABLES`来添加用户
  
  - 根据配置`BR2_ROOTFS_POST_IMAGE_SCRIPT`指定的脚本来生成镜像文件
  
  - 根据配置`BR2_GLOBAL_PATCH_DIR`来添加对应包的补丁

# 推荐的定制化目录

```shell
+-- board/
| +-- <company>/
|     +-- <boardname>/
|         +-- linux.config
|         +-- busybox.config
|         +-- <other configuration files>
|         +-- post_build.sh
|         +-- post_image.sh
|         +-- rootfs_overlay/
|         |     +-- etc/
|         |     +-- <some files>
|         +-- patches/
|             +-- foo/
|             |     +-- <some patches>
|             +-- libbar/
|                 +-- <some other patches>
|
+-- configs/
|     +-- <boardname>_defconfig
|
+-- package/
| +-- <company>/
|         +-- Config.in (if not using a br2-external tree)
|         +-- <company>.mk (if not using a br2-external tree)
|         +-- package1/
|         |     +-- Config.in
|         |     +-- package1.mk
|         +-- package2/
|             +-- Config.in
|             +-- package2.mk
|
+-- Config.in (if using a br2-external tree)
+-- external.mk (if using a br2-external tree)
+-- external.desc (if using a br2-external tree)
```

以上的目录结构既可以在 Buildroot 上建立一个分支，也可以在 Buildroot 目录之外建立。

如果在目录之外建立，那么在首次构建时，需要设置变量`BR2_EXTERNAL`：

```shell
$ make BR2_EXTERNAL=/path/to/foo menuconfig
```

该设置会被保存在 output 目录的 `.br2-external.mk` 文件中，下次再构建就可以不用再次设置了。

如果要切换到新目录，就再设置一次该变量即可。也可以关闭使用外部目录：

```shell
$ make BR2_EXTERNAL= menuconfig
```

# 保存配置

## Buildroot 的整体配置

简单的方式：

```shell
make savedefconfig
```

将当前配置保存为文件`defconfig`，也可以存放在其他位置：

```shell
make savedefconfig BR2_DEFCONFIG=<path-to-defconfig>
```

最简单的方式还是存在`configs/<boardname>_defconfig`

## 其他软件包的配置

对于像 U-Boot，Linux 的配置，也应该需要保存。保存的位置根据前面所述，位于`board/<company>/<boardname>/`中最好。

可以使用`make linux-menuconfig`来创建 linux 的配置文件。

- `make linux-update-defconfig`将配置存储于`BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE`指定的路径中

- `make busybox-update-config`将配置存储于`BR2_PACKAGE_BUSYBOX_CONFIG`指定的路径中

- `make uboot-update-defconfig`将配置存储于 `BR2_TARGET_UBOOT_CUSTOM_CONFIG_FILE`指定的路径中

# 定制文件系统

定制文件系统有两种方式，一种是覆盖文件系统，一种是通过预构建脚本。

## 覆盖 (`BR2_ROOTFS_OVERLAY`)

配置`BR2_ROOTFS_OVERLAY`指定了覆盖目录的路径，Buildroot 会按照该目录的路径对文件系统进行覆盖。

比较推荐的路径是`board/<company>/<boardname>/rootfs-overlay`

# 构建脚本(`BR2_ROOTFS_POST_BUILD_SCRIPT`)

在 Buildroot 构建了软件但还没有打包镜像文件时，会运行该配置指定的脚本。

这种方式更为灵活，可以删除、编辑目标板上的文件。

比较推荐的路径是``board/<company>/<boardname>/post_build.sh`.`

该脚本被调用时，传入的第一个参数，就是目标文件系统的路径。

除此之外，还有其他变量可以使用：

- `BR2_CONFIG`：Buildroot .config 文件路径

- `CONFIG_DIR`：包含 .config 的目录路径

- ``HOST_DIR`, `STAGING_DIR`, `TARGET_DIR``

- `BUILD_DIR`：构建路径

- `BINARIES_DIR`：镜像文件的存放路径

- `BASE_DIR`：输出路径

# 设置文件权限和所有人

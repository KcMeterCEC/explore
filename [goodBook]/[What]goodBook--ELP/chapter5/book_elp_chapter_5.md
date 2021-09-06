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

## `staging`文件夹

所谓的`staging`文件夹，就是一个根文件系统的基础框架，在最开始可以创建它：

``` shell
$ mkdir ~/rootfs
$ cd ~/rootfs
$ mkdir bin dev etc home lib proc sbin sys tmp usr var
$ mkdir usr/bin usr/lib usr/sbin
$ mkdir -p var/log
```

## POSIX 文件的访问权限


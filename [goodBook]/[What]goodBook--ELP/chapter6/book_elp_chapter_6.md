---
title: '[What]Selecting a Build System'
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

前面已经手撸了整个嵌入式系统的构建过程，但是在实际工作中，尤其是根文件系统的建立是很费时间的。这个时候一个自动化的构建工具就非常重要了。

自动化构建工具，需要能完成：
1. 自动化的获取源码（不管是网络还是本地）
2. 为源码打补丁，并进行一些配置
3. 完成构建
4. 将构建的文件组织成根文件系统
5. 最终可以将多个镜像文件打包并装载到目标机。

以上的过程都是可以用户灵活配置的，并可以输出 SDK 便于多个开发人员的环境统一。

目前有以下自动化构建工具：
1. [Buildroot](https://buildroot.org/)：使用 Make 和 Kconfig 的构建工具，非常易于使用。
2. [EmbToolkit](https://www.embtoolkit.org/)：用于构建跟文件系统和工具链的简单构建工具
3. [OpenEmbedded](https://openembedded.org/)：功能强大的构建系统，是 Yocto 的核心组件
4. [OpenWrt](https://openwrt.org/)：专用于构建无线路由器软件包的工具
5. [PTXdist](https://www.ptxdist.org/)：简单的构建工具
6. [Yocto](https://www.yoctoproject.org/)基于 OpenEmbedded 扩展的元数据、工具、文档集，更为强大的构建工具

其中就属 Yocto 最完善，所以这里只关注 Yocto。

<!--more-->




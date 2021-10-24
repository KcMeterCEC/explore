---
title: '[What] linux PCIE: 驱动对设备的操作'
tags: 
- operations
date: 2021/10/20
categories: 
- linux
- operations
- PCIE
layout: true
---

学习视频：[GNU/Linux & PCI(Express)](https://www.youtube.com/playlist?list=PLCGpd0Do5-I1hZpk8zi9Zh7SCnHrIQlgT)

当 PCI 设备被分配了地址后，驱动便是对该设备的地址进行操作。

<!--more-->

# 回顾 io mem 操作

既然 PCI 设备已经被映射到了 io mem，那么其操作应该就和 io mem 类似。

回顾一下对 io mem 的操作流程如下：

1. 使用 `request_mem_region()`函数申请驱动要对一段物理内存操作
2. 使用`ioremap()`函数将一段物理内存映射到虚拟内存以准备操作
3. 使用`readb(),readl(),writeb(),writel()`等函数，对映射的内存进行操作
4. 使用`iounmap()`取消对物理内存的映射
5. 使用`release_mem_region()`对申请的物理内存进行释放

# 查看 PCI io mem 操作

其实 PCI 的操作和 io mem 操作几乎一致，也是根据 IO 端口/内存资源调用对应的 API 即可，这里以 IO 内存资源为例：

1. 使用`pci_request_mem_regions()`选择对设备的一个 BAR 进行申请操作
2. 使用`pcim_iomap()`对 BAR 对应的物理内存映射到虚拟内存
3. 使用`readb(),readl(),writeb(),writel()`等函数，对映射的内存进行操作
4. 使用`pcim_iounmap()`取消对物理内存的映射
5. 使用`pci_release_mem_regions()`对 BAR 对应的物理内存释放

只不过，在进行以上步骤以前，需要先找到设备：

1. 使用`pci_get_device()`对指定的 VID,DID 搜寻设备
2. 使用`pci_enable_device()`使能对该设备的操控

作者在[GitHub - Johannes4Linux/pci_parport: A simple Linux Kernel Module for a PCI to parallel port adapter](https://github.com/Johannes4Linux/pci_parport)有简易的示例，虽然这个是 IO 空间，但逻辑几乎是一致的。

要更深入的理解这些 API ，那就需要看[Linux PCI Bus Subsystem — The Linux Kernel documentation](https://www.kernel.org/doc/html/latest/PCI/index.html)。


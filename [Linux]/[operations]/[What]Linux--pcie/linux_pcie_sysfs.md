---
title: '[What] linux PCIE: 使用 sysfs 与 PCIE 设备通信'
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

除了可以写模块来操作 PCI 设备外，还可以通过 sysfs 来操作设备。

由于是在 user space ，自然是更加的易于调试。

<!--more-->

# 进入对应逻辑设备

首先使用`lspci`来查看当前系统的 PCI 拓扑：

```shell
00:00.0 Host bridge: Intel Corporation 8th Gen Core Processor Host Bridge/DRAM Registers (rev 07)
00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 630 (Desktop)
00:14.0 USB controller: Intel Corporation 200 Series/Z370 Chipset Family USB 3.0 xHCI Controller
00:14.2 Signal processing controller: Intel Corporation 200 Series PCH Thermal Subsystem
00:16.0 Communication controller: Intel Corporation 200 Series PCH CSME HECI #1
00:17.0 SATA controller: Intel Corporation 200 Series PCH SATA controller [AHCI mode]
00:1b.0 PCI bridge: Intel Corporation 200 Series PCH PCI Express Root Port #17 (rev f0)
00:1c.0 PCI bridge: Intel Corporation 200 Series PCH PCI Express Root Port #1 (rev f0)
00:1c.1 PCI bridge: Intel Corporation 200 Series PCH PCI Express Root Port #2 (rev f0)
00:1c.4 PCI bridge: Intel Corporation 200 Series PCH PCI Express Root Port #5 (rev f0)
00:1d.0 PCI bridge: Intel Corporation 200 Series PCH PCI Express Root Port #9 (rev f0)
00:1f.0 ISA bridge: Intel Corporation Z370 Chipset LPC/eSPI Controller
00:1f.2 Memory controller: Intel Corporation 200 Series/Z370 Chipset Family Power Management Controller
00:1f.3 Audio device: Intel Corporation 200 Series PCH HD Audio
00:1f.4 SMBus: Intel Corporation 200 Series/Z370 Chipset Family SMBus Controller
00:1f.6 Ethernet controller: Intel Corporation Ethernet Connection (2) I219-V
03:00.0 SATA controller: ASMedia Technology Inc. ASM1062 Serial ATA Controller (rev 02)
04:00.0 USB controller: ASMedia Technology Inc. ASM2142 USB 3.1 Host Controller
```

根据逻辑设备的[总线号：设备号：功能号]，进入`/sys/bus/pci/devices/<bus_num/device_num/func_num>/`文件夹，在这里也可以获取到配置信息。

> 使用 hexdump config 便可以获取配置信息的值

关于各个文件的说明，参考[kernel](https://www.kernel.org/doc/html/latest/PCI/sysfs-pci.html)手册。

# 控制逻辑设备

逻辑设备目录中的 `resource*`文件便是对应该设备的 BAR，那么对这些文件进行操作便可以与 PCI 逻辑设备进行通信了。

> 可以使用 lspci -v 和 `resource*`文件的大小做对比，发现它们完全一致。

那操作逻辑就很简单了：

1. 打开想要操作逻辑设备的`resourceN`文件
2. 使用`mmap`映射物理内存到虚拟地址空间
3. 使用指针操作对应内存
4. 使用`munmap`取消映射，完成操作

简易示例如下：

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

// GPIO 配置寄存器
#define IO_CONFIG 0xf8
// GPIO 数值寄存器
#define IO_BYTE_1 0xfc

int main(int argc, char* argv[]) {
	
	// 打开 BAR 对应的文件
	int fd = open("/sys/bus/pci/devices/0000:04:08.0/resource0", O_RDWR | O_SYNC);
	
	if (fd < 0) {
		perror("Error opening BAR's resource file:");
		
		return -1;
	}
	
	// 映射物理内存到虚拟内存
	uint8_t bar0 = mmap(NULL, 256, PORT_READ | PORT_WRITE, MAP_SHARED, fd, 0);
	
	close(fd);
	
	if (bar0 == MAP_FAILED) {
		perror("Memory mapping of BAR failed:");
		
		return -1;
	}
	
	// 这里还是要读取 config 文件，以避免 BAR 的范围小于 4KB 时，需要将映射的地址加上偏移
	fd = open("/sys/bus/pci/devices/0000:04:08.0/config", O_RDONLY);
	
	if (fd < 0) {
		perror("Error opening BAR's config file:");
		
		munmap(bar0, 256);
		return -1;		
	};
	
	uint32_t config[5];
	
	int i = read(fd, config, sizeof(config);
	
	close(fd);
	
	if (i != sizeof(config)) {
		perror("Error reading PCI config header");
		
		munmap(bar0, 256);
		return -1;
	}
	
	// 这里是读取 BAR0 的值，低 4 位不用管，就看它是否是 4K 对齐
	uint32_t offset = (config[4] & 0xfffffff0) % 4096;
	
	// 如果不是 4K 对齐，则需要增加一个偏移才能正常操作
	bar0 += offset;
	
	// 配置 GPIO 为输入模式
	*(bar0 + IO_CONFIG) = 0x00;
	
	// 读取 GPIO 的值
	uint8_t val = *(bar0 + IQ_BYTE_1);
	
	// 设置 GPIO 为输出模式
	*(bar0 + IO_CONFIG) = 0x00;
	
	// 设定 GPIO 的值
	*(bar0 + IQ_BYTE_1) = 0x01;	
	
	munmap(bar0, 256);
	
	return 0;
}
```


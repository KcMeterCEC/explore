---
title: '[What]All about Bootloaders'
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

重新整理引导的构建相关知识。

<!--more-->

# bootloader 的职责

bootloader 主要就是用于依次做两件事：

1. 初始化系统的硬件环境
2. 载入内核

在系统最开始上电时，能用的资源只有：

1. 一个单核
2. 有限的内部 SRAM
3. 一个 boot ROM

# 启动顺序

对于现代 SOC 而言，其通常的启动顺序如下。

## 初始阶段：ROM code

`ROM code`便是 SOC 启动时的初始代码，它通过单核运行。

根据启动配置引脚从对应的接口载入代码到内部 SRAM 中，然后运行该代码。

> 由于 SRAM 中运行的代码是第二阶段运行的代码，所以它也叫做 SPL（secondary program loader）



### imx8mm的 ROM code

imx8mm 上电后最开始当然也是先运行 ROM code，它根据寄存器`BOOT_MODE[1:0]`、eFUSEs 状态 和 GPIO 的设定来决定启动的行为。

ROM code 还可以从启动设备的代码中获取配置信息，根据该配置来配置 DDR 等外设。

ROM code 还可以对启动代码进行验证，如果是未经授权的代码则不会被执行。

### imx8mm 的 BOOT_MODE 寄存器

BOOT_MODE 寄存器的[1:0] 两位是在上电时，根据管脚`BOOT_MODE0`和`BOOT_MODE1`来决定的：

| BOOT_MODE[1:0] | Boot Type         |
| -------------- | ----------------- |
| 00             | Boot From Fuses   |
| 01             | Serial Downloader |
| 10             | Internal Boot     |
| 11             | Reserved          |

**Boot From Fuses：**

ROM code 从 eFUSE 读取的 `BT_FUSE_SEL`来决定如何启动，GPIO 配置会被忽略：

- BT_FUSE_SEL = 0：通过`Serial Downloader`启动
- BT_FUSE_SEL = 1：通过 eFUSE 的设定的启动设备启动

在产品出厂时，一般会选择这种模式来启动：

> 由于一开始 BT_FUSE_SEL = 0，会通过`Serial Downloader`模式启动。这部分代码启动后完成多个镜像的烧写，然后配置  BT_FUSE_SEL = 1，并设置对应启动设备。
>
> 下次再次启动设备时，ROM code 就会从指定的启动设备启动。



**Serial Downloader：**

这里的`Serial Downloader`其实指的就是通过 USB 来启动设备。

如果在`USDHC2`端口上有 SD 卡/EMMC，那么 ROM code 会先尝试从它们启动。

> 可以通过配置 fuse 来关闭这种启动。



**Internal Boot：**

ROM code 会从 GPIO 指定的引脚来确定启动设备，如果启动失败会尝试`Serial Downloader`。

如果`BT_FUSE_SEL = 1`，则会从 eFUSE 设定的设备启动。

管脚`SAI1_RXD0~7,SAI1_TXD0~7`依次决定了`BOOT_CFG`寄存器的 0~15 位。

其中，`BOOT_CFG`的 12~14 位用于选择启动设备：

| BOOT_CFG[14:12] | Boot device                 |
| --------------- | --------------------------- |
| 001             | SD/eSD                      |
| 010             | MMC/eMMC                    |
| 011             | NAND                        |
| 100             | Serial NOR boot via FlexSPI |
| 110             | Serial(SPI) NOR             |

当选择对应设备时，`BOOT_CFG`的 0~11，15 用于指定设备的配置细节。比如操作频率，等待时间等。

米尔科技将`BOOT_CFG`的 0~13 位以及 `BOOT_MODE0`和`BOOT_MODE1`都引了到拨码开关 SW1,2。那么就可以灵活的配置其启动模式。

## 第二阶段：SPL

SPL 的主要目标就是初始化 SDRAM ，然后将下一阶段的 bootloader 拷贝进 SDRAM，跳转后运行。

> SDRAM 的 bootloader 属于第三阶段，所以也叫做 TPL（Tertiary Program Loader）。



imx8mm 具有 256 + 32 KB 的 SRAM，其中 256 KB 用于载入 SPL，而 32 KB 是备用区。

- 256KB SRAM 的地址范围是 0x00910000 ~ 0x0091FFFF
- 32KB SRAM 的起始地址是 0x0090000

>  所以 imx8mm 的 SPL 大小不能超过 256 KB.

## 第三阶段：TPL

第三阶段的 bootloader 就可以与用户交互，并具备了诊断硬件的功能。

最终还是为了将内核和文件系统载入进 SDRAM，然后跳转去运行内核。

一旦进入到内核，该阶段 bootloader 所占用的内存就被释放了。

> 在有了设备树后，需要传递给内核的参数基本上由设备树来设定了。
>
> bootloader 只需要告诉内核，设备树所位于的地址。

# 设备树复习

现在再回过头来看设备树，其实它也就是一个配置文件而已，只是配置的目标是硬件，并且符合[设备树标准]([DeviceTree](https://www.devicetree.org/))。

> 而面对已有的设备，需要修改设备树。那么就可以参考其对应文档的说明，文档位于`Documentation/devicetree/bindings`

## 设备树基础

设备树的起始源文件存储于：

- Linux：`arch/${ARCH}/boot/dts`
- U-boot：`arch/${ARCH}/dts`

设备树从根节点开始，向下以树的形式扩展子节点，节点的内容由`属性=值`的方式组成。

简单的示例如下：

```c
/dts-v1/;
/{
    model = "TI AM335x BeagleBone";
    compatible = "ti,am33xx";
    #address-cells = <1>;
    #size-cells = <1>;
    cpus {
        #address-cells = <1>;
        #size-cells = <0>;
        cpu@0 {
            compatible = "arm,cortex-a8";
        	// 指定节点的类型
            device_type = "cpu";
            reg = <0>;
        };
    };
    memory@0x80000000 {
        // 指定节点的类型
        device_type = "memory";
        // 起始地址和大小
        reg = <0x80000000 0x20000000>; /* 512 MB */
    };
};        
```

## reg 属性

reg 属性中值的规则由其父节点的`#address-cells`和`#size-cells`来确定：

- `#address-cells`：代表由多少个 cells 来表示一个完整的地址
- `#size-cells`：代表由多少个 cells 来表示大小

比如上面的 cpu节点，由于只需要表示地址而无需表示大小，所以：

> #address-cells = <1>;
>
> #size-cells = <0>;

而对于 32 位内存空间，就需要一个 cell 表示地址，一个 cell 表示大小，所以：

> #address-cells = <1>;
> #size-cells = <1>;
>
> // 起始地址是 0x80000000 ，大小是 0x20000000，也就是 512 MB
>
> reg = <0x80000000 0x20000000>; /* 512 MB */

而如果是 64 位地址空间，那么就必然需要两个 cell 表示地址，两个 cell 表示大小：

```c
/{
    #address-cells = <2>;
    #size-cells = <2>;
    memory@80000000 {
        device_type = "memory";
        // 前两个 cells 表示起始地址，后两个 cells 表示大小
        reg = <0x00000000 0x80000000 0 0x80000000>;
    };
};
```

## label 和中断

通常一个节点的名称是包含其字符串和地址，很多时候我们需要引用这个节点或对齐内容进行修改或增加，那么为其添加一个 label ，以便于以后引用方便。这个 label 就被称为 `phandles`：

```c
/dts-v1/;
{    
    intc: interrupt-controller@48200000 {
        compatible = "ti,am33xx-intc";
        interrupt-controller;
        #interrupt-cells = <1>;
        reg = <0x48200000 0x1000>;
    };
    lcdc: lcdc@4830e000 {
        compatible = "ti,am33xx-tilcdc";
        reg = <0x4830e000 0x1000>;
        interrupt-parent = <&intc>;
        interrupts = <36>;
        ti,hwmods = "lcdc";
        status = "disabled";
    };
};
```

上面为中断控制器设定了`intc`为其`phandle`，所以在 lcdc 节点中就可以通过`&intc`的方式来引用。

中断控制器中的`#interrupt-cells = <1>;`代表使用该中断控制器的节点需要在其`interrupts`属性中填入一个值即可。

## 设备树包含

设备树的公有部分的文件后缀是`.dtsi`，以被其他设备树文件以`/include/`的方式包含：

> /include/ "vexpress-v2m.dtsi"

处理上面这种方式，设备树还可以包含 c 头文件，以获取其文件内部的宏定义：

```c
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/pinctrl/am33xx.h>
#include <dt-bindings/clock/am3.h>
```

## 编译设备树

使用设备树编译器`dtc`，将设备树源文件`dts`，编译为设备树二进制文件`dtb`：

> $ dtc simpledts-1.dts -o simpledts-1.dtb

# U-Boot

为了使这个步骤尽量简单，我们不使用[原本的U-boot]([WebHome < U-Boot < DENX](https://www.denx.de/wiki/U-Boot))，而是使用[米尔科技的 U-boot 分支](https://github.com/MYiR-Dev/myir-imx-uboot)。

## imx8mm 在 ROM code 之后的启动流程

前面说过，在 ROM code 之后便是根据配置选择启动设备，从中读出代码，代码依次分为这么几部分：

1. [i.MX ARM Trusted firmware](https://source.codeaurora.org/external/imx/imx-atf/)：用于配置是否使用安全启动

2. imx-uboot：uboot 就分为了 SPL 和 TPL

   > U-boot 的 falcon 模式可以直接从 SPL 装载内核然后运行，节约开机时间

3. controller firmware：用于 uboot 的 SPL 调用，来初始化 ddr

## 编译 imx-atf

首先需要将交叉编译工具链，加入当前 SHELL 的环境变量中：

```shell
export PATH=/home/cec/x-tools/aarch64-unknown-linux-gnu/bin:${PATH}
```

由于 imx-atf 使用的是 Makefile 编译，并且查看其源文件也可以看到它会使用变量`CROSS_COMPILE`，所以需要设定变量：
```shell
export CROSS_COMPILE=aarch64-unknown-linux-gnu-
# 按照惯例，先 clean 一次
make clean
```

然后可以使用`make help`查看编译说明：

> usage: make PLAT=<a70x0|a70x0_amc|a80x0|a80x0_mcbin|fvp|hikey|hikey960|imx8dx|imx8dxl|imx8mm|imx8mn|imx8mp|imx8mq|imx8qm|imx8qx|juno|k3|ls1043|mt6795|mt8173|poplar|qemu|rk3328|rk3368|rk3399|rpi3|sgi575|sgm775|stm32mp1|sun50i_a64|sun50i_h6|synquacer|tegra|uniphier|warp7|zynqmp> [OPTIONS] [TARGET]
>
> PLAT is used to specify which platform you wish to build.
> If no platform is specified, PLAT defaults to: fvp

可以看到需要为其指定 SOC，那么我们自然是指定 `imx8mm`：

```shell
make PLAT=imx8mm
```

最后生成文件`build/imx8mm/release/bl31.bin`。

## 编译 U-boot

编译 U-boot 的步骤和编译内核都差不多：

1. 使用一个最接近当前硬件的配置
2. 使用`menuconfig`进行进一步细节配置
3. 使用`make`编译

```shell
# 按照惯例先 clean 一次
make distclean
# 指定配置文件
make myd_imx8mm_defconfig
# 开始编译
make -j8
```

然后会生成以下几个文件：

- `u-boot`：U-boot 的 ELF 目标文件，里面包含了调试信息
- `u-boot.map`：符号表
- `u-boot.bin`：去掉调试信息的二进制文件
- `u-boot.img`：在 `u-boot.bin`之上包含 U-boot 头信息
- `u-boot.srec`：U-boot 的 SRC 格式，可以通过串口传输
- `spl/u-boot-spl.bin`：SPL 阶段运行的代码

## 启动 U-boot

查看脚本文件`make-uboot-emmc.sh`内容：

```shell

cp myir-imx-uboot/tools/mkimage                      ./imx-mkimage/iMX8M/mkimage_uboot
cp myir-imx-uboot/arch/arm/dts/myb-imx8mm-base.dtb   ./imx-mkimage/iMX8M/fsl-imx8mm-ddr4-evk.dtb
cp myir-imx-uboot/spl/u-boot-spl.bin                 ./imx-mkimage/iMX8M/
cp myir-imx-uboot/u-boot-nodtb.bin                   ./imx-mkimage/iMX8M/

# firmware-imx-8.7 
cp firmware-imx-8.7/firmware/ddr/synopsys/ddr4_dmem_1d.bin                     ./imx-mkimage/iMX8M/
cp firmware-imx-8.7/firmware/ddr/synopsys/ddr4_dmem_2d.bin                     ./imx-mkimage/iMX8M/
cp firmware-imx-8.7/firmware/ddr/synopsys/ddr4_imem_1d.bin                     ./imx-mkimage/iMX8M/
cp firmware-imx-8.7/firmware/ddr/synopsys/ddr4_imem_2d.bin                     ./imx-mkimage/iMX8M/

# imx8mm-atf
cp imx-atf/build/imx8mm/release/bl31.bin                                    ./imx-mkimage/iMX8M/

cd imx-mkimage
make SOC=iMX8MM clean
make SOC=iMX8MM flash_ddr4_evk
```

可以看到，其主要是将之前编译的文件拷贝到`imx-mkimage`文件夹中，然后运行`make`开始制作。

[imx-mkimage](https://source.codeaurora.org/external/imx/imx-mkimage)是 IMX 做的打包工具，最终生成文件`flash.bin`。

那这个`flash.bin`应该放在哪里，在`imx_linux_users_guide`中有说明：

>  Execute the following command to copy the U-Boot image to the SD/MMC card:
>
> > $ sudo dd if=<U-Boot image> of=/dev/sdx bs=1k seek=<offset> conv=fsync
>
> Where offset is:
>
> - 1 - for i.MX 6 or i.MX 7
> -  33 - for i.MX 8QuadMax A0, i.MX 8QuadXPlus A0, and i.MX 8M Quad
> -  32 - for i.MX 8QuadXPlus B0, i.MX 8QuadMax B0, i.MX 8DualX, i.MX 8DXL,i.MX 8M Nano, i.MX 8M Mini, and i.MX 8M Plus
>
> The first 16 KB of the SD/MMC card, which includes the partition table, is reserved.

由于我们使用的是 IMX8MM，按照上面说明`seek`应该是`32`。

>  但实际测试发现需要设置`33`才行，米尔的手册上面也是 33……

最后就是熟悉的启动输出了：

```shell
U-Boot SPL 2019.04-g65e4ca0a-dirty (Sep 03 2021 - 17:02:00 +0800)
power_bd71837_init
DDRINFO: start DRAM init
DDRINFO:ddrphy calibration done
DDRINFO: ddrmix config done
Normal Boot
Trying to boot from MMC1

U-Boot 2019.04-g65e4ca0a-dirty (Sep 03 2021 - 17:02:00 +0800)

CPU:   Freescale i.MX8MMQ rev1.0 1800 MHz (running at 1200 MHz)
CPU:   Commercial temperature grade (0C to 95C)CPU Temperature (43000C) has beyond alert (85000C), close to critical (95000C) at 43C
Reset cause: POR
Model: MYD i.MX8MM  board
DRAM:  2 GiB
MMC:   FSL_SDHC: 1, FSL_SDHC: 2
Loading Environment from MMC... Run CMD11 1.8V switch
*** Warning - bad CRC, using default environment

In:    serial
Out:   serial
Err:   serial

 BuildInfo:
  - ATF f1a195b
  - U-Boot 2019.04-g65e4ca0a-dirty

Run CMD11 1.8V switch
switch to partitions #0, OK
mmc1 is current device
flash target is MMC:1
Run CMD11 1.8V switch
Net:   
Error: ethernet@30be0000 address not set.

eth-1: ethernet@30be0000
Fastboot: Normal
Normal Boot
Hit any key to stop autoboot:  0 
Run CMD11 1.8V switch
switch to partitions #0, OK
mmc1 is current device
Run CMD11 1.8V switch
** Unrecognized filesystem type **

Booting from net ...

Error: ethernet@30be0000 address not set.

WARN: Cannot load the DT
u-boot=> 
```

## 复习  U-boot 的基础知识

### 环境变量

U-boot 使用`name=value`的形式来表示环境变量，一些环境变量是最开始在头文件中已经配置了默认值。在启动后读入内存，便可以被修改了。

> 对环境变量的操作都在`env`命令中

## 启动内核

使用`bootm`启动内核，其语法如下：

```shell
bootm <address of kernel> [address of ramdisk] [address of 
dtb]
```

其中`address of kernel`是必须的，后面两项不是必须的。

如果没有`address of ramdisk`但是有`address of dtb`，那么使用短横线代替即可:

```shell
=> bootm 82000000 – 83000000
```

除了在调试阶段需要手动输入这些命令，实际使用阶段是经过脚本来完成，比如 imx8mm 默认环境变量如下：

```shell
mmcdev=1
mmcpart=1
loadaddr=0x40480000
script=boot.scr
bootscript=echo Running bootscript from mmc ...; source
image=Image
fdt_addr=0x43000000
fdt_file=myb-imx8mm-lcd-hontron-7.dtb
boot_fdt=try
console=ttymxc1,115200 earlycon=ec_imx6q,0x30890000,115200
mmcroot=/dev/mmcblk1p2 rootwait rw

mmcargs=setenv bootargs ${jh_clk} console=${console} root=${mmcroot}
loadfdt=fatload mmc ${mmcdev}:${mmcpart} ${fdt_addr} ${fdt_file}

loadbootscript=fatload mmc ${mmcdev}:${mmcpart} ${loadaddr} ${script};
loadimage=fatload mmc ${mmcdev}:${mmcpart} ${loadaddr} ${image}

mmcboot=\
echo Booting from mmc ...;\
run mmcargs;\
if test ${boot_fdt} = yes || test ${boot_fdt} = try;\
then if run loadfdt;\
     then booti ${loadaddr} - ${fdt_addr};\
     else echo WARN: Cannot load the DT;\
     fi;\
else echo wait for boot;\
fi;\

bootcmd=\
mmc dev ${mmcdev};\
if mmc rescan;\ # 扫描 mmc，发现有 mmc
then if run loadbootscript;\ 
	 then run bootscript;\ # 如果从 mmc 读取文件成功，则运行启动脚本
	 else if run loadimage;\ # 或者从 mmc 读取指定名称文件
		  then run mmcboot;\ # 读取成功则运行启动脚本
		  else run netboot;\ # 然后会尝试通过网络启动
		  fi;\ 
	 fi;\ 
else booti ${loadaddr} - ${fdt_addr};\ 
fi\
```

`bootcmd`将会是 U-boot 启动以后自动执行的命令。

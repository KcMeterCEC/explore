[What] Zynq --> 调试总结
==========================

## 配置 PS 

需要牢记于心的是： **zynq中PL与PS是可以单独配置的**，这句话的意义在于可以仅仅下载 PL 或者 PS 代码。

也就是说，当仅仅需要配置 PS 时，可以在 vivado 下通过图形界面配置 PS 模块。随后在同步和综合后便可以直接输出硬件描述文件，而**不需要编译 bit 文件**，这样会**大大节约调试时间**（当然，在输出硬件文件时，也不用选择导出 bit 文件选项）。

在生成的文件导入 SDK 后，可以查看 ps7\_init.html 文件来了解整个 PS 的配置概览和寄存器的具体配置值。

对应的初始化时钟、DDR、MIO代码具体实现是在 ps7\_init.c 和 ps7\_init.h 文件中来实现寄存器配置。（当然也可以通过直接修改 ps7\_init.c 的寄存器列表，但是没有 vivado 图形界面配置直观）。

### 配置 DDR

DDR 是跑 ssbl 和系统的基础，但 DDR 由于布线参数等等原因不是那么好配置。

比较好的解决步骤是：

1.  在 vivado 下将 DDR 时钟降低，这样会降低由于布线造成的误差。
2.  通过 JATG 下载 fsbl 配置 DDR ，然后再通过 JATG 下载例程 "DRAM test" 代码完成对整个 DDR 的读写测试（需要关闭 cache，命令“Z”）。
3.  参考 "DRAM test" 测试结果（眼图测试命令“R/I/D/A”）修改 DDR 配置参数，直到配置正常。
4.  提升 DDR 时钟到理论时钟，对参数再次进行微调。
5.  在修改参数的过程中，要**注意截图保存**，因为参数会反复调。

相关参考 : [ddr基础知识](https://github.com/KcMeterCEC/explore/blob/master/%5BWhat%5D%E5%9F%BA%E7%A1%80%E7%A1%AC%E4%BB%B6--DDR%E7%9F%A5%E8%AF%86/document.md)

#### 对于 LPDDR

vivado 对 lpddr 的配置参数支持并不友好，如果在前面的步骤无法搞定，那么需要**手动修改文件 "ps7\_init.c ps7\_init.tcl"**。

**得到内核版本：**

1. 使用 JATG 连接目标板
2. 在 SDK 下调用控制台 "Xilinx Tools --> XSDB Console"
3. 在控制台下连接目标板 "connect"
4. 选中目标 "targets 1"
5. 读取寄存器的值 "mrd 0xf8007080"
6. 根据返回数据的第 31:28 位得出版本号，比如：30800100 代表版本3.0

**修改寄存器并验证：**

1. 修改 **对应版本** "ps7\_init.c ps7\_init.tcl" （查看 DDR MRX 配置，对应搜寻 zynq MRX 寄存器配置）

**注意：** SDK 最坑爹的是它会在下载完一次代码后，自动还原上面两个文件的值！！！！！所以每次下载前需要重新修改

2. 重新编译 "Project --> Clean"
3. 通过“得到内核版本”中一样的步骤，读取寄存器

## 裸机测试

打开 c99 标准： project-> properties -> c/c++Build -> settings -> ARM v7 gcc compiler -> Miscekkaneous 
在 Other flags 中添加 -std=c99

优化代码大小： 在添加c99标准处，继续添加 "-ffunction-sections -fdata-sections" ，在 xxxx ->settings -> ARM v7 gcc linker -> inferred options -> software platform -> software platform inferred flags 处，添加 "--gc-sections"

**说明：**
> 编译选项 -ffunction-sections -fdata-sections 使得编译器为每个 functions 和 data item 分配独立的 section。
> 链接选项 --gc-sections 会使链接器删除没有被使用的section


逻辑测试如果硬件稍多需要使用 FreeRTOS，需要注意的是：

1. 包含头文件 "FreeRTOS.h" 的位置要在其他组件**之前**，并且在 debug 和 release 下都要添加此选项
2. zynq 默认上电 IO 口是**高电平**！
3. 如果裸机代码大于 192KB，那么需要**修改链接脚本的映射**，并且在**执行代码前**调用 [OCM重映射函数](https://github.com/KcMeterCEC/explore/tree/master/%5BWhat%5DZynq--%E6%9E%84%E6%9E%B6%E8%AF%B4%E6%98%8E)。
4. 如果要修改 bsp 的部分配置，则**修改 libsrc 下的文件，不能修改 include文件夹下的文件，因为它会被覆盖！**
5. 一般硬件 IIC 只需要提供 **7位地址即可**，不用包含最终的读写位，How foolish i am!
---
title: 如何编写一个简单的内核模块？
tags: 
- linux
categories:
- linux
- driver
- module
date: 2023/3/24
updated: 2023/3/25
layout: true
comments: true
---

这里仅仅是一个简单的说明，比较全面的说明可以查看开源书籍 [lkmpg](https://sysprog21.github.io/lkmpg/)。

<!--more-->

# 概述

Linux内核使用模块(Module)的方法使得需要的功能可以动态的方式被加载到内核中，它具有如下优点：

- 模块本身不被编译入内核镜像，可以灵活的控制内核大小
- 模块被加载后，和内核其他部分一样，也是通过函数的方式调用(宏内核)
  + 但如果模块编写有误，也有可能导致内核奔溃

# 基本操作

## 加载及卸载

```shell
  #加载模块
  sudo insmod name.ko
  #以依赖的方式加载模块，这种方式默认模块位于 /lib/modules/<kernel> 目录下
  sudo modprobe name.ko 

  #卸载模块
  sudo rmmod name
  #以依赖的方式卸载模块
  sudo modprobe -r name.ko 
```

需要注意的是：当模块在卸载时，如果模块申请的资源没有被完全释放，那么下次再加载此模块时将有可能会出现各种错误。

### Required key not available

在Linux内核4.4.0-20 之后(ubuntu16.04)，默认打开了安全启动模式，也就是禁止第三方的模块加载。

所以需要关闭此安全启动模式：

```shell
  #################
  # 方法1
  #################
  #简单粗暴的进入bios，然后关闭安全启动模式
  #################
  # 方法2
  #################
  sudo apt install mokutil
  #执行完此步骤后会输入一个8~16位密码
  sudo mokutil --disable-validation
  #重启
  #根据提示关闭安装启动模式(启动时可能不是输入密码，而是要你按照屏幕提示输入字符，和验证码一样)
  #再次重启
```

## 模块查看

- 使用 `lsmod` 命令可以获得系统中已加载的所有模块以及模块间的依赖关系。
  + 此命令实际上是读取 `/proc/modules` 文件中的内容显示的
- 内核被加载后，也存在于 `/sys/module/<module_name>` 文件夹下。
  + `refcnt` 代表模块被引用的次数
  + `sections` 表示了模块的段信息，在进行GDB调试时，需要获取这些信息
  + `parameters` 中包含了模块中定义的参数变量，可以`cat`出其值
- 使用 `modinfo <module_name>.ko` 可以查看模块信息

# 实例模版

## 代码

```c
  /*!
   * this is a example of kernel module
   */

  /*!
   * @brief 通过编译会在当前目录生成example.ko
   * ### 加载模块
   * 1. 加载模块时使用命令   insmod ./example.ko(加载模块位于 /sys/module/ 目录 ，并且会创建一个和模块名一样的目录，目录下具有模块对应的信息)
   * 2. 也可以使用"modprobe"命令加载，此命令会同时加载其该模块所依赖的模块, 模块之间的依赖关系位于 /lib/modules/<kernel-version>/modules.dep 文件中
   * 3. 在本模块代码中,可以使用"request_module(module_name)"动态加载其他模块
   * 4. 查看内核输出的文件: /var/log/kern.log
   * ### 卸载模块
   * 1. 卸载模块时使用命令   rmmod  example
   * 2. 相应的使用 "modprobe -r filename"命令卸载，会同时卸载其依赖的模块
   * ### 模块信息
   * 1. 查看已经加载的模块使用命令 lsmod(此命令实际上是分析文件 /proc/modules )
   * 2. 查看单个模块的信息使用 "modinfo <模块名>"命令
   */
  #include <linux/init.h>
  #include <linux/module.h>

  /*!
   * @brief 使用"module_param(参数名, 参数类型, 参数访问权限)"定义一个外部可访问的参数
   * 在模块加载的时候可以为参数设定值" insmod ./example.ko module_name='world'"(*参数赋值前后不能有空格*，多个参数使用空格分隔)
   * 或者在bootloader中在"bootargs"设置"模块名.参数名 = 值"
   * 也可以在设备树中设定
   *
   * 参数类型: byte, short, ushort, int, uint, long, ulong, charp, bool, invbool
   *
   * 也可以定义数组"module_param_array(数组名, 数组类型, 长度, 访问权限)"
   *
   * 模块参数可以在"/sys/module/example/parameters"下查看
   */
  static char *module_name = "hello";
  module_param(module_name, charp, S_IRUGO);

  static int num = 1000;
  module_param(num, int, S_IRUGO);

  //! 使用"__initdata"标记的变量，内核在初始化完模块后，便释放该变量所占用的内存
  //! 同理，只有卸载阶段才使用的变量，可以使用标记"__exitdata"
  static int hello_data __initdata = 1;

  /*!
   * @brief 使用EXPORT_SYMBOL_GPL(符号名) 导出符号被外部模块使用(符号表位于/proc/kallsyms)
   *
   *
   */
  int add_integar(int a, int b)
  {
      return a + b;
  }
  EXPORT_SYMBOL_GPL(add_integar);
  int sub_integar(int a, int b)
  {
      return a - b;
  }
  EXPORT_SYMBOL_GPL(sub_integar);
  /*!
   * 如果直接编译进内核，此函数放在区段".init.text"区段
   * 其地址放在 ".initcall.init" 用于初始化调用
   *
   * @note: 在初始化后这两个段的内存将会被释放
   */
  static int __init hello_init(void)
  {
      printk(KERN_INFO "\n********************\n");
      printk(KERN_INFO "[Hello world] module initialized! val = <%d>\n", hello_data);
      printk(KERN_INFO "module name = %s\n", module_name);
      printk(KERN_INFO "module num = %d\n", num);
      printk(KERN_INFO "********************\n");

      //! 初始化成功返回0,失败返回负值(位于<linux/errno.h>),这些值可以被perror()使用
      return 0;
  }
  module_init(hello_init);

  /*!
   * @brief 当此模块被编译被内建模块时，此函数将被省略
   * 注意：使用此函数，需要清理掉模块所申请的内存
   */
  static void __exit hello_exit(void)
  {
      printk(KERN_INFO "\n********************\n");
      printk(KERN_INFO "[Hello world] module exit!\n");
      printk(KERN_INFO "********************\n");
  }
  module_exit(hello_exit);

  MODULE_AUTHOR("kcmetercec <kcmeter.cec@gmail.com>");
  //! 如果没有许可证声明，加载模块时会收到内核被污染警告(Kernel Tainted)
  MODULE_LICENSE("GPL v2");// GPL, GPL v2, GPL and additional rights, Dual BSD/GPL, Dual MPL/GPL
  MODULE_DESCRIPTION("A simple example module");
  MODULE_ALIAS("a simplest module");
  MODULE_VERSION("ver1.0");
```

## 编译(Makefile)

```Makefile
KVERS = $(shell uname -r)

obj-m += example.o
#如果模块包含多个文件 (file1.c,file2.c) 则使用
#obj-m := modulename.o
#modulename-objs := file1.o file2.o

#使用可以得到包含调试信息的模块
#EXTRA_CFLAGS=-g -O0
build: kernel_modules

kernel_modules:
# -C 后指定了内核的源码目录
# 对于交叉编译，那么就需要首先修改 CC 变量指定编译器，然后再指定源码目录
    make -C /lib/modules/$(KVERS)/build M=$(CURDIR) modules

clean:
    make -C /lib/modules/$(KVERS)/build M=$(CURDIR) clean
```

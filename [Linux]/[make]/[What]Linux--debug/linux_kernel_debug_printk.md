---
title: 使用 printk 调试内核
tags: 
 - linux
categories:
 - linux
 - kernel
 - debug
date: 2023/7/31
updated: 2023/8/8
layout: true
comments: true
---

- kernel version : v6.1.x (lts)

总结在 Linux 内核下使用串口打印调试信息。

<!--more-->

# printk 基本使用

`printk()` 函数用于打印内核的调试信息，同时会将这些信息输出到一个缓冲区中。

可以通过 `dmesg` 命令查看内核打印缓冲区, 当使用 `dmesg -c` 则不仅会显示 `__log_buf` 还会清除该缓冲区的内容。

也可以通过 `cat /proc/kmsg` 命令来一直显示内核信息。

## 信息缓冲区大小设置

信息缓冲区的填写是一个环形队列的形式，所以如果消息太多以前的消息就会被覆盖掉，有的时候需要设置更大的缓冲区显示更多的信息。

信息缓冲区代码位于 `kernel/printk/printk.c` 中：

``` c
#define __LOG_BUF_LEN (1 << CONFIG_LOG_BUF_SHIFT)
// 限制最大的日志大小是 2G
#define LOG_BUF_LEN_MAX (u32)(1 << 31)
static char __log_buf[__LOG_BUF_LEN] __aligned(LOG_ALIGN);
static char *log_buf = __log_buf;
static u32 log_buf_len = __LOG_BUF_LEN;
```

可以看出缓存的大小是 `2 ^ CONFIG_LOG_BUF_SHIFT` 个字节， `CONFIG_LOG_BUF_SHIFT` 的设置是由 `init/Kconfig` 来完成的，在Menuconfig中的路径为：

``` shell
General setup -> Kernel log buffer size(16 => 64KB, 17 => 128kB)
```

但如果在启动参数中使用`log_buf_len`，则以启动参数中的值为准。

如果存在多核对称处理器（SMP），那么还会根据`CONFIG_LOG_CPU_MAX_BUF_SHIFT` 来配置日志缓存的大小（参考 `log_buf_add_cpu()` 函数）。

> 由于上面的缓存是 static 形式的，所以如果 SMP 新增日志缓存生效，则意味着这段内存就不会被使用（浪费了）。


## 消息级别

printk()定义了8个消息级别(0~7)，**数值越低，级别越高** 。

在实际使用中，会有默认的消息级别打印， **只有低于消息级别的消息才会打印** 。

``` C
// 位于 /include/linux/kern_levels.h
#define KERN_SOH   "\001"  /*ASCII Start of header*/
#define KERN_SOH_ASCII '\001'

#define KERN_EMERG   KERN_SOH "0" //紧急事件,一般是系统崩溃之前提示的消息
#define KERN_ALERT   KERN_SOH "1" //必须立即采取行动
#define KERN_CRIT    KERN_SOH "2" //临界状态,通常涉及严重的硬件或软件操作失败
#define KERN_ERR     KERN_SOH "3" //用于报告错误状态,设备驱动代码经常使用它报告硬件问题
#define KERN_WARNING KERN_SOH "4" //对可能出现问题的情况进行警告,不会对系统造成严重的问题
#define KERN_NOTICE  KERN_SOH "5" //有必要进行提示的正常情形,许多与安全攸关的情况用这个级别
#define KERN_INFO    KERN_SOH "6" //提示性的信息,驱动程序使用它打印出一般信息
#define KERN_DEBUG   KERN_SOH "7" //调试信息

#define KERN_DEFAULT  "" //默认级别
```

## 修改消息级别的方法

### 在menuconfig中修改

对应的路径为：

``` shell
Kernel hacking -> printk and dmesg options -> Default message log level(1-7)
```

### 在系统中修改 prink 文件:
通过 `/proc/sys/kernel/printk` 文件可以调节 printk() 的输出等级,该文件的4个数值表示为：

1. 控制台的日志级别：当前的打印级别，优先级高于该值（值越小，优先级越高）的消息将被打印至控制台
2. 默认的消息日志级别：将用该优先级来打印没有优先级前缀的消息,也就是直接写 `printk("xxx")` 而不带打印级别的情况下，会使用该打印级别
3. 最低的控制台日志级别：控制台日志级别可被设置的最小值（一般是1）
4. 默认的控制台日志级别：控制台日志级别的默认值

使用如下命令打印所有信息:

```
shell
#echo 8 > /proc/sys/kernel/printk
```

**注意**:

此文件并不控制内核消息进入 `__log_buf` 的门槛，因此无论消息级别是多少,都会进入 `__log_buf` 中，但是最终只有高于当前打印级别的内核消息才会从控制台打印。

### 修改启动参数

通过在 `bootargs` 中设置 `ignore_loglevel` 来忽略打印级别。
在系统启动后，也可以通过写 `/sys/module/printk/parameters/ignore_loglevel` 文件来动态设置是否忽略打印级别。

## 带时间戳的输出

在 `menuconfig` 中使能 `printk` 带时间戳输出，有助于判断代码执行时间。

路径:

```shell
Kernel hacking -> printk and dmesg options -> Show timing information on printks
```

# 调试信息的输出

## pr_xxx(): 位于 `/include/linux/printk.h`

通常使用封装了 `printk()` 的宏，来显示调试信息。比如 `pr_debug()`，`pr_info()`。
使用 `pr_xxx()` API的好处是可以在文件最开头通过 `pr_fmt()` 定义一个打印格式。

``` C
//打印消息头带有 "[driver] watchdog:"前缀
#define pr_fmt(fmt) "[driver] watchdog:" fmt

// 对于模块的话，可以使用模块名称的宏
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

// 如果要打印函数名的话，还可以这样：
#define pr_fmt(fmt) "%s:%s: " fmt, KBUILD_MODNAME, __func__
```

定义打印格式后，其实就是在 `printk` 前加入该宏：

```c
/**
 * pr_info - Print an info-level message
 * @fmt: format string
 * @...: arguments for the format string
 *
 * This macro expands to a printk with KERN_INFO loglevel. It uses pr_fmt() to
 * generate the format string.
 */
#define pr_info(fmt, ...) \
	printk(KERN_INFO pr_fmt(fmt), ##__VA_ARGS__)
```

## dev_xxx(): 位于 `/include/linux/dev_printk.h`

使用`dev_xxx()` 打印的时候，设备名称会被自动打印到打印消息的前面。

## 使用规则

- 能使用 `dev_xxx()` 的时候就尽量使用它，因为它可以打印出设备的名称。
  + 这在一个驱动对应多个设备，而某个设备出问题的情况下比较好排查。
- 在不能使用 `dev_xxx()` 的场合才使用 `pr_xxx()` 
  + 为了明确信息是由 `pr_xxx()` 输出的信息，建议在信息头中加上标识符。
    + 驱动中调试加上 `[driver]`
    + 内存中调试加上 `[mem]`

## 默认调试信息输出

内核默认有很多使用 `pr_debug()`/`dev_dbg()` 的输出,但需要满足如下条件:

1. 开启了 DEBUG 宏
2. kernel printk 的默认日志级别大于7

### 开启DEBUG

- 方法1：在要输出信息的文件的**最开头**加上宏定义 `#define DEBUG`
- 方法2：在编译内核的时候传入参数 `KCFLAGS=-DDEBUG` 打开全局输出（不推荐，相关的输出实在是太多了）

# 早期信息的打印

## 使能

为了能够在控制台驱动初始化之前就打印信息,需要在`menuconfig`中设置: 

- 选择 `Kernel low-level debug`

```c
 Kernel hacking > arm Debugging -> Kernel low-level debugging functions(read help!)
```

- 选择 Early printk

```c
Kernel hacking -> Early printk
```

- 在 `bootargs` 中添加 `earlyprintk` 字符串

## 使用
``` c
#include <asm/early_printk.h>

early_printk("Hello world\n");
```

# 与用户空间顺序输出
在精简的嵌入式系统中，当用户空间在使用 `printf` 的同时内核在使用 `printk` 时会造成两个输出相互干扰，与造成竞态的效果一样。

内核为用户空间提供了设备文件 `/dev/ttyprintk` 以让用户空间的log可以在内核中打印，打印的Log前会加上 `[U]` 标识，
这样便不会造成二者干扰了。

在嵌入式内核中，可能没有 `/dev/ttyprintk` 设备，可以使用 `/dev/kmsg` 来达到目的。

通过 `/dev/kmsg` 没有前缀输出，但是我们可以自己加入前缀以达到同样的效果。

如下用户空间代码:

``` c
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>


int fd = 0;

void KernelWrite(const char *fmt, ...) {
	va_list ap;
	char buf[256];
	int n;

	va_start(ap, fmt);
	n = vsnprintf(buf, 256, fmt, ap);
	va_end(ap);
	write(fd, buf, n);
}

int main(int argc, char *argv[]) {
    fd = open("/dev/ttyprintk", O_WRONLY);
	if (fd < 0) {
		printf("open file failed!\n");
		return 1;
	}

	KernelWrite("The ttyprintk index is %d\n", fd);

	close(fd);
	return 0;
}
```

通过 `dmesg` 查看，输出为：

```shell
[U] The ttyprintk index is 3
```

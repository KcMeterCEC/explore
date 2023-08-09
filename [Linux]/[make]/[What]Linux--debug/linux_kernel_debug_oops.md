---
title: Linux内核调试之Oops
tags: 
 - linux
categories:
 - linux
 - kernel
 - debug
date: 2023/8/8
updated: 2023/8/9
layout: true
comments: true
---

- kernel version : v6.1.x (lts)

总结在Linux内核下使用 Oops 输出调试内核。

<!--more-->

# 输出分析

当内核出现异常时，内核会抛出 Oops 信息，这些信息会被输出到控制台。

在Oops 的输出信息中, 需要注意的一些信息是:

- Oops 最开始的输出信息中已经大致说明了异常的原因
- `PC is at [function_name] + [address]` ：此行指出了出错的函数，以及执行语句在函数中的偏移地址。 然后可以通过命令得出反汇编代码, 找出C代码位置

```shell
arm-linux-gnueabihf-objdump -d -S file.o
```

- 寄存器列表：当出错的函数有参数时, 可以通过寄存器列表来查看输入的参数是否正确(如果参数过多, 还要查看栈信息)
- 函数调用顺序：通过查看栈信息, 可以知道此函数是如何被以层层调用进来的

# Oops 与 Panic

Panic 属于 Oops 的一种，内核发现异常会抛出Oops，但错误不严重的情况下内核还会继续运行。如果严重则会抛出 Panic，此时内核便会停止运行。

但为了便于调试，一般需要做如下操作：

```shell
echo 1 > /proc/sys/kernel/panic_on_oops
```

这是为了内核无论是出现 Oops 还是 Panic 都要停止内核运行，以便正确并及时的捕捉错误的位置。

# 显示使用 BUG_ON() 和 WARN_ON()

BUG_ON() 和 WARN_ON() 是内核提供的警告宏。

首先使能 `CONFIG_BUG` 宏:

```shell
  General setup -> Configure standard kernel features(expert users) -> BUG() support
```

其中BUG_ON()成立时主动抛出 Oops 的宏，WARN_ON() 成立时抛出栈调用。我们在必要的位置可以加上者两个宏,以达到：

- 判断出了错误
- 查看错误时的参数调用
- 查看函数调用栈

``` c
// path of file: /include/asm-generic/bug.h
/*
 * Don't use BUG() or BUG_ON() unless there's really no way out; one
 * example might be detecting data structure corruption in the middle
 * of an operation that can't be backed out of.  If the (sub)system
 * can somehow continue operating, perhaps with reduced functionality,
 * it's probably not BUG-worthy.
 *
 * If you're tempted to BUG(), think again:  is completely giving up
 * really the *only* solution?  There are usually better options, where
 * users don't need to reboot ASAP and can mostly shut down cleanly.
 */
#ifndef HAVE_ARCH_BUG
#define BUG() do { \
	printk("BUG: failure at %s:%d/%s()!\n", __FILE__, __LINE__, __func__); \
	barrier_before_unreachable(); \
	panic("BUG!"); \
} while (0)
#endif

#ifndef HAVE_ARCH_BUG_ON
// 当 condition 为真时，才会触发 BUG()
#define BUG_ON(condition) do { if (unlikely(condition)) BUG(); } while (0)
#endif

#ifndef WARN_ON
#define WARN_ON(condition) ({						\
	int __ret_warn_on = !!(condition);				\
	if (unlikely(__ret_warn_on))					\
		__WARN();						\
	unlikely(__ret_warn_on);					\
})
#endif
```

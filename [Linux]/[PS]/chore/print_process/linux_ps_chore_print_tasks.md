---
title: 输出 Linux 中所有的 task
tags: 
- linux
categories:
- linux
- ps
- chore
date: 2023/4/11
updated: 2023/4/12
layout: true
comments: true
---

- kernel version : v6.1.x (lts)

进程或线程对于 kernel 来说，都是 `task_struct` 结构体来描述，所以这里指的是输出所有的 task。

<!--more-->

# task_struct 的双向链表

还是继续来看，`task_struct`的结构体定义：

```c
struct task_struct {
#ifdef CONFIG_THREAD_INFO_IN_TASK
	/*
	 * For reasons of header soup (see current_thread_info()), this
	 * must be the first element of task_struct.
	 */
	struct thread_info		thread_info;
	//...
	unsigned int			rt_priority;
	//...

	struct sched_info		sched_info;
	//...
	struct list_head		tasks;
	//...
	/*
	 * executable name, excluding path.
	 *
	 * - normally initialized setup_new_exec()
	 * - access it with [gs]et_task_comm()
	 * - lock it with task_lock()
	 */
	char				comm[TASK_COMM_LEN];
	//...
};
```

该结构体中就具有双向链表节点`tasks`，所以通过它就将所有的 task 都链接了起来，那么问题来了：这个链表的头在哪里？

# 0 号进程

Linux kernel 会以全局变量的方式创建 0 号进程”swapper“，该进程在启动后才会去创建 PID 为 1 的"init"进程，所以该进程便是所有 tasks 的头节点，可以通过它来遍历所有的 task。

> 由于是全局变量，所以该进程是不能被杀死或停止的。

`swapper`进程的精妙之处在于，它的优先级是最低的，当整个系统没有 task 在运行时，便会运行该进程，该进程可以管理一些资源，且可以让 CPU 进入浅度睡眠以省电。

0 号进程的定义位于`init/init_task.c`中。

# 内核模块来输出 tasks

模块代码如下：

```c
#define pr_fmt(fmt) "tasks:" fmt

#include <linux/init.h>
#include <linux/module.h>
#include <linux/list.h>
#include <linux/sched/task.h>
#include <linux/pid.h>
#include <linux/sched.h>

static void print_tasks(void)
{
    struct task_struct* current_entry = NULL;
    struct task_struct* next_entry = NULL;

    pr_info("pid = %d, name = %s\n",
            task_pid_nr(&init_task),
            init_task.comm);

    list_for_each_entry_safe(current_entry, next_entry,
                             &(init_task.tasks), tasks) {
        pr_info("pid = %d, name = %s\n",
                task_pid_nr(current_entry),
                current_entry->comm);
    }
}

static int __init tasks_init(void)
{
    pr_info("Hello world!\n");
    print_tasks();
    return 0;
}
module_init(tasks_init);

static void __exit tasks_exit(void)
{
    pr_info("Bye!\n");
}
module_exit(tasks_exit);

MODULE_AUTHOR("kcmetercec <kcmeter.cec@gmail.com>");
MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("A simple demo which prints tasks");
MODULE_ALIAS("print tasks demo");
MODULE_VERSION("ver1.0");
```



对应的 Makefile 如下：

```makefile
KVERS = $(shell uname -r)

obj-m += print_tasks.o

EXTRA_CFLAGS = -std=gnu99

build: kernel_modules

kernel_modules:
        make -C /lib/modules/$(KVERS)/build M=$(CURDIR) modules

clean:
        make -C /lib/modules/$(KVERS)/build M=$(CURDIR) clean

```



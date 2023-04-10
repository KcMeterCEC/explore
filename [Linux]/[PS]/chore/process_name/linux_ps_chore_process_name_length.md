---
title: Linux 进程的名称最长是多少个字符？
tags: 
- linux
categories:
- linux
- ps
- chore
date: 2023/4/10
updated: 2023/4/10
layout: true
comments: true
---

- kernel version : v6.1.x (lts)

Linux 在运行可执行文件时，可以显示多长的进程名称？

<!--more-->

# task_struct

进程或线程在内核中都由结构体`task_struct`来表示，在该结构体中具有一个字符串数组用于存放该运行进程的名称：

```c
/*
 * Define the task command name length as enum, then it can be visible to
 * BPF programs.
 */
enum {
	TASK_COMM_LEN = 16,
};

struct task_struct {
    //...
	/*
	 * executable name, excluding path.
	 *
	 * - normally initialized setup_new_exec()
	 * - access it with [gs]et_task_comm()
	 * - lock it with task_lock()
	 */
	char comm[TASK_COMM_LEN];
    //...
};
```

从上面的代码可以看出：进程的最长名字是 15 个字符（最后再加上一个字符串结束符）。

## /proc/\<pid\>/stat

每个进程的名称可以在`/proc/<pid>/stat`和`/proc/<pid>/status`中查看。

比如现在随便写一个测试代码：

```cpp
#include <iostream>
#include <chrono>
#include <thread>

int main(int argc, char* argv[]) {
    while (1) {
        std::cout << "Hello world!\n";

        std::this_thread::sleep_for(std::chrono::seconds(3));
    }
};
```

并给它取一个较长的名字：`0123456789abcdefABCDEF`，包含除结束字符串外的 22 个字符。

启动该进程后，在`/proc`对应的文件夹下查看：

```shell
cec@box:~$ cat /proc/1317/stat
1317 (0123456789abcde) S 1226 1317 ......
cec@box:~$ cat /proc/1317/status
Name:   0123456789abcde
Umask:  0002
State:  S (sleeping)

......
```

那可以看到，其名称的确是被限制到了 15 个字符。

## 对应内核的代码

当对`/proc/<pid>/stat`和`/proc/<pid>/status`进行查看时，对应代码位于`/fs/proc/array.c`中：

```c
int proc_pid_status(struct seq_file *m, struct pid_namespace *ns,
			struct pid *pid, struct task_struct *task)
{
	struct mm_struct *mm = get_task_mm(task);

	seq_puts(m, "Name:\t");
	proc_task_name(m, task, true);
	seq_putc(m, '\n');

    //...
	return 0;
}

static int do_task_stat(struct seq_file *m, struct pid_namespace *ns,
			struct pid *pid, struct task_struct *task, int whole)
{
    //...

	seq_put_decimal_ull(m, "", pid_nr_ns(pid, ns));
	seq_puts(m, " (");
	proc_task_name(m, task, false);
	seq_puts(m, ") ");
	seq_putc(m, state);
	seq_put_decimal_ll(m, " ", ppid);
    //...
}
```

关于 task 名称，都是调用的 `proc_task_name`函数：

```c
char *__get_task_comm(char *buf, size_t buf_size, struct task_struct *tsk)
{
	task_lock(tsk);
	/* Always NUL terminated and zero-padded */
	strscpy_pad(buf, tsk->comm, buf_size);
	task_unlock(tsk);
	return buf;
}
EXPORT_SYMBOL_GPL(__get_task_comm);


void proc_task_name(struct seq_file *m, struct task_struct *p, bool escape)
{
	char tcomm[64];

	/*
	 * Test before PF_KTHREAD because all workqueue worker threads are
	 * kernel threads.
	 */
	if (p->flags & PF_WQ_WORKER)
		wq_worker_comm(tcomm, sizeof(tcomm), p);
	else if (p->flags & PF_KTHREAD)
		get_kthread_comm(tcomm, sizeof(tcomm), p);
	else
		__get_task_comm(tcomm, sizeof(tcomm), p);

	if (escape)
		seq_escape_str(m, tcomm, ESCAPE_SPACE | ESCAPE_SPECIAL, "\n\\");
	else
		seq_printf(m, "%.64s", tcomm);
}
```

由于用户态进程并不属于工作队列和内核线程，所以就会运行函数`__get_task_comm`，该函数就是将 task_struct 中的 comm 数组的内容拷贝过来，这样就能够一一对应了。

# 全名称显示

当使用 `ps -aux` 时，却可以显示完整的进程名：

```shell
cec@box:~$ ps -aux | grep "0123456"
cec         1317  0.0  0.0   5888  1512 pts/1    S+   22:45   0:00 ./0123456789abcdefABCDEF

```



这是因为，`ps -aux`获取名称是通过`/proc/<pid>/cmdline`来获取的，也就是说它显示的是进程的输入命令行：

```shell
cec@box:~$ cat /proc/1317/cmdline
./0123456789abcdefABCDEF
```

该文件对应的内核代码是位于`/fs/proc/base.c`中：

```c
static ssize_t proc_pid_cmdline_read(struct file *file, char __user *buf,
				     size_t count, loff_t *pos)
{
	struct task_struct *tsk;
	ssize_t ret;

	BUG_ON(*pos < 0);

	tsk = get_proc_task(file_inode(file));
	if (!tsk)
		return -ESRCH;
	ret = get_task_cmdline(tsk, buf, count, pos);
	put_task_struct(tsk);
	if (ret > 0)
		*pos += ret;
	return ret;
}
```

该函数最终会从`mm_struct`中获取 arg list，而`mm_struct`又是`task_struct`的成员，所以说`task_struct`封装了进程的资源。

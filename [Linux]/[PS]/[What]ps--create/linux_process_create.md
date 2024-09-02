---
title: Linux下进程的创建
tags: 
- linux
categories:
- linux
- process
- overview
date: 2024/9/2
updated: 2024/9/2
layout: true
comments: true
---

| kernel version | arch  |
| -------------- | ----- |
| v5.4.0         | arm32 |

Linux 创建进程是基于 COW 实现的，现在再来深入一下。

<!--more-->

# 为什么需要 COW 技术

由于基于 COW 技术，fork() 的实际开销就是复制父进程的页表以及给子进程创建唯一的进程描述符。

假设子进程运行和父进程一样的代码，那么只有在子进程写内存时才会真正的进行对应部分页表映射，这样：

1. 将传统 fork() 整个拷贝的开销均摊到了平时的操作中，降低了时间复杂度
2. 极有可能子进程仅仅写一小部分内存，这样降低了物理内存的占用

假设子进程启动后会运行 `exec()` 执行其他的可执行代码，那么就避免传统 fork() 大量拷贝所做的无用功。

# fork()

fork(),vfork(),__clone() 库函数调用实际上都是根据需要传入一些列的参数给 `clone()` ，在内核中由 `clone()` 去调用 `_do_fork()` :

``` c
/*
,*  Ok, this is the main fork-routine.
,*
,* It copies the process, and if successful kick-starts
,* it and waits for it to finish using the VM if required.
,*
,* args->exit_signal is expected to be checked for sanity by the caller.
,*/
long _do_fork(struct kernel_clone_args *args)
{
	u64 clone_flags = args->flags;
	struct completion vfork;
	struct pid *pid;
	struct task_struct *p;
	int trace = 0;
	long nr;

	/*
	 * Determine whether and which event to report to ptracer.  When
	 * called from kernel_thread or CLONE_UNTRACED is explicitly
	 * requested, no event is reported; otherwise, report if the event
	 * for the type of forking is enabled.
	 */
	if (!(clone_flags & CLONE_UNTRACED)) {
	  if (clone_flags & CLONE_VFORK)
		trace = PTRACE_EVENT_VFORK;
	  else if (args->exit_signal != SIGCHLD)
		trace = PTRACE_EVENT_CLONE;
	  else
		trace = PTRACE_EVENT_FORK;

	  if (likely(!ptrace_event_enabled(current, trace)))
		trace = 0;
	}

	//复制父进程的资源
	p = copy_process(NULL, trace, NUMA_NO_NODE, args);
	add_latent_entropy();

	if (IS_ERR(p))
	  return PTR_ERR(p);

	/*
	 * Do this prior waking up the new thread - the thread pointer
	 * might get invalid after that point, if the thread exits quickly.
	 */
	trace_sched_process_fork(current, p);

	pid = get_task_pid(p, PIDTYPE_PID);
	nr = pid_vnr(pid);

	if (clone_flags & CLONE_PARENT_SETTID)
	  put_user(nr, args->parent_tid);

	if (clone_flags & CLONE_VFORK) {
	  p->vfork_done = &vfork;
	  init_completion(&vfork);
	  get_task_struct(p);
	}

	wake_up_new_task(p);

	/* forking complete and child started to run, tell ptracer */
	if (unlikely(trace))
	  ptrace_event_pid(trace, pid);

	if (clone_flags & CLONE_VFORK) {
	  if (!wait_for_vfork_done(p, &vfork))
		ptrace_event_pid(PTRACE_EVENT_VFORK_DONE, pid);
	}

	put_pid(pid);
	return nr;
}
```

`copy_process` 在复制父进程资源时，执行了如下流程：
- `dup_task_struct()` : 为新进程创建内核栈、thread_info、task_struct。
  + 它们的值与父进程相同，那么它们的描述符也是一样的
- `task_rlimit()` : 检测新创建子进程后，当前用户所拥有的进程数目没有超出限制
- 子进程初始化自己的 task_struct，使得与父进程区别开来
- 拷贝父进程指向的文件、地址空间、信号处理等
- `alloc_pid()` : 为新进程分配有效的 PID
- 返回新申请的 task_struct

# vfork()

vfork() 相比 fork() 而言就是不拷贝父进程的页表，这样 vfork() 与父进程共享内存空间，就相当于一个线程了。

一般使用 vfork() 后会立即调用 exec() 来读取新的代码。这在性能上的节约相比 fork() 后再使用 exec() 也高不了多少。

但有一个特性：vfork() 之后父进程被阻塞，直到子进程调用 exit() 或执行 exec()。

也就是说，vfork() 在执行 exec() 之后父进程才执行，这可以保证父子进程之间的同步关系。

vfork() 调用相比 fork() 调用在参数中多了一些标记：

``` c
SYSCALL_DEFINE0(vfork)
{
	struct kernel_clone_args args = {
									 .flags		= CLONE_VFORK | CLONE_VM,
									 .exit_signal	= SIGCHLD,
	};

	return _do_fork(&args);
}
```

正是 `CLONE_VFORK` 这个标记使得父进程会等待子进程退出或完成：

``` c
if (clone_flags & CLONE_VFORK) {
	p->vfork_done = &vfork;
	init_completion(&vfork);
	get_task_struct(p);
}

//....

if (clone_flags & CLONE_VFORK) {
	if (!wait_for_vfork_done(p, &vfork))
	  ptrace_event_pid(PTRACE_EVENT_VFORK_DONE, pid);
}
``` 

# 线程的创建

线程对内核来讲也是会分配一个 task_struct，只不过这个结构会与其进程共享内存等资源，但在调度算法上并没有区别对待。

在用户空间使用 `pthread_create()`= 创建线程时，实际上是调用了 clone() 函数并传入一些参数：

``` c
/*
,* cloning flags:
,*/

#define CSIGNAL		0x000000ff	/* signal mask to be sent at exit */
#define CLONE_VM	0x00000100	/* set if VM shared between processes */
#define CLONE_FS	0x00000200	/* set if fs info shared between processes */
#define CLONE_FILES	0x00000400	/* set if open files shared between processes */
#define CLONE_SIGHAND	0x00000800	/* set if signal handlers and blocked signals shared */
#define CLONE_PIDFD	0x00001000	/* set if a pidfd should be placed in parent */
#define CLONE_PTRACE	0x00002000	/* set if we want to let tracing continue on the child too */
#define CLONE_VFORK	0x00004000	/* set if the parent wants the child to wake it up on mm_release */
#define CLONE_PARENT	0x00008000	/* set if we want to have the same parent as the cloner */
#define CLONE_THREAD	0x00010000	/* Same thread group? */
#define CLONE_NEWNS	0x00020000	/* New mount namespace group */
#define CLONE_SYSVSEM	0x00040000	/* share system V SEM_UNDO semantics */
#define CLONE_SETTLS	0x00080000	/* create a new TLS for the child */
#define CLONE_PARENT_SETTID	0x00100000	/* set the TID in the parent */
#define CLONE_CHILD_CLEARTID	0x00200000	/* clear the TID in the child */
#define CLONE_DETACHED		0x00400000	/* Unused, ignored */
#define CLONE_UNTRACED		0x00800000	/* set if the tracing process can't force CLONE_PTRACE on this clone */
#define CLONE_CHILD_SETTID	0x01000000	/* set the TID in the child */
#define CLONE_NEWCGROUP		0x02000000	/* New cgroup namespace */
#define CLONE_NEWUTS		0x04000000	/* New utsname namespace */
#define CLONE_NEWIPC		0x08000000	/* New ipc namespace */
#define CLONE_NEWUSER		0x10000000	/* New user namespace */
#define CLONE_NEWPID		0x20000000	/* New pid namespace */
#define CLONE_NEWNET		0x40000000	/* New network namespace */
#define CLONE_IO		0x80000000	/* Clone io context */

clone(..., CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID, ...);
```

同理，内核线程的创建也会分配一个 task_struct，只是与用户空间请求创建的线程有 1 点不同：内核线程所谓的地址空间就是内核空间，它们只在内核空间运行。
- 在调度方面来讲，内核线程并不天生比用户请求的线程高贵，大家都是同等的被调度，都可以设置各自的调度策略和优先级。

与用户空间相对应最为相似的内核线程创建便是 `kthread_run` 宏，可以看到也是返回了一个 task_struct。

``` c
/**
* kthread_run - create and wake a thread.
* @threadfn: the function to run until signal_pending(current).
* @data: data ptr for @threadfn.
* @namefmt: printf-style name for the thread.
*
* Description: Convenient wrapper for kthread_create() followed by
* wake_up_process().  Returns the kthread or ERR_PTR(-ENOMEM).
*/

#define kthread_run(threadfn, data, namefmt, ...)                 \
({                                                              \
	struct task_struct *__k                                       \
	= kthread_create(threadfn, data, namefmt, ## __VA_ARGS__);  \
	if (!IS_ERR(__k))                                             \
	wake_up_process(__k);                                       \
	__k;                                                          \
})
```

终止内核线程便可以通过其返回的 task_struct 指针：

``` c
  int kthread_stop(struct task_struct *k);
``` 

# 进程的终结

进程的终结是通过内核 `do_exit()` 函数来完成的，其步骤如下：

1. `exit_signals()` 将 task_struct 中的标志成员设置为 `PF_EXITING`
2. 删除任意内核定时器，确保没有定时器在排队，也没有定时器处理程序在运行
3. 如果进程记账功能是开启的，调用 `acct_update_integrals()` 输出记账信息
4. `exit_mm()` 释放进程占用的 mm_struct，如果没有别的进程使用它，就彻底释放它们
5. `exit_sem()` 释放信号量
6. `exit_shm()` 释放共享内存
7. `exit_files()，exit_fs()` 递减文件描述符和文件系统引用计数，如果计数值降为 0，那么就释放资源。
8. 将退出码存入 task_struct 的 exit_code 成员，用于父进程检索退出原因
9. `exit_notify()` 通知父进程，并将当前进程设置为 `EXIT_ZOMBIE` 僵死状态。
10. `do_task_dead()` 切换到新的进程。
    
在调用 `exit_notify()` 通知父进程外，还需要为此进程的子进程找到新的父进程，其会执行 `forget_original_parent()` ,
然后会调用 `find_new_reaper` 为子进程找到新的父进程，其搜寻的先后顺序是：

1. 在当前线程组内找个一个线程作为父进程
2. 如果不行，就看哪个进程将其设置为了 subreaper 属性，如果有就将其作为父进程
3. 如果还是不行，就将 init 进程设置为父进程

经过上面步骤以后，该进程还保有内核栈、thread_info 和 task_struct 结构，用于向父进程提供信息。

在父进程通过 wait 类系统调用获取到该进程的退出状态后，进程剩余的内存也就被释放，归还给系统了。

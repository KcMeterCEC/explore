---
title: Linux下进程和线程的基本概念及操作
tags: 
- linux
categories:
- linux
- process
- overview
date: 2024/8/31
updated: 2024/8/31
layout: true
comments: true
---

| kernel version | arch  |
| -------------- | ----- |
| v5.4.0         | arm32 |

<!--more-->

# 进程

首先需要明确的是：进程是资源分配的基本单位，线程是调度的基本单位。同一进程里的线程之间共享进程的资源。

## 进程的表示

在Linux内核中，使用结构体(PCB) `task_struct` （位于 include/linux/sched.h）来表明一个进程，其中不仅包括了此进程的资源，还有其状态、优先级等参数。

此结构体中就包含了内存资源、文件系统路径、打开的文件资源等：

```c
struct fs_struct {
    int users;
    //...
    //指定了根路径以及当前路径
    struct path root, pwd;
} __randomize_layout;


/*
 * Open file table structure
 */
struct files_struct {
  /*
   * read mostly part
   */
    atomic_t count;
    bool resize_in_progress;
    wait_queue_head_t resize_wait;

    struct fdtable __rcu *fdt;
    struct fdtable fdtab;
  /*
   * written part on a separate cache line in SMP
   */
    spinlock_t file_lock ____cacheline_aligned_in_smp;
    unsigned int next_fd;
    unsigned long close_on_exec_init[1];
    unsigned long open_fds_init[1];
    unsigned long full_fds_bits_init[1];

    //存储打开的文件
    struct file __rcu * fd_array[NR_OPEN_DEFAULT];
};
```

## 进程的限制

系统中可以创建的进程总数是有限的，同理单个用户可以创建的进程数也是有限的。

- 用户可以使用 `ulimit -u` 查看限制的进程数，也可以使用 `getrlimit(),setrlimit()` 来得到或设置资源
- 在`/proc/sys/kernel/pid_max`中表示了整个系统的进程限制

```c
#include <stdio.h>
#include <sys/time.h>
#include <sys/resource.h>

int main(void) {
    struct rlimit rl;

    if(getrlimit(RLIMIT_NPROC, &rl) != 0) {
            perror("can not get the limit of process!");
    }

    if(rl.rlim_cur == RLIM_INFINITY) {
            printf("the maximum number of process is unlimit!\n");
            return 0;
    }

    printf("The limit number of process is %lu, and the hardware maxinum number of process is %lu\n",
           rl.rlim_cur, rl.rlim_max);

    return 0;
}
```

### fork bomb

由于系统的进程是有限的，如果无限制的创建进程，那最终将导致进程被耗光，也就相当于系统资源被消耗完而出现系统死掉的现象。

>  [fork bomb](https://en.wikipedia.org/wiki/Fork_bomb) 就是基于这个原理做出来的。

### android 提权漏洞

[提权漏洞](https://blog.csdn.net/feglass/article/details/46403501) 就是因为pid会被恶意消耗完，而代码没有检查自己降权成功而导致的root权限问题。

## 进程的链接

Linux内核以三种数据结构来链接进程PCB：

- 链表 ： 用于遍历所有进程
- 树 ： 用于查看进程的继承关系
  + 使用命令 `pstree` 可以查看进程的树形结构
- 哈希表 ： 用于快速查找出进程

## 进程的树形结构

进程是以树的形式创建的，也是基于这个关系使得父进程可以监控子进程。

- 当子进程意外退出后，父进程可以获取其退出的原因并且重新启动它。

## 进程的状态

![](./linux_process_life_cycle.jpg)

**注意：**

1. Linux的调度算法仅针对就绪态和运行态的调度!
2. 内核以 `task_struct` 为单位进行调度!

### 理解僵死态

僵死态就是进程已经退出， **其占有的资源已经被释放，但父进程还没有清理其PCB时的一个状态**。

当父进程清理子进程PCB后(通过 `waitpid` 实现)，那么对于该进程的所有痕迹都被清除了。

- 只要进程一退出，其所占有的所有资源都被释放了，所以不用担心代码里面动态申请的内存还未来得及释放
- 如果父进程没有清理子进程，那么其最后的PCB就代表它的尸体存在。
  + 可以通过 `ps -aux` 命令来查看其状态。

可以通过以下代码来理解：

```c
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

#define CLEAR_CHILD_PID 0

int main(void) {
    int status = 0;
    pid_t child_pid = fork();

    if (child_pid == -1) {
        perror("can not fork process:");
    } else if (child_pid == 0) {
        printf("This is child process, my pid is %d\n", getpid());
        while(1);
    } else {
#if CLEAR_CHILD_PID
        printf("This is parent process, i get child pid is %d\n", child_pid);

        if (waitpid(child_pid, &status, 0)) {

        }
        if(WIFEXITED(status)) {
            printf("The child was terminated normally!");
            printf("exit status = %d\n", WEXITSTATUS(status));
        }
        if(WIFSIGNALED(status)) {
            printf("The child was terminated by signal %d\n", WTERMSIG(status));
#ifdef WCOREDUMP
            if(WCOREDUMP(status))
            {
                printf("The child produced a core dump!\n");
            }
#endif
        }
        if(WIFSTOPPED(status)) {
            printf("The chiild process was stopped by delivery of a signal %d\n",
                    WSTOPSIG(status));
        }
        if(WIFCONTINUED(status)) {
            printf("The child process was resumed by delivery of SIGCONT\n");
        }
#else
        while(1);
#endif
    }

    return 0;
}
```

可以看到:

- 当父进程使用 `waitpid()` 时，外部使用 `kill` 命令后，使用 `ps -aux` 看不到子进程的任何痕迹
- 当父进程没有使用 `waitpid()` 来清除子进程的僵死态时，使用 `ps -aux` 看到其状态是 `Z+` 。
  + 当父进程被终止后，其僵死态也消失了。

### 理解内存泄露

根据上面对僵死态的理解，可以知道 **只要进程退出，就会释放其所占的资源，也就没有所谓的内存泄露**

内存泄露指的是： **在进程运行时**其所占用的内存随着时间的推移在震荡的上升。

- 正常的进程所占用的内存应该是在一个平均值周围震荡。

### 理解停止态

停止态用于 **主动暂停进程**，有点类似于给这个进程打了一个断点（此进程已经不占用CPU资源）。在需要其运行的时候，又可以让其继续运行。

- 睡眠是进程没有获取到资源而 **主动让出CPU**

- 在shell中可以使用 `Ctrl + Z` 来让一个进程进入停止状态，使用 `fg` 来让其再次前台运行， `bg` 进入后台运行
  
  + 也可以使用 `cpulimit` 命令来限制某个进程的利用率，其内部就是在让进程间歇性的进入停止态以控制其CPU利用率

### 理解睡眠

当一个进程在等待资源时便会进入睡眠态，一般情况下都会设置为浅度睡眠，只有在读写块设备这种情况才会深度睡眠。

睡眠的底层实现，是将 `task_struct` 放入等待队列中，然后在接收到信号或资源可用来唤醒此队列中的一个进程。

如下面的示例代码所示：

```c
    int ret;
    struct globalfifo_dev *dev = container_of(filp->private_data,
        struct globalfifo_dev, miscdev);

    DECLARE_WAITQUEUE(wait, current);

    mutex_lock(&dev->mutex);
    add_wait_queue(&dev->r_wait, &wait);

    while (dev->current_len == 0) {
        if (filp->f_flags & O_NONBLOCK) {
            ret = -EAGAIN;
            goto out;
        }
        __set_current_state(TASK_INTERRUPTIBLE);
        mutex_unlock(&dev->mutex);

        schedule();
        if (signal_pending(current)) {
            ret = -ERESTARTSYS;
            goto out2;
        }

        mutex_lock(&dev->mutex);
    }
```

## fork()

fork()的作用是在一个进程的基础上为其分裂出一个子进程，其内部是为子进程单独分配了一个 `task_struct` 的PCB。

此时两个进程分别通过fork()来返回，父进程中fork()返回子进程的pid，子进程中的fork()返回0。

### 父进程与子进程资源->fork()

当父进程通过 fork() 创建子进程时，子进程除了拥有一个PCB外，也具有与父进程 **一样的资源** （内存、文件系统、文件、信号等）。

在接下来的过程中，父子进程可以分别单独的修改自己的资源，二者并不会冲突。 

在实现逻辑的过程中，**内存资源**的分离是基于 **具有MMU支持的COW技术** 来实现的。

- 在 fork() 前，内存资源是可读可写的
- 在 fork() 后二者的内存资源都 **变为只读** 的，此时父子进程对应内存的虚拟地址和物理地址都是一致的
- 父或子进程的其中一个修改内存时，便会触发MMU的 pagefault
- 然后内核会为此进程访问的内存重新申请页表，让其对应到另一个物理地址
- 最后父子进程虽然虚拟地址一样，但它们对应的物理地址就不一样了，并且它们的内存资源权限又恢复为可读可写了
- 最终此进程的内存修改才正式生效（Linux 会修改 PC 指针重新到写的那部分代码，这次写才会有效）

所有在内存分离时，最开始的操作是比较耗时的！

验证内存分离的代码如下：

```c
#include <stdio.h>
#include <unistd.h>

static int val = 123;

int main(void) {
    pid_t child_pid = fork();

    if(child_pid == -1) {
      perror("fork() failed!");
    } else if(child_pid == 0) {
        printf("This is child process, my pid is %d\n", getpid());
        printf("child: val = %d\n", val);
        val *= 2;
        printf("child: val = %d\n", val);
    } else {
        sleep(1);
        printf("This is parent process, val  = %d\n", val);
    }
    return 0;
}
```

### 父进程与子进程资源 -> vfork()

当硬件中没有MMU支持时，父进程通过vfork()来创建子进程，子进程拥有一个新的PCB，此时二者是具有 **完全一样的内存资源（但文件系统、文件、信号等资源是分离的）** ，且 **无法完成内存分离** 。

- 所以，无论是父还是子修改了内存，这些修改对于另一方是可见的
- 如果子进程没有退出，父进程是无法运行的。

### 父进程与子进程资源 -> clone()

父进程通过clone()来创建子进程，子进程拥有一个新PCB，此时二者是具有 **完全一样的所有资源，也就是共享所有资源** ， 那就是一个线程了!

- 子进程的资源指针直接指向父进程的资源
- pthread_create()的底层就是由clone()所支持的

## 孤儿

### 实例展示

```c
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

#define CLEAR_CHILD_PID 0

int main(void) {

    int status = 0;
    pid_t child_pid = fork();

    if(child_pid == -1)
    {
        perror("can not fork process:");
    } else if(child_pid == 0) {
        printf("This is child process, my pid is %d\n", getpid());
        printf("check parent pid...\n");
        while(1)
        {
            printf("My parent pid is %d\n", getppid());
            sleep(1);
        }
    } else {
#if CLEAR_CHILD_PID
        printf("This is parent process, i get child pid is %d\n", child_pid);
        if(waitpid(child_pid, &status, 0))
        {

        }
        if(WIFEXITED(status)) {
            printf("The child was terminated normally!");
            printf("exit status = %d\n", WEXITSTATUS(status));
        }
        if(WIFSIGNALED(status)) {
            printf("The child was terminated by signal %d\n", WTERMSIG(status));
#ifdef WCOREDUMP
            if(WCOREDUMP(status))
            {
                printf("The child produced a core dump!\n");
            }
#endif
        }
        if(WIFSTOPPED(status)) {
            printf("The chiild process was stopped by delivery of a signal %d\n",
                    WSTOPSIG(status));
        }
        if(WIFCONTINUED(status)) {
            printf("The child process was resumed by delivery of SIGCONT\n");
        }
#else
        while(1) {
            sleep(1);
        }
#endif
    }

    return 0;
}
```

通过上面的代码查看，当kill掉父进程以后，子进程的 parent pid 会变为另外一个进程的pid。

- 此父进程有可能是init进程，也可能是具有subreaper属性的进程。
  + 这要根据子进程是否挂接在各自的链表中
    ![](./orphan.jpg)

### subreaper

subrepaer 是在3.4后引入的，当将进程设置为 repaer 时需要注意wait子进程，以回收它的PCB。

```c
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/prctl.h>
#include <signal.h>

void sig_handler(int num) {
    int status = 0;
    printf("get sig_handler = %d\n", num);
    if(waitpid(-1, &status, 0) == -1) {
        perror("wait signal failed!");
    }
    if(WIFEXITED(status)) {
        printf("The child was terminated normally!");
        printf("exit status = %d\n", WEXITSTATUS(status));
    }
    if(WIFSIGNALED(status)) {
        printf("The child was terminated by signal %d\n", WTERMSIG(status));
#ifdef WCOREDUMP
        if(WCOREDUMP(status))
        {
            printf("The child produced a core dump!\n");
        }
#endif
    }
    if(WIFSTOPPED(status)) {
        printf("The chiild process was stopped by delivery of a signal %d\n",
                WSTOPSIG(status));
    }
    if(WIFCONTINUED(status)) {
        printf("The child process was resumed by delivery of SIGCONT\n");
    }
}

int main(void) {

    if(prctl(PR_SET_CHILD_SUBREAPER, 1) < 0)
    {
        perror("can not to be a subreaper!");
        return -1;
    }

    pid_t child_pid = fork();

    if(child_pid == -1) {
        perror("can not fork process:");
    }
    else if(child_pid == 0) {
        if(fork() == -1) {
            perror("can not fork process:");
        }
        while(1)
        {
            printf("childl-> %d parent pid is %d\n",getpid(), getppid());
            sleep(1);
        }
    } else {
        while(1) {
            if(signal(SIGCHLD,sig_handler) == SIG_ERR) {
                perror("wait signal error:");
            }
        }
    }

    return 0;
}
```

## 根进程

Linux在启动的过程会创建进程0，此进程0会创建init进程1，此后所有的进程都是挂接在init进程下的。

进程0在完成创建init进程后，会设置自己的优先级为最低，也就是将自己退化成了idle进程。
当其他进程都不占有CPU时，idle进程会运行，并将CPU置为低功耗模式。
当接收到中断后，如果有其他进程调度便又会将CPU让给其他进程。

# 线程

由上面的 `clone()` 可以看出：在Linux中创建线程实际上在内核也会位置分配一个 `task_struct` ，但它们的资源都指向同一个地址。
而 `task_struct` 中具有pid，这样在创建线程的同时也创建了多个pid。

## tgid

为了符合操作系统中关于线程的要求：一个进程中的多个线程所访问的pid都是一致的。

Linux内核使用 TGID(thread group ID)，来使得上层调用 `getpid()` 时获取的pid，都是最初此进程的pid，而其他的pid被掩盖了。

- 可以在shell中访问 `/proc/[pid]/task/` 中看到几个被掩盖的pid
  + 也可以使用 `top -H` 来查看各个线程对应的Pid
- 在编程时，使用系统调用 `syscall(__NR_gettid)` 来获取自己真实的pid

```c
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/syscall.h>

static pid_t gettid(void)
{
return syscall(__NR_gettid);
}
static void *thread_func(void *param)
{
printf("process pid = %d, thread pid = %d, thread_self = %d\n",
       getpid(), gettid(), pthread_self());
while(1);
return NULL;
}
int main(void)
{
pthread_t tid1, tid2;
//pthread_self() 是用户空间库所创建的ID，内核不可见
printf("process pid = %d, man thread pid = %d,man thread_self = %d\n",
       getpid(), gettid(), pthread_self());

if(pthread_create(&tid1, NULL, thread_func, NULL) == -1)
  {
    perror("create thread failed:");
    return -1;
  }
if(pthread_create(&tid1, NULL, thread_func, NULL) == -1)
  {
    perror("create thread failed:");
    return -1;
  }
if(pthread_create(&tid1, NULL, thread_func, NULL) == -1)
  {
    perror("create thread failed:");
    return -1;
  }
while(1);
return 0;
}
```

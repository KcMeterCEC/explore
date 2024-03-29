---
title: Linux 服务器程序规范
tags: 
- network
categories:
- network
- basic
date: 2022/6/10
updated: 2022/6/10
layout: true
comments: true
---

Linux 服务器程序有一些基本的规范：
- Linux 服务器程序以守护进程的方式运行
- Linux 服务器程序通常有一套日志系统，一般在 `var/log` 目录下有自己的日志目录
  + 如果是使用 c++ 的话，那记录日志使用 [spdlog](https://github.com/gabime/spdlog) 是个很好的选择
- Linux 服务器程序一般会创建一个用户来运行自己的程序
- Linux 服务器程序的配置文件存放在`/etc`目录下
- Linux 服务器程序在启动后会在`/var/run`目录中生成一个 PID 文件，以记录进程 PID
- Linux 服务器进程需要考虑系统资源和限制，以预测自身能够承受多大负荷

<!--more-->

# 日志

## Linux 系统日志

![](./log_struct.jpg)

Linux 提供了 `rsyslogd` 守护进程来处理系统日志，它既能够接收用户进程输出日志，又可以接收内核日志。

- 用户进程调用 `syslog()` 函数生成日志，该函数将日志输出到 `AF_UNIX` 类型的文件 `/dev/log` 中, `rsyslogd` 监听 `/dev/log` 将内存输出至 `/var/log/`
  - 进程日志的存放位置由 `/etc/rsyslog.d/*.conf` 文件指定
- 内核日志由 `printk` 等函数打印到内核环形缓存，其内容被映射到 `/proc/kmsg` , `rsyslogd` 读取该文件后存储日志
  - 内核日志被存放于 `/var/log/kern.log`   

## syslog

``` c
#include <syslog.h>

// openlog 和 closelog 是可选函数
void openlog(const char *ident, int option, int facility);
void syslog(int priority, const char *format, ...);
void closelog(void);

//只有打印等级符合 mask 的日志才被存储
//等级的 mask 由宏 LOG_MASK(priority) 获取
int setlogmask(int mask);
```

`priority` 指定日志级别，默认值是 `LOG_USER` ，可选值有：
- `LOG_EMERG` ： 系统不可用
- `LOG_ALERT` ：报警，需要立即采取动作
- `LOG_CRIT` ：严重情况
- `LOG_ERR` ：错误
- `LOG_WARNING` ：警告
- `LOG_NOTICE` ：通知
- `LOG_INFO` ：信息
- `LOG_DEBUG` ：调试

`openlog()` 可以在日志中添加附加信息：
- `ident` : 指定的字符串将被附加到日志之后，当设置为 NULL，则为程序名称
- `option` : 指定打印行为，比如是否包含 PID，是否延迟打开日志等
- `facility` : 说明输出日志的程序属于哪种类别
  
`setlogmask()` 设置日志的打印级别，这样在不用的应用场景可以屏蔽一些冗余输出。


# 用户信息

## UID,EUID,GID,EGID

UID : 运行该进程的用户 ID

EUID : 该程序所有者的真实用户 ID,当该程序权限设置了 `set-user-id` 标志后，运行该程序的用户就可以以文件所有者的权限来执行
- 比如 `su` 程序就具有 `set-user-id` 标志，这样才能够修改自身密码

> GID（运行该进程的组 ID），EGID（程序所有者的组 ID）同理

``` c
#include <unistd.h>
#include <sys/types.h>

//获取真实用户 ID
uid_t getuid(void);
//获取有效用户 ID
uid_t geteuid(void);
//获取真实组 ID
gid_t getgid(void);
//获取有效组 ID
gid_t getegid(void);

//设置真实用户 ID
int setuid(uid_t uid);
//设置有效用户 ID
int seteuid(uid_t euid);
//设置真实组 ID
int setgid(gid_t gid);
//设置有效组 ID
int setegid(gid_t egid);
```

## 切换用户

以下代码将以 `root` 身份启动的进程切换为以普通用户身份运行：
- 以 `root` 身份运行该代码即可查看效果
``` c
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

static bool switch_to_user(uid_t user_id, gid_t gp_id) {
    //确保目标用户不是 root
    if ((user_id == 0) && (gp_id == 0)) {
        printf("error:Can't change to root!\n");
        return false;
     }

    uid_t uid = getuid();

    //如果当前用户是普通用户，则不用切换
    if (uid != 0) {
        return true;
    }

   if ((setgid(gp_id) < 0) || (setuid(user_id) < 0)) {
        perror("Change id error:");
        return false;
    }

    return true;
}

int main(int argc, char *argv[]) {
    printf("before switch, uid = %d, gid = %d\n", getuid(), getgid());

    switch_to_user(1000, 1000);


    printf("after switch, uid = %d, gid = %d\n", getuid(), getgid());
    return 0;
}
```

# 进程关系

## 进程组

每个进程都归属于一个组，所以进程包含进程 ID（PID）和进程组 ID（PGID）。

当一个进程的 PID 等于 PGID 时，此进程便是该进程组的首领进程。
``` c
#include <sys/types.h>
#include <unistd.h>

//获取进程 ID
pid_t getpid(void);
//获取父进程 ID
pid_t getppid(void);

//获取组 ID
pid_t getpgid(pid_t pid);
//设置组 ID,将 PID 为 pid 的进程的 PGID 设置为 pgid
int setpgid(pid_t pid, pid_t pgid);
```

## 会话

一些有关联的进程组将形成一个会话(session)：
``` c
#include <unistd.h>

//创建一个会话
pid_t setsid(void);
//得到会话 ID
pid_t getsid(pid_t pid);
```
调用此函数后：
- 调用进程成为会话的首领，此时该进程是新会话的唯一成员
- 新建一个进程组，其 PGID 与调用进程的 PID 一致，也就是调用进程也是该组的首领
- 调用进程将脱离终端
  
可以使用命令 `ps -o pid,ppid,pgid,sid,comm | less` 来查看几个 ID 的值。

# 系统资源限制

linux 资源限制使用如下函数读取和设置：
``` c
#include <sys/time.h>
#include <sys/resource.h>

struct rlimit {
    //软限制，建议限制，若超过此时，系统可能会终止其运行
    rlim_t rlim_cur;  /* Soft limit */
    //硬限制，软限制的上限，普通程序可以减小，只有 root 可以增大
    rlim_t rlim_max;  /* Hard limit (ceiling for rlim_cur) */
};

//resource 指定资源类型
int getrlimit(int resource, struct rlimit *rlim);
int setrlimit(int resource, const struct rlimit *rlim);

int prlimit(pid_t pid, int resource, const struct rlimit *new_limit,
          struct rlimit *old_limit);
```
`resource` 有些重要设置：
- `RLIMIT_AS` : 虚拟内存总限制，超过将产生 `ENOMEM` 错误
- `RLIMIT_CORE` : 核心转储文件大小限制
- `RLIMIT_CPU` : CPU 时间限制
- `RLIMIT_DATA` : 数据段限制（data,bss,堆）
- `RLIMIT_NOFILE` : 文件描述符数量限制，超过将产生 `EMFILE` 错误
- `RLIMIT_FSIZE` : 文件大小限制，超过将产生 `EFBIG` 错误
- `RLIMIT_NPROC` : 用户能创建的进程数限制，超过将产生 `EAGAIN` 错误
- `RLIMIT_SIGPENDING` : 用户能够挂起的信号数量限制
- `RLIMIT_STACK` : 进程栈内存限制，超过将产生 `SIGSEGV` 信号


# 改变工作目录和根目录

一些服务程序需要修改工作目录和逻辑根目录：
``` c
#include <unistd.h>

//得到当前工作目录绝对路径
char *getcwd(char *buf, size_t size);
//切换工作目录到 path 指定的目录
int chdir(const char *path);
//改变进程逻辑根目录，而当前工作目录并不会切换，所以一般还会在后面加上 chdir("/") 函数以切换工作目录
int chroot(const char *path);
```

# 服务器程序后台化

linux 提供了 `daemon` 函数完成将当前进程切换为守护进程的方式：
``` c
#include <unistd.h>

//当 nochdir 为 0 时，工作目录将被设置为 “/” 根目录，否则继续使用当前目录
//当 noclose 为 0 时，标准输入、标准输出、标准错误输出都会被重定向到 /dev/null 文件，否则依然使用原来设备
int daemon(int nochdir, int noclose);
```

其目的就是为了让当前进程脱离 shell 并且其输出不会出现在终端之上。

下面的代码演示如何将一个进程以守护进程的方式运行：
``` c
#include <stdbool.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <fcntl.h>


bool daemonize(void) {
    //创建子进程，并关闭父进程，使得程序在后台运行
    pid_t pid = fork();

    if(pid < 0) {
        perror("Can't fork:");
        return false;
    } else if(pid > 0) {
        // 关闭父进程
        exit(0);
    }

    //设置文件权限掩码，当进程创建新文件时，文件的权限将是 mode & 0777
    umask(0);

    //创建新会话，本进程即为进程组的首领，其 PID，PGID，SID 一致
    pid_t sid = setsid();
    if(sid < 0) {
        perror("setsid() error:");
        return false;
    }

    //切换工作目录到根目录
    if (chdir("/") < 0) {
        return false;
    }

    //关闭标准输入、输出，标准错误输出
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    //重定向标准输入、输出，标准错误到 /dev/null
    open("/dev/null", O_RDONLY);
    open("/dev/null", O_RDWR);
    open("/dev/null", O_RDWR);

    return true;
}

int main(int argc, char *argv[]) {
    printf("hello world!\n");
    if (daemonize() == false) {
        printf("change to background failed!\n");
        return -1;
    }

    printf("can you see this message? \n");
    while(1) {
        sleep(1);
    }

    return 0;
}
```
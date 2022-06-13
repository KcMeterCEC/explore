---
title: Linux 信号
tags: 
- network
categories:
- network
- basic
date: 2022/6/12
updated: 2022/6/13
layout: true
comments: true
---

理解进程可能会收到的信号，以及捕捉该信号。

<!--more-->

# 概述

信号可以由用户、系统或进程发送给目标进程，信号可以由如下条件产生：
- 对于前台进程，用户可以通过输入特殊的终端字符串来给它发信号。比如 Ctrl+C 会发送中断信号。
- 系统异常，比如非法访问内存
- 系统状态变化，比如 alarm 定时器到期引起 SIGALRM 信号
- 运行 kill 命令或调用 `kill()` 函数

## 发送信号

一个进程给其他进程发送信号使用 kill 函数：
``` C
#include <sys/types.h>
#include <signal.h>
//将信号 sig 发送给 pid 进程
int kill(pid_t pid, int sig);
```

pid 的取值如下：

| pid 参数 | 含义                                                                         |
|----------|------------------------------------------------------------------------------|
| pid > 0  | 信号发送给 PID 为 pid 的进程                                                 |
| pid = 0  | 信号发送给本进程组内的其他进程                                               |
| pid = -1 | 信号发送给除 init 进程外的所有进程，但发送者需要拥有对目标进程发送信号的权限 |
| pid < -1 | 信号发送给组 ID 为 -pid 的进程组中的所有成员                                 |

## 信号处理方式

目标进程可以定义个回调函数来处理接收到的信号，信号原型为：

```c
#include <signal.h>

//传入信号类型
typedef void (*sighandler_t)(int);
```

**需要注意的是：** 此函数应该是可重入的，否则很容易引发一些竞态条件！

目标进程也可以使用宏传入 `signal()` 函数： 
- `SIG_DFL` ：使用默认处理方式，可以结束进程（Term）、忽略信号（Ign）、结束并生成核心转储文件（Core）、暂停进程（Stop）、继续进程（Cont）
- `SIG_IGN` ：忽略目标信号


## Linux 标准信号

| 信号      | 起源     | 默认行为 | 含义                                                    |
|-----------|----------|----------|---------------------------------------------------------|
| SIGHUP    | POSIX    | Term     | 控制终端挂起                                            |
| SIGINT    | ANSI     | Term     | 键盘输入以中断进程（Ctrl + C）                          |
| SIGQUIT   | POSIX    | Core     | 键盘输入使进程退出（Ctrl + \）                          |
| SIGILL    | ANSI     | Core     | 非法指令                                                |
| SIGTRAP   | POSIX    | Core     | 断点陷进，用于调试                                      |
| SIGABRT   | ANSI     | Core     | 进程调用 =abort= 函数时生成该信号                       |
| SIGIOT    | 4.2BSD   | Core     | 和 =SIGABRT= 相同                                       |
| SIGBUS    | 4.2BSD   | Core     | 总线错误，错误的内存访问                                |
| SIGFPE    | ANSI     | Core     | 浮点异常                                                |
| SIGKILL   | POSIX    | Term     | 终止一个进程，该信号不可被捕获或忽略                    |
| SIGUSR1   | POSIX    | Term     | 用户自定义信号1                                         |
| SIGSEGV   | ANSI     | Core     | 非法内存段引用                                          |
| SIGUSR2   | POSIX    | Term     | 用户自定义信号2                                         |
| SIGPIPE   | POSIX    | Term     | 往读端被关闭的管道或者 socket 的连接中写数据            |
| SIGALRM   | POSIX    | Term     | 由 =alarm= 或 =setitimer= 设置的实时闹钟超时引起        |
| SIGTERM   | ANSI     | Term     | 终止进程。kill 命令默认发送的信号就是 SIGTERM           |
| SIGSTKFLT | linux    | Term     | 早期的 Linux 使用该信号来报告数学协处理器栈错误         |
| SIGCLD    | System V | Ign      | 和 =SIGCHLD= 相同                                       |
| SIGCHILD  | POSIX    | Ign      | 子进程状态发生变化（退出或暂停）                        |
| SIGCONT   | POSIX    | Cont     | 启动被暂停的进程（Ctrl+Q)                               |
| SIGSTOP   | POSIX    | Stop     | 暂停进程（Ctrl + S）。该信号不可被捕获或忽略            |
| SIGTSTP   | POSIX    | Stop     | 挂起进程（Ctrl + Z）                                    |
| SIGTTIN   | POSIX    | Stop     | 后台进程试图从终端读取输入                              |
| SIGTTOU   | POSIX    | Stop     | 后台进程试图向终端输出内容                              |
| SIGURG    | 4.2BSD   | Ign      | socket 连接上接收到紧急数据                             |
| SIGXCPU   | 4.2BSD   | Core     | 进程的 CPU 使用时间超过其软限制                         |
| SIGXFSZ   | 4.2BSD   | Core     | 文件尺寸超过其软限制                                    |
| SIGVTALRM | 4.2BSD   | Term     | 与 =SIGALRM= 类似，但它只统计进程用户空间代码的运行时间 |
| SIGPROF   | 4.2BSD   | Term     | 与 =SIGALRM= 类似，同时统计用户代码和内核的运行时间     |
| SIGWINCH  | 4.3BSD   | Ign      | 终端窗口大小发送变化                                    |
| SIGPOLL   | System V | Term     | 与 =SIGIO= 类似                                         |
| SIGIO     | 4.2BSD   | Term     | IO 就绪事件                                             |
| SIGPWR    | System V | Term     | 对于使用 UPS 系统时电池电量过低时发出                   |
| SIGSYS    | POSIX    | Core     | 非法系统调用                                            |
| SIGUNUSED |          | Core     | 保留，通常和 =SIGSYS= 效果相同                          |

## Linux 中断系统调用

如果程序在执行系统调用时处于阻塞状态，此时接收到信号，并且设置了信号处理函数，那么此系统调用将被中断，errno 被设置为 EINTR。
- 对于默认行为是暂停进程的信号，如果没有设置信号处理函数，也可以中断某些系统调用。

可以使用 `sigaction()` 函数为信号设置 `SA_RESTART` 标志以重启被中断的系统调用。

# 信号函数

## signal 系统调用

``` c
#include <signal.h>

//为信号 signum 设置对应的处理函数
//返回前一次调用 signal 函数时传入的函数指针或是 sig 对应的默认处理函数指针
sighandler_t signal(int signum, sighandler_t handler);
```

## sigaction 系统调用

``` c
#include <signal.h>

struct sigaction {
    void     (*sa_handler)(int);//信号处理函数
    void     (*sa_sigaction)(int, siginfo_t *, void *);
    sigset_t   sa_mask;//信号掩码，指定哪些信号不能发送给本进程
    int        sa_flags;//设置接收到信号时的行为
    void     (*sa_restorer)(void);
};

//为信号 signum 设置新的 act 处理方式，并返回 oldact 老的处理方式
int sigaction(int signum, const struct sigaction *act,
            struct sigaction *oldact);
```

# 信号集

信号集用来表示一组信号。

## 信号集函数

``` c
#include <signal.h>

//清空信号集
int sigemptyset(sigset_t *set);
//设置所有信号
int sigfillset(sigset_t *set);
//添加信号到信号集
int sigaddset(sigset_t *set, int signum);
//删除信号到信号集
int sigdelset(sigset_t *set, int signum);
//测试 signum 是否在信号集中
int sigismember(const sigset_t *set, int signum);
```

## 进程信号掩码

``` c
#include <signal.h>
/**
 * @brief 设置或查看进程的信号掩码
 * @par set :设置新的信号掩码
 * @par oldset: 原来的信号掩码
 * @par how：指定设置进程信号掩码的方式，可以有以下值
 * SIG_BLOCK : 新进程信号掩码是其当前值和 set 指定信号集的并集
 * SIG_UNBLOCK：新的进程信号掩码是其当前值移除 set 信号集的结果
 * SIG_SETMASK：直接将进程信号掩码设置为 set
 */
int sigprocmask(int how, const sigset_t *set, sigset_t *oldset);
```

## 被挂起的信号

设置进程信号掩码后，被屏蔽的信号将不能被进程接收。如果给进程发送一个被屏蔽的信号，
则操作系统将该信号设置为进程的一个被挂起的信号。

**如果进程取消对被挂起信号的屏蔽，则它能立即被进程接收到。**

`sigpending()` 函数可以获得进程当前被挂起的信号集：

``` c
#include <signal.h>

int sigpending(sigset_t *set);
```

# 统一事件源

信号处理函数与程序主循环是两条不同的执行路线，并且信号处理函数要尽快的执行完以确保新的信号到来可以及时响应。

很明显，信号处理函数是 I/O 密集型任务，那么就不应该让此函数来进行数据的处理。

典型的解决方案是：信号处理逻辑放在主循环中，当信号处理函数被触发时，它通过管道将信号发送给主循环。

> 这种处理方式就有点类似于中断中的顶半和底半处理。

主循环通过 I/O 复用来统一监听信号时间和其他的 I/O 事件，这就被称为统一事件源。

可以通过 `telnet` 测试以下代码。

``` c
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/epoll.h>
#include <pthread.h>

#include <assert.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

#define MAX_EVENT_NUMBER (1024)
static int pipefd[2];

static int set_nonblocking(int fd) {
    int old_opt = fcntl(fd, F_GETFL);
    int new_opt = old_opt | O_NONBLOCK;

    fcntl(fd, F_SETFL, new_opt);

    return old_opt;
}

// 以边沿触发的方式加入文件描述符
static void add_fd(int epoll_fd, int fd) {
    struct epoll_event event;

    event.data.fd = fd;
    event.events = EPOLLIN | EPOLLET;
    epoll_ctl(epoll_fd, EPOLL_CTL_ADD, fd, &event);

    set_nonblocking(fd);
}

static void sig_handler(int sig) {
    // 这里是为了不破坏全局的 errno
    int save_errno = errno;
    int msg = sig;
    // 向 pipe 写入该消息的值
    send(pipefd[1], (char *)&msg, 1, 0);

    errno = save_errno;

    printf("sig %d received!\n", sig);
}

static void addsig(int sig) {
    struct sigaction sa;

    memset(&sa, 0, sizeof(sa));

    // 指定信号处理函数
    sa.sa_handler = sig_handler;
    // 当进程被打断后，系统调用可以继续运行
    sa.sa_flags |= SA_RESTART;
    sigfillset(&sa.sa_mask);

    // 注册信号处理
    int ret = sigaction(sig, &sa, NULL);
    assert(ret == 0);
}

int main(int argc, char *argv[]) {
    int ret = 0;
    if (argc != 2) {
        printf("usage: %s <port>\n", argv[0]);

        return -1;
    }

    int port = atoi(argv[1]);

    struct sockaddr_in server_addr;

    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);
    server_addr.sin_addr.s_addr = htonl(INADDR_ANY);

    int server_sock = socket(server_addr.sin_family, SOCK_STREAM, 0);
    assert(server_sock > 0);

    ret = bind(server_sock, (const struct sockaddr *)&server_addr, sizeof(server_addr));
    assert(ret == 0);

    ret = listen(server_sock, 5);
    assert(ret == 0);

    struct epoll_event events[MAX_EVENT_NUMBER];
    int epoll_fd = epoll_create(5);
    assert(epoll_fd >= 0);

    add_fd(epoll_fd, server_sock);

    ret = socketpair(PF_UNIX, SOCK_STREAM, 0, pipefd);
    assert(ret = -1);

    set_nonblocking(pipefd[1]);
    // 监控读信号
    add_fd(epoll_fd, pipefd[0]);

    // 增加接受的信号
    addsig(SIGINT);
    addsig(SIGHUP);
    addsig(SIGCHLD);
    addsig(SIGTERM);


    bool stop_server = false;

    while (!stop_server) {
        int number = epoll_wait(epoll_fd, events, MAX_EVENT_NUMBER, -1);
        if ((number < 0) && (errno != EINTR)) {
            perror("epoll failed:");

            break;
        }

        for (int i = 0; i < number; i++) {
            int sock_fd = events[i].data.fd;

            if (sock_fd == server_sock) {
                struct sockaddr_in client_addr;
                socklen_t client_addr_len = sizeof(client_addr);
                int connfd = accept(server_sock, (struct sockaddr *)&client_addr,
                &client_addr_len);

                printf("client : %s -> %d\n", inet_ntoa(client_addr.sin_addr),ntohs(client_addr.sin_port));

                add_fd(epoll_fd, connfd);
            } else if ((sock_fd == pipefd[0]) && (events[i].events & EPOLLIN)) {
                int sig;
                char signals[1024];
                ret = recv(pipefd[0], signals, sizeof(signals), 0);

                if (ret <= 0) {
                    continue;
                } else {
                    // 遍历读取到的信号
                    for (int i = 0; i < ret; ++i) {
                        switch (signals[i]) {
                            case SIGCHLD:
                            case SIGHUP: {
                                printf("continue\n");
                                continue;
                            }break;
                            case SIGTERM:
                            case SIGINT: {
                                stop_server = true;
                                printf("exit server\n");
                            }
                        }
                    }
                }
            } else {
                char recv_buf[1024];
                // 由于工作在 ET 模式，所以需要一次性全部读出
                while (1) {
                    memset(recv_buf, 0, 1024);
                    ret = recv(sock_fd, recv_buf, sizeof(recv_buf), 0);
                    if (ret < 0) {
                        if ((errno == EAGAIN) || (errno == EWOULDBLOCK)) {
                            printf("read empty!\n");
                            break;
                        }
                    } else if(ret == 0) {
                        close(sock_fd);
                    } else {
                        printf("client: %s\n", recv_buf);
                    }
                }
            }
        }
    }

    close(server_sock);
    close(pipefd[1]);
    close(pipefd[0]);

    return 0;
}
```

# 网络编程相关信号

## SIGHUP

当挂起进程的控制终端时，SIGHUP 信号将被触发。

对于没有控制终端的网络后台程序而言，它们通常利用 SIGHUP 信号来强制服务器重读配置文件。

比如 `xinetd` 超级服务程序，在接收到 SIGHUP 信号后将循环读取 `/etc/xinetd.d` 目录下每个配置文件，检测配置文件的变化，根据它们的内容来控制子服务程序。

## SIGPIPE

向读端关闭的管道或 socket 连接中写数据将引发 SIGPIPE 信号，此时 errno 也会为 EPIPE。

**代码需要显示的捕获或者忽略此信号，否则程序接收到 SIGPIPE 信号的默认行为便是结束进程。**

当 `send()` 函数使用 `MSG_NOSIGNAL` 标志来禁止写操作触发 SIGPIPE 信号时，应该使用 `send()` 返回的 errno 来判断管道或 socket 读端已经关闭。

也可以使用 I/O 复用函数来检测管道和 socket 连接的读端是否已经关闭，以 poll 为例：
- 当管道的读端关闭时，写端文件描述符上的 POLLHUP 事件将被触发
- 当 socket 连接被对方关闭时，socket 上的 POLLRDHUP 事件将被触发


## SIGURG
除了可以通过`select()`读取带外信号，还可以通过接收 SIGURG 信号来接收带外数据。

如下服务端代码：

``` c
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <string.h>
#include <assert.h>

#define BUF_SIZE (1024)

static int client_fd = 0;

// 获取到信号后，便读取内容
static void sig_urg(int sig) {
    int save_errno = errno;
    char buffer[BUF_SIZE];
    memset(buffer, 0, BUF_SIZE);
    int ret = recv(client_fd, buffer, BUF_SIZE - 1, MSG_OOB);
    printf("got %d bytes of oob data: %s\n", ret, buffer);

    errno = save_errno;
}

static void add_sig(int sig, void (*sig_handler)(int)) {
    struct sigaction sa;

    memset(&sa, 0, sizeof(sa));

    sa.sa_handler = sig_handler;
    sa.sa_flags |= SA_RESTART;
    sigfillset(&sa.sa_mask);
    int ret = sigaction(sig, &sa, NULL);
    assert(ret != -1);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("usage: %s <port>\n", argv[0]);

        return -1;
    }
    int port = atoi(argv[1]);

    //addr
    struct sockaddr_in socket_addr;

    memset(&socket_addr, 0, sizeof(socket_addr));
    socket_addr.sin_family = AF_INET;
    socket_addr.sin_port = htons(port);
    socket_addr.sin_addr.s_addr = htonl(INADDR_ANY);

    //socket
    int socket_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (socket_fd < 0) {
        perror("can't create socket:");

        return -1;
    }

    //bind
    if (bind(socket_fd, (const struct sockaddr *)&socket_addr, sizeof(socket_addr)) < 0) {
        perror("bind socket and address failed:");

        return -1;
    }
    //listen
    if (listen(socket_fd, 5) < 0) {
        perror("listen failed!\n");

        return -1;
    }
    printf("I'm waiting for client...\n");
    //accept
    struct sockaddr_in client_addr;
    socklen_t     addr_len = sizeof(client_addr);
    if ((client_fd = accept(socket_fd, (struct sockaddr *)&client_addr, &addr_len)) < 0) {
        perror("accept failed:");

        return -1;
    }

    printf("connected to client ip: %s, port: %d\n",
    inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));

    add_sig(SIGURG, sig_urg);
    //设置 socket 的宿主进程或进程组
    fcntl(client_fd, F_SETOWN, getpid());

    ssize_t recv_len;

    #define RECV_BUF_SIZE   (30)
    char recv_buf[RECV_BUF_SIZE];

    while (1) {
        memset(recv_buf, 0, RECV_BUF_SIZE);
        recv_len = recv(client_fd, recv_buf, RECV_BUF_SIZE - 1, 0);
        if (recv_len <= 0) {
            break;
        }
        printf("received %ld bytes : %s\n", recv_len, recv_buf);
    }
    close(client_fd);
    close(socket_fd);

    return 0;
}
```
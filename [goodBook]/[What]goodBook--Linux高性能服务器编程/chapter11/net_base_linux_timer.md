---
title: Linux 定时器
tags: 
- network
categories:
- network
- basic
date: 2022/6/13
updated: 2022/6/13
layout: true
comments: true
---

理解在用户空间中使用定时器。

Linux 提供了 3 种定时方法：
1. socket 选项 SO_RECVTIMEO 和 SO_SNDTIMEO
2. SIGALRM 信号
3. I/O 复用系统调用的超时参数

<!--more-->

# socket 选项 SO_RECVTIMEO 和 SO_SNDTIMEO

SO_RECVTIMEO 和 SO_SNDTIMEO 分别对应设置接收和发送超时。

| 系统调用 | 有效选项    | 系统调用超时后的行为                        |
|----------+-------------+---------------------------------------------|
| send     | SO_SNDTIMEO | 返回 -1，errno 的值为 EAGAIN 或 EWOULDBLOCK |
| sendmsg  | SO_SNDTIMEO | 返回 -1，errno 的值为 EAGAIN 或 EWOULDBLOCK |
| recv     | SO_RCVTIMEO | 返回 -1，errno 的值为 EAGAIN 或 EWOULDBLOCK |
| recvmsg  | SO_RCVTIMEO | 返回 -1，errno 的值为 EAGAIN 或 EWOULDBLOCK |
| accept   | SO_RCVTIMEO | 返回 -1，errno 的值为 EAGAIN 或 EWOULDBLOCK |
| connect  | SO_SNDTIMEO | 返回 -1，errno 的值为 EINPROGRESS           |
如下所示为 socket 使用`connect` 超时的设置：

``` c
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>

#include <stdlib.h>
#include <assert.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>

int main(int argc, char *argv[]) {
    int ret = 0;
    if (argc != 3) {
        printf("usage: %s <ip> <port>\n", argv[0]);

        return -1;
    }

    const char *ip = argv[1];
    int port = atoi(argv[2]);

    struct sockaddr_in address;

    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    inet_pton(AF_INET, ip, &address.sin_addr);
    address.sin_port = htons(port);

    int sock_fd = socket(address.sin_family, SOCK_STREAM, 0);
    assert(sock_fd > 0);

    struct timeval timeout;

    // 设置超时时间为 5 s
    timeout.tv_sec = 5;
    timeout.tv_usec = 0;
    socklen_t len = sizeof(timeout);

    ret = setsockopt(sock_fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, len);
    assert(ret == 0);

    ret = connect(sock_fd, (struct sockaddr *)&address, sizeof(address));
    if (ret == -1) {
        if (errno == EINPROGRESS) {
            printf("connecting timeout\n");
            return -1;
        }
        perror("connect failed:");

        return -1;
    }

    return 0;
}
```

# SIGALRM 信号

`SIGALRM`和`setitimer`使用，可以实现高效的定时机制。

比如下面这段代码就使用实时定时器实现每隔 10ms 输出一次字符串。

```c
#include <sys/msg.h>
#include <sys/ipc.h>
#include <sys/time.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>

static void(*pfunc)(void);

static void TimerSet(uint64_t microsecond) {
    struct itimerval its;

    its.it_value.tv_sec = microsecond / 1000000;
    its.it_value.tv_usec = microsecond % 1000000;
    its.it_interval.tv_sec = its.it_value.tv_sec;
    its.it_interval.tv_usec = its.it_value.tv_usec;

    if (setitimer(ITIMER_REAL, &its, NULL) == -1) {
        perror("setitimer failed: ");

        exit(1);
    }
}

static void TimerStart(uint64_t microsecond, void(*func)(void)) {
    pfunc = func;

    TimerSet(microsecond);
}

static void TimerStop(void) {
    printf("stop time!\n");
    TimerSet(0);
}

static int stop_cnt = 0;
static void TimerHandler(int sig) {

    printf("received sig: %d\n", sig);
    if (pfunc) {
        pfunc();
    }
}

static void UserFunc(void) {
    printf("Hello world!\n");
    if (++stop_cnt >= 4) {
        stop_cnt = 0;

        TimerStop();
    }
}

int main(int argc, char* argv[]) {
    if (signal(SIGALRM, TimerHandler) == SIG_ERR) {
        perror("can't bind signal:");

        exit(1);
    }

    TimerStart(500000, UserFunc);

    int cnt = 10;
    while (cnt--) {
        sleep(1);
    }

    return 0;
}
```

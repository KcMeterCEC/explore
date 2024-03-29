---
title: Linux I/O 复用
tags: 
- network
categories:
- network
- basic
date: 2022/6/11
updated: 2022/6/12
layout: true
comments: true
---

I/O 复用虽然能同时监听多个文件描述符， **但它本身是阻塞的** 。并且当多个文件描述符同时就绪时，如果不采取额外的措施，程序就只能按顺序依次处理其中的每个文件描述符，这使得服务器程序看起来像是串行工作的。要实现并发，只能使用多进程或多线程等编程手段。

<!--more-->

# select

监听文件描述符上的可读、可写和异常事件。

## API
``` c
/* According to POSIX.1-2001, POSIX.1-2008 */
#include <sys/select.h>

/* According to earlier standards */
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

struct timeval {
    long    tv_sec;         /* seconds */
    long    tv_usec;        /* microseconds */
};

/**
* @par nfds : 被监听文件描述符数值最大值加 1（因为文件描述符从 0 开始），这个参数用于向内核传递范围，提高 select 性能
* @par readfds,writefds,exceptfds : 指向可读、可写、异常事件对应的文件描述符集合
* @par timeout : 超时时间，当设置为 NULL 时，表示一直阻塞
* @ret 成功时返回就绪文件描述符总数，失败返回 -1 并设置 errno
*/
int select(int nfds, fd_set *readfds, fd_set *writefds,
         fd_set *exceptfds, struct timeval *timeout);
```

`fd_set` 是一个整型数组，每一位代表文件描述符，linux 提供了对应的宏来操作这些位：
``` c
//清除 set 上的某一位
void FD_CLR(int fd, fd_set *set);
//检查 set 上某一位是否被设置
int  FD_ISSET(int fd, fd_set *set);
//设置 set 上的某一位
void FD_SET(int fd, fd_set *set);
//清除 set 上的所有位
void FD_ZERO(fd_set *set);
```

## 就绪条件

在网络编程中，下列情况下 socket 可读：
- socket 对应的内核接收缓存区中的字节数大于或等于低水位标记 `SO_RCVLOWAT` 
- socket 通信的对方关闭连接，此时读操作返回 0
- 监听 socket 上有新的连接请求
- socket 上有未处理的错误，此时通过 `getsockopt()` 来读取和清除该错误

在网络编程中，下列情况下 socket 可写：
- socket 对应的内核发送缓冲区中可用字节数大于或等于低水位标记 `SO_SNDLOWAT` 
- socket 的写操作被关闭。对写操作被关闭的 socket 执行写操作将触发一个 `SIGPIPE` 信号
- socket 使用非阻塞 connect 连接成功或者失败后
- socket 上有未处理的错误，此时通过 `getsockopt()` 来读取和清除该错误
  
在网络编程中，select能处理的异常情况只有一种：socket 上接收到带外数据

## 处理带外数据

socket 上接收到普通数据和带外数据都将使 select 返回，但 socket 处于不同的就绪状态：前者处于可读状态，后者处于异常状态。

下面的代码是客户端发送普通和异常数据：

``` c
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <netdb.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("usage: %s <hostname> <port>\n", argv[0]);

        return -1;
    }

    int port = atoi(argv[2]);

    //addr
    struct sockaddr_in socket_addr;

    memset(&socket_addr, 0, sizeof(socket_addr));
    socket_addr.sin_family = AF_INET;
    socket_addr.sin_port = htons(port);

    struct hostent *host_info = gethostbyname(argv[1]);
    assert(host_info);

    printf("I have found the ip address of host %s is:\n", host_info->h_name);

    int i = 0;
    do {
        printf("%s: %s\n", host_info->h_addrtype == AF_INET ? "ipv4" : "ipv6",
        inet_ntoa(*(struct in_addr *)host_info->h_addr_list[i]));

        i++;
    } while (host_info->h_addr_list[i]);

    socket_addr.sin_addr.s_addr = *(uint32_t *)host_info->h_addr_list[0];

    //socket
    int socket_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (socket_fd < 0) {
        perror("can't create socket:");

        return -1;
    }

    //connect
    if (connect(socket_fd, (const struct sockaddr *)&socket_addr, sizeof(socket_addr)) < 0) {
        perror("connect to server failed!\n");

        return -1;
    }

    const char *oob_data = "abc";
    const char *normal_data = "123";

    send(socket_fd, normal_data, strlen(normal_data), 0);
    send(socket_fd, oob_data, strlen(oob_data), MSG_OOB);
    send(socket_fd, normal_data, strlen(normal_data), 0);


    close(socket_fd);

    return 0;
}        
```

下面代码是服务端通过 select 来接收普通和异常数据：
```c
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <assert.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <netdb.h>

int main(int argc, char *argv[]) {
    int ret = 0;
    if (argc != 2) {
        printf("usage: %s <port>\n", argv[0]);

        ret = -1;
        goto error1;
    }

    int port = atoi(argv[1]);

    struct sockaddr_in addr;

    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    int socket_fd = socket(addr.sin_family, SOCK_STREAM, 0);
    if (socket_fd <= 0) {
        perror("can't create socket!");
        ret = -1;
        goto error1;
    }
    if (bind(socket_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind socket failed!");
        ret = -1;
        goto error1;
    }

    if (listen(socket_fd, 5) < 0) {
        perror("listen socket failed!");
        ret = -1;
        goto error1;
    }

    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);

    int client_fd = accept(socket_fd, (struct sockaddr *)&client_addr, &addr_len);
    if (client_fd < 0) {
        perror("accept failed!");

        ret = -1;
        goto error2;
    }
    printf("client: ip -> %s, port -> %d\n", inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));

    char buf[1024];

    fd_set read_fds;
    fd_set exception_fds;
    FD_ZERO(&read_fds);
    FD_ZERO(&exception_fds);

    while (1) {
        memset(buf, 0, sizeof(buf));

        FD_SET(client_fd, &read_fds);
        FD_SET(client_fd, &exception_fds);

        if (select(client_fd + 1, &read_fds, NULL, &exception_fds, NULL) < 0) {
            perror("select failed:");
            ret = -1;
            goto error3;
        }

        int ret = 0;


        if (FD_ISSET(client_fd, &read_fds)) {
            if (( ret = recv(client_fd, buf, sizeof(buf) - 1, 0)) < 0) {
                perror("recv failed:");

                ret = -1;
                goto error3;
            } else if (ret == 0) {
                printf("socket has been closed.\n");
                goto error2;
            } else {
                printf("I have got normal data: %s\n", buf);
            }
        }

        memset(buf, 0, sizeof(buf));
        if (FD_ISSET(client_fd, &exception_fds)) {
            if ((ret = recv(client_fd, buf, sizeof(buf) - 1, MSG_OOB)) < 0) {
                perror("read oob data failed:");

                ret = -1;
                goto error3;
            } else if (ret == 0) {
                printf("socket has been closed.\n");
                goto error2;
            } else {
                printf("I have got oob data: %s\n", buf);
            }
        }
    }
error3:
    close(client_fd);
error2:
    close(socket_fd);
error1:
    return ret;
}
```
接下来运行：
```shell
# WSL 运行服务端
$ ./server 54321
#在 WSL 上运行客户端
$ ./client localhost 54321
I have found the ip address of host localhost is:
ipv4: 127.0.0.1

#最终服务端接收
client: ip -> 127.0.0.1, port -> 50294
I have got normal data: 123ab
I have got oob data: c
I have got normal data: 123
socket has been closed.
```

从服务端代码可以看出，每次接收到数据后，`select()`都需要重新设置一次，它就像是有健忘症一样……

# poll

poll 与 select 在使用上类似。
``` c
#include <poll.h>

struct pollfd {
    int   fd;         /* file descriptor */
    short events;     /* requested events */
    short revents;    /* returned events */
};
int poll(struct pollfd *fds, nfds_t nfds, int timeout);
```
event 类型有：

| 事件       | 描述                                 |
|------------|--------------------------------------|
| POLLIN     | 数据（包括普通数据和优先数据）可读   |
| POLLRDNORM | 普通数据可读                         |
| POLLRDBAND | 优先级带数据可读                     |
| POLLPRI    | 高优先级数据可读，比如 TCP 带外数据  |
| POLLOUT    | 数据（包括普通数据和优先数据）可写   |
| POLLWRNORM | 普通数据可写                         |
| POLLWRBAND | 优先级带数据可写                     |
| POLLRDHUP  | TCP 连接被对方关闭或对方关闭了写操作 |
| POLLERR    | 错误                                 |
| POLLHUP    | 挂起                                 |
| POLLNVAL   | 文件描述符没有打开                   |

虽然 poll 和 select 类似，但是当有事件发生时，内核修改的是 pollfd 的 `revents`成员变量，而不会修改原来的`events`成员变量。

所以其下次再来调用时，可以不用再次修改 pollfd，编程接口相对更为友好。

# epoll

epoll 则与 select、poll 有以下差异：
- epoll 使用一组函数来完成任务
- epoll 把用户关心的文件描述符上的事件放在内核里的一个事件表中，而无须像 select 和 poll 每次调用都需要重复传入参数

> 既然不需要重复传入参数，那 epoll 的操作效率是比 select 和 poll 的效率高的

## 内核事件表

epoll 需要使用一个额外的文件描述符来唯一标识内核中的事件表：

``` c
#include <sys/epoll.h>

//size 提示内核事件表需要多大
int epoll_create(int size);
```

该函数返回的文件描述符将用作其他所有 epoll 系统调用的第一个参数，以指定要访问的内核事件表。

操作内核事件表，使用下面这个函数：

``` c
#include <sys/epoll.h>

typedef union epoll_data {
    void        *ptr;
    int          fd;
    uint32_t     u32;
    uint64_t     u64;
} epoll_data_t;

struct epoll_event {
    uint32_t     events;      /* Epoll events */
    epoll_data_t data;        /* User data variable */
};

int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event);
```

op 参数指定对 fd 的操作类型：
- EPOLL_CTL_ADD：往事件表中注册 fd 上的事件
- EPOLL_CTL_MOD：修改 fd 上的注册事件  
- EPOLL_CTL_DEL：删除 fd 上的注册事件

event 结构中的 `events` 成员描述事件类型，与 `poll` 事件类型基本相同，只是宏名称前需要加 'E' 。

除此之外，epoll 还有两个额外的事件类型 `EPOLLET` 和 `EPOLLONESHOT`。

## epoll_wait

epoll_wait 函数在一段超时时间内等待一组文件描述符上的事件：
``` c
#include <sys/epoll.h>

int epoll_wait(int epfd, struct epoll_event *events,
             int maxevents, int timeout);
```

当 epoll_wait 检测到事件，就将所有就绪事件从内核事件表中复制到参数 `events` 指向的数组中。
也就是说，`events` 指向的数组中全部都是就绪事件，而不需要像 `select` 和 `poll` 再来二次判断了。

它们的差异如下：

``` c
//poll 查询谁就绪了
int ret = poll(fds, MAX_EVENT_NUMBER, -1);
for (int i = 0; i < MAX_EVENT_NUMBER; ++i) {
if (fds[i].revents & POLLIN) {
	int sockfd = fds[i].fd;
	//...
  }
}

//epoll 返回后直接处理
int ret = epoll_wait(epollfd, events, MAX_EVENT_NUMBER, -1);
for (int i = 0; i < ret; ++i) {
int sockfd = events[i].data.fd;
//...
}
```

## LT 和 ET 模式
epoll 对文件描述符操作有两种模式：
- LT（Level Trigger, 电平触发）：默认此工作模式，相当于效率比较高的 poll
  + 事件发生时，如果应用程序不处理，这些事件会被保持
- ET（Edge Trigger，边沿触发）：此模式是 epoll 的高效工作模式
  + 事件发生时，应用程序应立即处理，否则下次调用 `epoll_wait` 后此事件将被清空

以上模式和中断的电平触发和边沿触发的概念类似。

**需要注意的是：** 当使用 ET 模式时，对应的文件描述符需要设置为非阻塞的方式。
因为 ET 模式下，当事件触发后，需要一次性读出所有数据。所以需要非阻塞的返回来判断是否已经读空了。

下面是服务端以两种模式工作的代码：

``` c
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
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

#define USE_LT  0

#define MAX_EVENT_NUMBER (1024)
#define BUFFER_SIZE      (10)

// 将文件描述符设置为非阻塞模式
static void setnonblocking(int fd) {
    int old_opt = fcntl(fd, F_GETFL);
    int new_opt = old_opt | O_NONBLOCK;
    fcntl(fd, F_SETFL, new_opt);
}

// 增加 fd 的读事件到 epoll
static void addfd(int epollfd, int fd, bool enable_et) {
    struct epoll_event event;

    event.data.fd = fd;
    event.events = EPOLLIN;
    if (enable_et) {
        event.events |= EPOLLET;
    }

    epoll_ctl(epollfd, EPOLL_CTL_ADD, fd, &event);

    setnonblocking(fd);
}

#if USE_LT
void lt(struct epoll_event *events, int number, int epollfd, int listenfd) {
    char buf[BUFFER_SIZE];

    for (int i = 0; i < number; ++i) {
        int sockfd = events[i].data.fd;

        // 当服务器检查到客户端连接，就将其加入 epoll，模式为电平触发
        if (sockfd == listenfd) {
            struct sockaddr_in client_addr;
            socklen_t addr_len = sizeof(client_addr);
            int connfd = accept(listenfd, (struct sockaddr *)&client_addr, &addr_len);

            printf("client: %s -> %d\n", inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));

            addfd(epollfd, connfd, false);
        } else if(events[i].events & EPOLLIN) {

            // 由于是电平触发方式，只要该 socket 中还有数据，则该事件还会被触发
            printf("event trigger once!\n");
            memset(buf, 0, BUFFER_SIZE);
            int ret = recv(sockfd, buf, BUFFER_SIZE - 1, 0);
            if (ret <= 0) {
                close(sockfd);
                continue;
            }
            printf("got %d bytes, the contents are: %s\n", ret, buf);
        } else {
            printf("something is wrong.\n");
        }
    }
}
#else
void et(struct epoll_event *events, int number, int epollfd, int listenfd) {
    char buf[BUFFER_SIZE];
    for (int i = 0; i < number; ++i) {
        int sockfd = events[i].data.fd;
        if (sockfd == listenfd) {
            struct sockaddr_in client_addr;
            socklen_t addr_len = sizeof(client_addr);
            int connfd = accept(listenfd, (struct sockaddr *)&client_addr, &addr_len);

            printf("client: %s -> %d\n", inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));

            addfd(epollfd, connfd, true);
        } else if (events[i].events & EPOLLIN) {
            // 由于是边沿触发模式，所以需要一次性将当前缓存的内容都读出来
            printf("event trigger once!\n");
            while(1) {
                memset(buf, 0, BUFFER_SIZE);
                int ret = recv(sockfd, buf, BUFFER_SIZE - 1, 0);
                if (ret < 0) {
                    // 以下两个标记都表示数据已经读取完毕了
                    if ((errno == EAGAIN) || (errno == EWOULDBLOCK)) {
                      printf("read later\n");
                      break;
                    }
                    close(sockfd);
                    break;
                } else if (ret == 0) {
                    close(sockfd);
                } else {
                    printf("got %d bytes, the contents are: %s\n", ret, buf);
                }
            }
        } else {
            printf("something is wrong.\n");
        }
    }
}
#endif
int main(int argc, char *argv[]) {
    int ret = 0;
    if (argc != 2) {
        printf("usage: %s <port>\n", argv[0]);

        ret = -1;
        goto error;
    }

    int port = atoi(argv[1]);

    struct sockaddr_in server_addr;

    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    server_addr.sin_port = htons(port);

    int server_fd = socket(server_addr.sin_family, SOCK_STREAM, 0);
    assert(server_fd > 0);

    ret = bind(server_fd, (struct sockaddr *)&server_addr, sizeof(server_addr));
    assert(ret >= 0);

    ret = listen(server_fd, 5);
    assert(ret >= 0);

    struct epoll_event events[MAX_EVENT_NUMBER];

    int epoll_fd = epoll_create(MAX_EVENT_NUMBER);
    assert(epoll_fd >= 0);
#if USE_LT
    addfd(epoll_fd, server_fd, false);
#else
    addfd(epoll_fd, server_fd, true);
#endif

    while (1) {
        int ret = epoll_wait(epoll_fd, events, MAX_EVENT_NUMBER, -1);
        if (ret < 0) {
            ret = -1;
            perror("epoll failed:");
            goto error1;
        }
#if USE_LT
        lt(events, ret, epoll_fd, server_fd);
#else
        et(events, ret, epoll_fd, server_fd);
#endif
    }
error1:
    close(server_fd);
error:
    return ret;
}
```

使用 telnet 作为客户端测试，发送大于 10 字节的数据，可以看出：
- 在电平触发模式下，如果数据没有读完，电平触发会一直保持，所以服务端可以每次触发发生时只读一次
- 在边沿触发模式下，触发只会出现一次，所以服务端在触发发生后，需要确保一次性读完 socket 中的内容才行，这样子也是效率最高的做法。
- 在有 epoll 做 I/O 扫描的情况下，文件描述符需要设置为非阻塞模式，这样可以避免读取的数据大于缓存存储时，阻塞了程序流程

## EPOLLONESHOT 事件

在 ET 模式下，如果一个线程在读取完某个 socket 上的数据后开始处理，而在处理过程中此 socket 上又有新数据可读，但此时由另外一个线程来读取这些新数据。

这就出现了两个线程同时操作同一个 socket 的问题，为了一个 socket 在连接任一时刻都只被一个线程处理，可以使用 EPOLLONESHOT 事件实现。

`EPOLLONESHOT` 使得操作系统最多触发一次其上注册的一个可读、可写或异常事件。

这样就可以将一个 socket 与一个单独的线程绑定， **当线程处理完此事件后，需要重置其 `EPOLLONESHOT` 事件。**

> 这样才能确保 socket 可以再次发出事件并被其他的线程处理。
  
下面是使用例子：
``` c
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <sys/epoll.h>
#include <fcntl.h>
#include <pthread.h>

#include <assert.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

#define MAX_EVENT_NUMBER    (5)
#define BUFFER_SIZE         (10)

struct fds {
    int epollfd;
    int sockfd;
};

void setnonblocking(int fd) {
    int old_opt = fcntl(fd, F_GETFL);
    int new_opt = old_opt | O_NONBLOCK;

    fcntl(fd, F_SETFL, new_opt);
}

void addfd(int epollfd, int fd, bool oneshot) {
    struct epoll_event event;

    event.data.fd = fd;
    event.events = EPOLLIN | EPOLLET;
    if (oneshot) {
        event.events |= EPOLLONESHOT;
    }

    epoll_ctl(epollfd, EPOLL_CTL_ADD, fd, &event);

    setnonblocking(fd);
}

void reset_oneshot(int epollfd, int fd) {
    printf("%s\n", __func__);

    struct epoll_event event;

    event.data.fd = fd;
    event.events = EPOLLIN | EPOLLET | EPOLLONESHOT;
    epoll_ctl(epollfd, EPOLL_CTL_MOD, fd, &event);
}

void *worker(void *arg) {
    int sockfd = ((struct fds *)arg)->sockfd;
    int epollfd = ((struct fds *)arg)->epollfd;

    char buf[BUFFER_SIZE];
    memset(buf, 0, BUFFER_SIZE);

    while(1) {
        int ret = recv(sockfd, buf, BUFFER_SIZE - 1, 0);
        if (ret == 0) {
            close(sockfd);
            printf("client closed the connection!\n");
            break;
        } else if(ret < 0) {
            // 当数据读完后，需要重新设置 ONESHOT 标记
            if (errno == EAGAIN) {
                reset_oneshot(epollfd, sockfd);
                printf("read laster\n");
                break;
            }
        } else {
            buf[ret] = '\0';
            printf("thread: %lu, get contents: %s\n", pthread_self(), buf);
            sleep(5);
        }
    }
    printf("thread: %lu done.\n", pthread_self());

    return (void *)0;
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
    server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    server_addr.sin_port = htons(port);

    int server_fd = socket(server_addr.sin_family, SOCK_STREAM, 0);
    assert(server_fd > 0);

    ret = bind(server_fd, (struct sockaddr *)&server_addr, sizeof(server_addr));
    assert(ret == 0);

    ret = listen(server_fd, MAX_EVENT_NUMBER);
    assert(ret == 0);

    struct epoll_event events[MAX_EVENT_NUMBER];

    int epoll_fd = epoll_create(MAX_EVENT_NUMBER);
    assert(epoll_fd >= 0);

    addfd(epoll_fd, server_fd, false);

    while (1) {
        ret = epoll_wait(epoll_fd, events, MAX_EVENT_NUMBER, -1);
        if (ret < 0) {
            perror("epoll failed:");
            break;
        }

        for (int i = 0; i < ret; ++i) {
            int sockfd = events[i].data.fd;

            if (sockfd == server_fd) {
                struct sockaddr_in client_addr;
                socklen_t addr_len = sizeof(client_addr);
                int connfd = accept(server_fd, (struct sockaddr *)&client_addr, &addr_len);

                printf("client: %s -> %d\n", inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));

                addfd(epoll_fd, connfd, true);
            } else if(events[i].events & EPOLLIN) {
                pthread_t thread;

                struct fds new_fds;

                new_fds.epollfd = epoll_fd;
                new_fds.sockfd = sockfd;

                pthread_create(&thread, NULL, worker, (void *)&new_fds);
            } else {
                printf("something is wrong\n");
            }
        }
    }

    close(server_fd);

    return ret;
}
```

上面代码的 `sleep()` 是为了模拟该线程正在对此事件进行处理，可以通过多个 `telnet` 客户端来给服务端发送数据。

可以看到：每个 `telent` 都有对应的唯一一个处理线程，在处理时间内发送新数据，原来的线程会继续处理。

# 三组 I/O 复用函数的比较

| 系统调用             | select  | poll  | epoll |
|------------|--------------------------|-------|-------------|
| 事件集合                               | 用户通过 3 个参数分别传入可读、可写及异常等事件，内核通过对这些参数的在线修改来反馈就绪事件。导致用户每次调用都要重置这 3 个参数 | 统一处理所有事件类型，因此只需一个事件集参数。用户通过 events 传入事件，内核通过修改 revents 反馈就绪事件 | 内核通过事件表管理事件。所以每次调用 epoll_wait 时不用反复传入用户感兴趣的事件。 epoll_wait 参数 events 仅用来反馈就绪事件 |
| 应用程序索引就绪文件描述符的事件复杂度 | O(n)                                                                                                                             | O(n)                                                                                                      | O(1)                                                                                                                       |
| 最大支持文件描述符数                   | 一般有最大值限制                                                                                                                 | 65535                                                                                                     | 65535                                                                                                                      |
| 工作模式                               | LT                                                                                                                               | LT                                                                                                        | LT，ET                                                                                                                     |
| 内核实现和工作效率                     | 采用轮询方式来检测就绪事件，事件复杂度为 O(n)                                                                                    | 采用轮询方式检测就绪事件，事件复杂度为 O(n)                                                               | 采用回调方式检测就绪事件，算法事件复杂度为 O(1)                                                                            |

# 非阻塞 connect

一个客户端为了能够同时发起多个连接，可以以非阻塞的方式调用 `connect()` ：
- 将 socket 设置为非阻塞状态，然后调用 `connect()` 
- 使用 `select()` , `poll()` 等来监听这些  socket  上的可写事件
- 当 `select()` , `poll()` 返回时，调用 `getsockopt()` 来读取错误码判断连接是否成功（选项为 SO_ERROR，层级为 SOL_SOCKET）
  + 当错误码为 0 时代表连接成功
    
**目前这种方式并不适用于所有系统**

如下示例代码，使用 poll 来并发检查 connect 状态：

``` c
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <netdb.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <poll.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>
#include <errno.h>

#define CONNECT_NUM (5)

int set_nonblocking(int fd) {
    int old_opt = fcntl(fd, F_GETFL);
    int new_opt = old_opt | O_NONBLOCK;

    fcntl(fd, F_SETFL, new_opt);

    return old_opt;
}

int main(int argc, char *argv[]) {
    int ret = 0;
    if (argc != 3) {
        printf("usage: %s <hostname> <port>\n", argv[0]);

        return -1;
    }
    int port = atoi(argv[2]);

    //addr
    struct sockaddr_in socket_addr;

    memset(&socket_addr, 0, sizeof(socket_addr));
    socket_addr.sin_family = AF_INET;
    socket_addr.sin_port = htons(port);

    struct hostent *host_info = gethostbyname(argv[1]);
    assert(host_info);

    printf("I have found the ip address of host %s is:\n", host_info->h_name);

    int i = 0;
    do {
        printf("%s: %s\n", host_info->h_addrtype == AF_INET ? "ipv4" : "ipv6",
        inet_ntoa(*(struct in_addr *)host_info->h_addr_list[i]));

        i++;
    } while (host_info->h_addr_list[i]);

    socket_addr.sin_addr.s_addr = *(uint32_t *)host_info->h_addr_list[0];

    int socket_fd[CONNECT_NUM];
    struct pollfd fdset[CONNECT_NUM];
    int socket_opt;
    int error = 0;
    socklen_t length = sizeof(error);

    for (int i = 0; i < CONNECT_NUM; i++) {
        socket_fd[i] = socket(AF_INET, SOCK_STREAM, 0);
        socket_opt = set_nonblocking(socket_fd[i]);

        ret = connect(socket_fd[i], (const struct sockaddr *)&socket_addr, sizeof(socket_addr));
        if (ret == 0) {
            printf("connect with server immediately!\n");
            //如果已经连接成功，则恢复默认设置
            fcntl(socket_fd[i], F_SETFL, socket_opt);
        } else if((ret != EINPROGRESS) && (errno != EINPROGRESS)) {
            perror("connect failed!\n");
            close(socket_fd[i]);
            ret = -1;
            goto error;
        }
    }

    sleep(1);

    for (int i = 0; i < CONNECT_NUM; i++) {
        fdset[i].fd = socket_fd[i];
        fdset[i].events = POLLOUT;
    }

    // 使用 poll 检测是否有写事件
    if (poll(fdset, CONNECT_NUM, -1) < 0) {
        perror("poll failed:");
        ret = -1;
        goto error1;
    }

    for (int i = 0; i < CONNECT_NUM; i++) {
        if (fdset[i].revents & POLLOUT) {
            if (getsockopt(fdset[i].fd, SOL_SOCKET, SO_ERROR, &error, &length) < 0) {
                perror("gesockopt failed:");
                close(fdset[i].fd);
                ret = -1;
                goto error;
            }
            if (error != 0) {
                printf("connection failed: %d\n", error);
                close(fdset[i].fd);
                ret = -1;
                goto error;
            }

            // 如果发生了写事件，并且返回为 0，则代表已经连接成功
            // 然后需要将文件属性恢复到以前的默认值

            printf("socket %d connection succedded!\n", i);

            fcntl(fdset[i].fd, F_SETFL, socket_opt);
        }
    }

    sleep(3);
error1:
    for (int i = 0; i < CONNECT_NUM; i++) {
        close(socket_fd[i]);
    }
error:
    return ret;
}
```

# 聊天室

使用 I/O 复用实现服务器同时处理网络连接和用户输入。

## 客户端

客户端实现两个功能：
1. 从标准输入读入用户数据，并发送至服务器
2. 接收服务器的数据并打印至终端

对于客户端来说，有用户输入和 socket 输入，并有 socket 输出和终端输出，所以可以用 I/O 复用函数来监听两个输入，然后对应输出。

``` c
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <netdb.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <poll.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>
#include <errno.h>

#define RECV_BUF_SIZE   (250)

int main(int argc, char *argv[]) {
    int ret = 0;
    if (argc != 3) {
        printf("usage: %s <hostname> <port>\n", argv[0]);

        return -1;
    }
    int port = atoi(argv[2]);

    //addr
    struct sockaddr_in socket_addr;

    memset(&socket_addr, 0, sizeof(socket_addr));
    socket_addr.sin_family = AF_INET;
    socket_addr.sin_port = htons(port);

    struct hostent *host_info = gethostbyname(argv[1]);
    assert(host_info);

    printf("I have found the ip address of host %s is:\n", host_info->h_name);

    int i = 0;
    do {
        printf("%s: %s\n", host_info->h_addrtype == AF_INET ? "ipv4" : "ipv6",
        inet_ntoa(*(struct in_addr *)host_info->h_addr_list[i]));

        i++;
    } while (host_info->h_addr_list[i]);

    socket_addr.sin_addr.s_addr = *(uint32_t *)host_info->h_addr_list[0];

    int socket_fd = socket(socket_addr.sin_family, SOCK_STREAM, 0);
    assert(socket_fd > 0);

    ret = connect(socket_fd, (const struct sockaddr *)&socket_addr, sizeof(socket_addr));
    assert(ret == 0);

    struct pollfd poll_fd[2];
    char recv_buf[RECV_BUF_SIZE];

    while (1) {
        // 检查 socket 和标准输入是否有输入事件
        poll_fd[0].fd = socket_fd;
        poll_fd[0].events = POLLIN;

        poll_fd[1].fd = STDIN_FILENO;
        poll_fd[1].events = POLLIN;

        poll(poll_fd, 2, -1);

        if (poll_fd[0].revents & POLLIN) {
            memset(recv_buf, 0, RECV_BUF_SIZE);
            // 如果是 socket 有输入，则发出到标准输出
            recv(socket_fd, recv_buf, RECV_BUF_SIZE, MSG_DONTWAIT);
            printf("%s", recv_buf);
        } else if(poll_fd[1].revents & POLLIN) {
            // 如果是标准输入有输入，则发送给服务端
            char *buf = fgets(recv_buf, RECV_BUF_SIZE, stdin);
            if (buf) {
                send(socket_fd, recv_buf, strlen(recv_buf), 0);
            }
        } else {
            perror("something is wrong:");
            break;
        }
    }

    close(socket_fd);

    return ret;
}
```

## 服务端

服务端主要功能是接收数据，并将数据发送给每个登录到该服务器上的除数据发送者的客户端，可以使用 I/O 复用函数来监听连接和数据。

``` c
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/sendfile.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <poll.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>

#define MAXIMUM_CLIENT_NUM  (5)
#define MAXIMUM_RECV_BUF    (250)

static int client_cnt = -1;
static int client_fds[MAXIMUM_CLIENT_NUM];
static char buf[MAXIMUM_RECV_BUF];
static struct pollfd poll_fd[MAXIMUM_CLIENT_NUM + 1];

static bool client_add(int fd) {
    bool ret = true;
    if (client_cnt < MAXIMUM_CLIENT_NUM - 1) {
        client_fds[++client_cnt] = fd;
    } else {
        ret = false;
    }

    return ret;
}

static bool client_del(int fd) {
    bool ret = true;
    if (client_cnt >= 0) {
        for (int i = 0; i < client_cnt + 1; ++i) {
            if (client_fds[i] == fd) {
                client_fds[i] = client_fds[client_cnt];
                client_fds[client_cnt] = -1;
                client_cnt -= 1;
                break;
            }
        }
        ret = false;
    } else {
        ret = false;
    }

    return ret;
}

int main(int argc, char *argv[]) {
    int ret = 0;
    if(argc != 2) {
        printf("usage: %s <port>\n", argv[0]);

        return -1;
}
    int port = atoi(argv[1]);

    for (int i = 0; i < MAXIMUM_CLIENT_NUM; ++i) {
        client_fds[i] = -1;
    }

    //addr
    struct sockaddr_in socket_addr;

    memset(&socket_addr, 0, sizeof(socket_addr));
    socket_addr.sin_family = AF_INET;
    socket_addr.sin_port = htons(port);
    socket_addr.sin_addr.s_addr = htonl(INADDR_ANY);

    //socket
    int socket_fd = socket(AF_INET, SOCK_STREAM, 0);
    assert(socket_fd > 0);

    //bind
    ret = bind(socket_fd, (const struct sockaddr *)&socket_addr, sizeof(socket_addr));
    assert(ret == 0);

    //listen
    if (listen(socket_fd, 5) < 0) {
        perror("listen failed!\n");

        return -1;
    }

    printf("I'm waiting for client.\n");

    while (1) {
        poll_fd[0].fd = socket_fd;
        poll_fd[0].events = POLLIN;
        for (int i = 1; i < client_cnt + 2; i++) {
            poll_fd[i].fd = client_fds[i - 1];
            poll_fd[i].events = POLLIN;
        }

        poll(poll_fd, client_cnt + 2, -1);

        for (int i = 0; i < client_cnt + 2; i++) {
            if (poll_fd[i].revents & POLLIN) {
                if (poll_fd[i].fd == socket_fd) {
                    //accept
                    int client_fd = 0;

                    struct sockaddr_in client_addr;
                    socklen_t     addr_len = sizeof(client_addr);
                    if ((client_fd = accept(socket_fd, (struct sockaddr *)&client_addr, &addr_len)) < 0) {
                        perror("accept failed!\n");

                        return -1;
                    }
                    printf("client: %s -> %d\n", inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));

                    if (client_add(client_fd) == false) {
                        printf("client fd buffer is full!\n");
                        close(client_fd);
                    }
                } else {
                    int recv_size = recv(poll_fd[i].fd, buf, MAXIMUM_RECV_BUF, 0);
                    if (recv_size == 0) {
                        printf("close one client!\n");
                        client_del(poll_fd[i].fd);
                        close(poll_fd[i].fd);
                    } else {
                        for (int j = 1; j < client_cnt + 2; j++) {
                            if (poll_fd[i].fd != client_fds[j - 1]) {
                                send(client_fds[j - 1], buf, recv_size, 0);
                            }
                        }
                    }
                }
            }

        }
   }
    close(socket_fd);
    return 0;
}
```

# 同时处理 TCP 和 UDP 服务

由于一个 socket 只能绑定一个地址（IP 地址和端口号），对于同一个服务器来说如果要同时监听多个端口（提供不同的服务类型），那么就必须创建多个 socket 对应绑定不同的端口号，然后使用 I/O 复用技术监听这多个端口号。

即使是同一个端口，如果服务器要同时处理该端口上的 TCP 和 UDP 请求，也需要创建两个不同的 socket。一个用于流式，一个用于数据报式，并且将它们绑定到同一个端口上。

如下示例则是服务器同时处理同一端口上的 TCP 和 UDP 请求：

``` c
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/epoll.h>

#include <assert.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

#define MAX_EVENT_NUMBER (1024)
#define TCP_BUFFER_SIZE  (512)
#define UDP_BUFFER_SIZE  (1024)

static int setnonblocking(int fd) {
    int old_opt = fcntl(fd, F_GETFL);
    int new_opt = old_opt | O_NONBLOCK;
    fcntl(fd, F_SETFL, new_opt);

    return old_opt;
}

static void addfd(int epollfd, int fd) {
    struct epoll_event event;

    event.data.fd = fd;
    event.events = EPOLLIN | EPOLLET;
    epoll_ctl(epollfd, EPOLL_CTL_ADD, fd, &event);

    setnonblocking(fd);
}

int main(int argc, char*argv[]) {
    if (argc != 2) {
        printf("usage: %s <port>\n", argv[0]);

        return -1;
    }

    int ret = 0;

    int port = atoi(argv[1]);

    struct sockaddr_in addr;

    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    int socket_tcp = socket(addr.sin_family, SOCK_STREAM, 0);
    assert(socket_tcp > 0);

    ret = bind(socket_tcp, (struct sockaddr *)&addr, sizeof(addr));
    assert(ret == 0);

    ret = listen(socket_tcp, 5);
    assert(ret == 0);

    int socket_udp = socket(addr.sin_family, SOCK_DGRAM, 0);
    assert(socket_udp > 0);

    ret = bind(socket_udp, (struct sockaddr *)&addr, sizeof(addr));
    assert(ret == 0);

    struct epoll_event events[MAX_EVENT_NUMBER];
    int epollfd = epoll_create(5);
    assert(epollfd > 0);

    addfd(epollfd, socket_tcp);
    addfd(epollfd, socket_udp);

    while (1) {
        int number = epoll_wait(epollfd, events, MAX_EVENT_NUMBER, -1);
        if (number < 0) {
            perror("epoll wait failed:");
            break;
        }

        for (int i = 0; i < number; i++) {
            int sockfd = events[i].data.fd;
            if (sockfd == socket_tcp) {
                struct sockaddr_in client_addr;
                socklen_t addr_len = sizeof(client_addr);
                int client_fd = accept(socket_tcp, (struct sockaddr *)&client_addr, &addr_len);
                assert(client_fd > 0);

                printf("tcp client: %s -> %d\n", inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));

                addfd(epollfd, client_fd);
            } else if(sockfd == socket_udp) {
                char buf[UDP_BUFFER_SIZE];

                memset(buf, 0, UDP_BUFFER_SIZE);
                struct sockaddr_in client_addr;
                socklen_t addr_len = sizeof(client_addr);

                ret = recvfrom(socket_udp, buf, UDP_BUFFER_SIZE - 1, 0,
                (struct sockaddr *)&client_addr, &addr_len);

                printf("udp client: %s -> %d\n", inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));
                // UDP 发送什么，就回传什么
                if (ret > 0) {
                    sendto(socket_udp, buf, ret, 0, (struct sockaddr *)&client_addr, addr_len);
                }

            } else if(events[i].events & EPOLLIN) {
                char buf[TCP_BUFFER_SIZE];
                while (1) {
                    memset(buf, 0, UDP_BUFFER_SIZE);
                    ret = recv(sockfd, buf, TCP_BUFFER_SIZE - 1, 0);

                    if (ret < 0) {
                        if (errno == EAGAIN || errno == EWOULDBLOCK) {
                            break;
                        }
                        close(sockfd);
                        break;
                    } else if(ret == 0) {
                        close(sockfd);
                    } else {
                        // 回传
                        send(sockfd, buf, ret, 0);
                    }
                }
            } else {
                printf("something is wrong\n");
            }
        }
    }

    close(socket_tcp);

    return 0;
}
```

客户端使用 `telnet` 测试 TCP 连接， `nc` 测试 UDP 连接。


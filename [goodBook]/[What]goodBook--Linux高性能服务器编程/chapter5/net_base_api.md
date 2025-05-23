---
title: Linux 网络编程基础 API
tags: 
- network
categories:
- network
- basic
date: 2022/6/7
updated: 2022/6/9
layout: true
comments: true
---

熟悉网络编程基础 API，理解与 TCP/IP 协议栈的关系。

<!--more-->

# socket 地址

## 主机字节序和网络字节序

根据数据存储顺序分为大端字节序（ big endian）和小端字节序（little endian），下面代码可以判断字节序。

```c
#include <stdio.h>

int main(int argc, char *argv[]) {
  int num = 0x12345678;
  char *byte = (char *)&num;

  if (*byte == 0x78) {
      printf("It's little endian\n");
  } else {
      printf("It's big endian\n");
  }

  return 0;
}
```

为了计算机通信数据正确，那必然要约定一致的字节序：

- 主机字节序：目前大多 CPU 使用小端字节序，所以又被称为主机字节序
- 网络字节序：网络通信规定为大端字节序，也就是说发送和接收方都需要以大端字节序发送和接收

**注意：** 即使同一台机器上运行的由不同语言编写的进程，也有可能是不同字节序，所以需要有良好的编程习惯。

- JAVA 虚拟机统一采用大端字节序

> 当然，如果通信双方以字符串的方式来交互，那在传输数据的过程中，也不需要注意大小端问题。

Linux 提供了如下函数完成主机字节序和网络字节序的转换：

```c
#include <arpa/inet.h>

uint32_t htonl(uint32_t hostlong);

uint16_t htons(uint16_t hostshort);

uint32_t ntohl(uint32_t netlong);

uint16_t ntohs(uint16_t netshort);
```

使用以上函数的场景有：

1. 设置 IP 地址时，使用 32 位转换
2. 设置端口号时，使用 16 位转换
3. 发送格式化数据时，使用对应转换

## 通用 socket 地址

`sockaddr` 表示 socket 地址：

```c
#include <bits/socket.h>

typedef unsigned short int sa_family_t;

struct sockaddr {
    sa_family_t sa_family;
    char        sa_data[14];
}
```

`sa_family` 表示地址族，这个与协议族有对应关系：

| 协议族      | 地址族      | 描述           | sa_data 含义                        |
| -------- | -------- | ------------ | --------------------------------- |
| PF_UNIX  | AF_UNIX  | UNIX 本地域协议族  | 文件路径名，最长 108 字节                   |
| PF_INET  | AF_INET  | TCP/IPv4 协议族 | 16 位端口号和 32 位地址                   |
| PF_INET6 | AF_INET6 | TCP/IPV6 协议族 | 16 位端口号，32 位流标识，128 位地址，32 位范围 ID |

```c
/* Protocol families.  */
#define PF_LOCAL    1    /* Local to host (pipes and file-domain).  */
#define PF_UNIX        PF_LOCAL /* POSIX name for PF_LOCAL.  */
#define PF_INET        2    /* IP protocol family.  */
#define PF_INET6    10    /* IP version 6.  */

/* Address families.  */
#define AF_UNIX        PF_UNIX
#define AF_INET        PF_INET
#define AF_INET6    PF_INET6
```

从上面定义可以看出它们的值是一样的，只是为了更好编码规范，需要根据当前对象使用对应的宏。

仅仅用 `sockaddr` 中的 `sa_data` 并不能完全容纳多种协议族的地址值，Linux 为此定义了 `sockaddr_storage` ：

```c
/* Structure large enough to hold any socket address (with the historical exception of AF_UNIX).  */
#define __ss_aligntype    unsigned long int
//这里就等于 128 - sizeof(unsigned shrot int) - sizeof(unsigned long int)
#define _SS_PADSIZE                                             \
(_SS_SIZE - __SOCKADDR_COMMON_SIZE - sizeof (__ss_aligntype))

struct sockaddr_storage
{
__SOCKADDR_COMMON (ss_);    /* Address family, etc.  */
char __ss_padding[_SS_PADSIZE];
__ss_aligntype __ss_align;    /* Force desired alignment.  */
};
```

## 专用 socket 地址

上面的通用地址结构体是以字节的方式格式化存储地址，这并不便于代码操作。

所以 Linux 为各个协议族提供了专门的 socket 地址结构体：

```c
#define    __SOCKADDR_COMMON(sa_prefix)            \
sa_family_t sa_prefix##family

/* Structure describing the address of an AF_LOCAL (aka AF_UNIX) socket.  */
struct sockaddr_un
{
    __SOCKADDR_COMMON (sun_);
    char sun_path[108];        /* Path name.  */
};

/* Internet address.  */
typedef uint32_t in_addr_t;
struct in_addr
{
    in_addr_t s_addr;
};

/* IPv6 address */
struct in6_addr
{
    union
    {
      uint8_t    __u6_addr8[16];
    } __in6_u;
    #define s6_addr            __in6_u.__u6_addr8
};

/* Structure describing an Internet socket address.  */
struct sockaddr_in
{
    __SOCKADDR_COMMON (sin_);
    in_port_t sin_port;            /* Port number.  */
    struct in_addr sin_addr;        /* Internet address.  */

    /* Pad to size of `struct sockaddr'.  */
    unsigned char sin_zero[sizeof (struct sockaddr) -
                           __SOCKADDR_COMMON_SIZE -
                           sizeof (in_port_t) -
                           sizeof (struct in_addr)];
};

/* Ditto, for IPv6.  */
struct sockaddr_in6
{
    __SOCKADDR_COMMON (sin6_);
    in_port_t sin6_port;    /* Transport layer port # */
    uint32_t sin6_flowinfo;    /* IPv6 flow information */
    struct in6_addr sin6_addr;    /* IPv6 address */
    uint32_t sin6_scope_id;    /* IPv6 scope-id */
};
```

这样在编程设置地址参数时就可以使用这些结构体，最后在调用对应函数时强制转换为 `sockaddr` 即可。

## IP 地址转换函数

为了提高编程的可读性，Linux 提供了字符串方式地址到二进制地址的相互转换函数：

```c
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

//将以字符串表示的 IPv4 地址转换为网络字节序的整数并存储于 inp 中
int inet_aton(const char *cp, struct in_addr *inp);
//将以字符串表示的 IPv4 地址转换为网络字节序的整数
in_addr_t inet_addr(const char *cp);

//将网络字节序的整数地址转换为字符串表示的 IPv4 地址
//此函数返回指向静态内存，所以其不可重入
char *inet_ntoa(struct in_addr in);

//将以字符串表示的 IPv4 或 IPv6 地址转换为网络字节序，并存储于对应的地址结构体中
int inet_pton(int af, const char *src, void *dst);
//将网络字节序的整数地址转换为字符串表示的 IPv4 或 IPv6 地址，size 指定转换的大小
//IPv4 大小至少为 INET_ADDRSTRLEN
//IPv6 大小至少为 INET6_ADDRSTRLEN
const char *inet_ntop(int af, const void *src,
                    char *dst, socklen_t size);
```

# 创建 socket

Linux 提供了 `socket` 函数来创建一个 socket 对象：

```c
#include <sys/types.h>          /* See NOTES */
#include <sys/socket.h>

int socket(int domain, int type, int protocol);
```

- `domain` 指定底层协议族
  + `AF_INET` 表示 IPv4， `AF_INET6` 表示 IPv6， `AF_UNIX,AF_LOCAL` 表示 UNIX 本地协议族
- `type` 指定服务类型，对于 `TCP` 协议则设置为 `SOCK_STREAM` (流服务)，对于 `UDP` 协议则设置为 `SOCK_DGRAM` （数据报服务）
  + 以上参数可以与 `SOCK_NONBLOCK` （非阻塞）和 `SOCK_CLOEXEC` （用 fork 调用创建子进程时，子进程关闭该 socket）相与
- `protocol` 表示具体的协议，一般前两个值都已经决定了协议的唯一性，一般设 0 表示使用默认协议。

# 命名 socket

将一个 socket 与 socket 地址绑定称为给 socket 命名。

在服务器程序中，通常要命名 socket，只有命名后客户端才能知道如何连接它。
而在客户端中，通常不需要命名，采用系统自动分配的地址即可。

```c
#include <sys/types.h>
#include <sys/socket.h>

//将 addr 所指的地址分配给未命名的 sockfd 文件描述符
int bind(int sockfd, const struct sockaddr *addr,
       socklen_t addrlen);
```

# 监听 socket

将 socket 命名之后，需要创建一个监听队列存放待处理的客户端连接：

```c
#include <sys/types.h> 
#include <sys/socket.h>
//创建一个以 sockfd 对应的最大长度为 backlog 的监听队列
int listen(int sockfd, int backlog);
```

`backlog` 表示处于完全连接状态的 socket 的上限，半连接的上限由 `/proc/sys/net/ipv4/tcp_max_syn_backlog` 指定。

**需要注意的是：backlog 代表可连接最大长度减一**，比如 backlog 设置为 5，代表最多可以连接 6 个客户端。

使用 `telnet` 连接下面代码的服务端，并用 `netstat -nt | grep <port>` 的方式查看状态便可验证：

```c
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("usage: %s : <port> <backlog>\n", argv[0]);

        return -1;
    }

    int port = atoi(argv[1]);
    int backlog = atoi(argv[2]);
    //设置地址
    struct sockaddr_in sockaddr;

    sockaddr.sin_family = AF_INET;
    sockaddr.sin_port = htons(port);
    sockaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    //新建 socket，类型是 IPv4 TCP
    int socket_fd = socket(sockaddr.sin_family, SOCK_STREAM, 0);
    if (socket_fd <= 0) {
        perror("create socket failed:");
        return -1;
    }
    //socket 命名
    if (bind(socket_fd, (const struct sockaddr *)&sockaddr, sizeof(sockaddr)) < 0) {
        perror("can't bind socket and addr:");
        return -1;
    }
    //开始监听
    if (listen(socket_fd, backlog) < 0) {
        perror("listen failed!\n");
        return -1;
    }

    while(1) {
        sleep(1);
    }

    return 0;
}
```

# 接受连接

所谓的接受连接，是指从监听队列中取出一个 client 连接的节点，然后处理。

- accept 不会判断当前连接处于何种状态（比如客户端异常断开）

```c
#include <sys/types.h>          
#include <sys/socket.h>

//从 sockfd 对应的监听队列中取出一个监听 socket 赋值给 addr
//返回一个新连接 socket 的标识
int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
```

# 发起连接

客户端通过 `connect` 来主动发起连接：

```c
#include <sys/types.h>          
#include <sys/socket.h>

//将 sockfd 与 addr 指向的地址进行连接
int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
```

# 关闭连接

关闭连接可以使用 `close` 和 `shutdown` :

```c
#include <unistd.h>

//将 fd 引用计数减一，只有当计数为 0 时才真正关闭连接，在父子进程中需要注意
int close(int fd);

#include <sys/socket.h>

//立即以 how 的方式关闭 sockfd（不管引用计数）
//how : SHUT_RD -> 关闭读 SHUT_WR -> 关闭写 SHUT_RDWR -> 全关闭
int shutdown(int sockfd, int how);
```

# 数据读写

## TCP 数据读写

```C
#include <sys/types.h>
#include <sys/socket.h>

ssize_t send(int sockfd, const void *buf, size_t len, int flags);
ssize_t recv(int sockfd, void *buf, size_t len, int flags);
```

需要明白的是：由于 TCP 是流数据通信，很可能 `recv()` 所返回的实际读取长度小于需求的长度，所以需要多次调用 `recv()` 才能得到完整的数据。

> 当 `recv()`返回 0 时，代表对方已经关闭了连接

flags 常用的取值如下（这些逻辑可以通过逻辑或组合起来）：

| 选项名           | 含义                                                 | send | recv |
| ------------- | -------------------------------------------------- | ---- | ---- |
| MSG_CONFIRM   | 仅用 SOCK_DGRAM,SOCK_RAW 类型，指示数据链路层协议持续监听对方回应，直到得到答复 | Y    | N    |
| MSG_DONTROUTE | 不查看路由表，直接将数据发送给本地局域网内的主机                           | Y    | N    |
| MSG_DONTWAIT  | 非阻塞操作                                              | Y    | Y    |
| MSG_MORE      | 内核超时等待更多数据写入发送缓存后一次性发送，提高传输效率                      | Y    | N    |
| MSG_WAITALL   | 读操作仅在读取到指定数量的字节后才返回                                | N    | Y    |
| MSG_PEEK      | 读取数据，但不清除读缓存                                       | N    | Y    |
| MSG_OOB       | 紧急数据的读写                                            | Y    | Y    |
| MSG_NOSIGNAL  | 往读端关闭的管道或 socket 连接中写入数据时，不会引发 SIGPIPE             | Y    | N    |

## UDP 数据读写

```c
ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
               struct sockaddr *src_addr, socklen_t *addrlen);
ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
             const struct sockaddr *dest_addr, socklen_t addrlen);
```

由于 UDP 没有连接的概念，所以在其发送和接收函数中需要包含与其通信的地址信息。

## 通用数据读写

```c
struct iovec {                    /* Scatter/gather array items */
    void  *iov_base;              /* Starting address */
    size_t iov_len;               /* Number of bytes to transfer */
};

struct msghdr {
    void         *msg_name;       /* optional address */
    socklen_t     msg_namelen;    /* size of address */
    struct iovec *msg_iov;        /* scatter/gather array */
    size_t        msg_iovlen;     /* # elements in msg_iov */
    void         *msg_control;    /* ancillary data, see below */
    size_t        msg_controllen; /* ancillary data buffer len */
    int           msg_flags;      /* flags on received message */
};
ssize_t recvmsg(int sockfd, struct msghdr *msg, int flags);
ssize_t sendmsg(int sockfd, const struct msghdr *msg, int flags);
```

通用数据读写函数既可以用于 TCP 也可以用于 UDP，这两个函数使用分散聚合模式来实现多段内存的读写：

- `struct iovec` 代表一块内存
- `msg_iov` 指向多段内存数组地址， `msg_iovlen` 指定数组长度
- `msg_name,msg_namelen` 分别表示对端的 socket 地址和长度，对于 TCP 而言设置为 NULL 
- `flags` 设定与前面的数据读写标记一致

# 带外标记

当有带外标记（紧急）数据到达时，内核会产生异常事件或 `SIGURG` 信号，然后用户程序通过 `sockatmark` 判断下一个数据是否是带外数据，然后通过 `MSG_OOB` 标记接收数据。

```c
#include <sys/socket.h>

int sockatmark(int sockfd);
```

为了理解带外标记，现在运行服务端，然后 PC 发送普通数据和带外数据来观察服务端的输出。

服务端代码：

```c
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
        perror("listen failed:");

        return -1;
    }
    printf("I'm waiting for client...\n");
    //accept
    int client_fd = 0;

    struct sockaddr_in client_addr;
    socklen_t     addr_len = sizeof(client_addr);
    if ((client_fd = accept(socket_fd, (struct sockaddr *)&client_addr, &addr_len)) < 0) {
        perror("accept failed:");

        return -1;
    }

    printf("connected to client ip: %s, port: %d\n",
    inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));

    ssize_t recv_len;

    #define RECV_BUF_SIZE   (30)
    char recv_buf[RECV_BUF_SIZE];

    memset(recv_buf, 0, RECV_BUF_SIZE);
    recv_len = recv(client_fd, recv_buf, RECV_BUF_SIZE - 1, 0);
    printf("1.received %ld bytes : %s\n", recv_len, recv_buf);

    memset(recv_buf, 0, RECV_BUF_SIZE);
    recv_len = recv(client_fd, recv_buf, RECV_BUF_SIZE - 1, MSG_OOB);
    if(recv_len < 0){
        perror("recv failed:");
    }
    printf("2.received %ld bytes : %s\n", recv_len, recv_buf);

    memset(recv_buf, 0, RECV_BUF_SIZE);
    recv_len = recv(client_fd, recv_buf, RECV_BUF_SIZE - 1, 0);
    printf("3.received %ld bytes : %s\n", recv_len, recv_buf);


    close(client_fd);
    close(socket_fd);

    return 0;
}
```

客户端代码：

```c
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
        printf("%s: %s\n", host_info->h_addrtype == AF_INET ? "ipv4" : "ipv6",inet_ntoa(*(struct in_addr *)host_info->h_addr_list[i]));
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
        perror("connect to server failed:");
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

```shell
# 服务端启动
$ ./oob_server 65123
I'm waiting for client...

# 客户端连接
./oob_client lab.local 65123
I have found the ip address of host lab.local is:
ipv4: 192.168.11.67

# 服务端接收
connected to client ip: 192.168.11.52, port: 13298
1.received 5 bytes : 123ab
2.received 1 bytes : c
3.received 3 bytes : 123
```

可以看到：虽然客户端发送的带外数据是 "abc" ，但是只有最后一个字符 "c" 被当做带外数据。且服务器对正常数据的接收将被带外数据截断，也就是无法通过一个 `recv` 全部读出。

同时 Wireshark 抓取的信息如下：

![](./catch_oob.jpg)

其过程如下：

1. 握手：客户端首先与服务器进行 3 次握手
2. 发送普通数据“123”
3. 发送紧急数据“abc123”，此时`URG`标志位置位，且紧急指针的值为 3，也就是说`c`为紧急数据
4. 客户端发送断开数据报
5. 服务器应答普通数据
6. 服务器应答紧急数据
7. 服务器应答结束报文
8. 客户端返回应答，最终便断开了连接

# 地址信息

```c
#include <sys/socket.h>

//获取本端 socket 地址
int getsockname(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
//获取对端 socket 地址
int getpeername(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
```

# socket 选项

以下函数用于获取和设置 `socket` 文件描述符属性的函数：

```c
  #include <sys/types.h>          
  #include <sys/socket.h>

  //level 设定协议栈哪一层选项，optname 设置具体选项
  int getsockopt(int sockfd, int level, int optname,
                 void *optval, socklen_t *optlen);
  int setsockopt(int sockfd, int level, int optname,
                 const void *optval, socklen_t optlen);
```

需要注意的是：**对服务端而言，需要在 `listen` 之前设置 socket。对于客户端而言，需要在 `connect` 之前设置 socket。**

下面根据协议栈的 Level 来说明常用的设置。

## SOL_SOCKET(通用 socket 选项，与协议无关)

- SO_DEBUG： 打开调试信息

- SO_REUSEADDR： 重用本地地址（而不是让 TCP 连接处于 `TIME_WAIT` 状态，等待很久后才能重用此地址）
  
  + 也可以通过修改 `/proc/sys/net/ipv4/tcp_tw_reuse` 达到同样的需求
    
    ```c
    int reuse = 1;
    if (setsockopt(socket_fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
    perror("Can't set socket:");
    }
    ```

- SO_TYPE：获取 socket 类型

- SO_ERROR： 获取并清除 socket 错误状态

- SO_DONTROUTE： 不查看路由表，直接将数据发送给本地局域网内的主机，与 send 函数的 `MSG_DONTROUTE` 效果一样

- SO_RCVBUF：TCP 接收缓冲区大小
  
  + 也可以设置 `/proc/sys/net/ipv4/tcp_rmem`

- SO_SNDBUF： TCP 发送缓冲区大小
  
  + 也可以设置 `/proc/sys/net/ipv4/tcp_wmem`

- SO_KEEPALIVE：发送周期性保活报文以维持连接
  
  + 关于 keepalive 的理解参考[此链接](https://holmeshe.me/network-essentials-setsockopt-SO_KEEPALIVE/)

- SO_OOBINLINE：将带外数据存放于普通数据缓存中，用户使用普通读取方式获取

- SO_LINGER：若有数据待发送，则延迟关闭，通过 `linger` 结构体配置是立即关闭，还是发送残留数据后关闭

- SO_RCVLOWAT： TCP 接收缓存区低水位标记，当缓存数据大于低水位时，应用程序便可以读取

- SO_SNDLOWAT：TCP 发送缓存区低水位标记，当空闲数据大于低水位时，应用程序便可以发送

- SO_RCVTIMEO： 接收数据超时

- SO_SNDTIMEO：发送数据超时

下面通过实例理解 TCP 接收和发送缓冲区大小设置。

服务端代码：

```c
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define BUFFER_SIZE (1024)
int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("usage: %s <port> <recv buffer size>\n", argv[0]);

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
    if(socket_fd < 0) {
        perror("can't create socket:");
        return -1;
    }
    int recvbuf = atoi(argv[2]);
    int len = sizeof(recvbuf);

    setsockopt(socket_fd, SOL_SOCKET, SO_RCVBUF, &recvbuf, sizeof(recvbuf));
    getsockopt(socket_fd, SOL_SOCKET, SO_RCVBUF, &recvbuf, (socklen_t *)&len);

    printf("I want to set recv buf is %d, actually recv buf is %d\n",
    atoi(argv[2]), recvbuf);
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
    int client_fd = 0;
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);
    if ((client_fd = accept(socket_fd, (struct sockaddr *)&client_addr, &addr_len)) < 0) {
        perror("accept failed!\n");
        return -1;
    }
    printf("connected to client ip: %s, port: %d\n",
    inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));
    char buffer[BUFFER_SIZE];
    memset(buffer, 0, BUFFER_SIZE);
    while (recv(client_fd, buffer, BUFFER_SIZE - 1, 0) > 0) {

    }
    close(client_fd);
    close(socket_fd);
    return 0;
}
```

客户端代码：

```c
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#include <assert.h>
#include <stdint.h>

#define BUFFER_SIZE (4096)
int main(int argc, char *argv[]){
    if (argc != 4) {
        printf("usage: %s <hostname> <port> <send buffer size>\n", argv[0]);
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

    int sendbuf = atoi(argv[3]);
    int len = sizeof(sendbuf);

    setsockopt(socket_fd, SOL_SOCKET, SO_SNDBUF, &sendbuf, sizeof(sendbuf));
    getsockopt(socket_fd, SOL_SOCKET, SO_SNDBUF, &sendbuf, &len);
    printf("I want to set send buf is %d, actually it is %d\n",
    atoi(argv[3]), sendbuf);
    //connect
    if (connect(socket_fd, (const struct sockaddr *)&socket_addr, sizeof(socket_addr)) < 0) {
        perror("connect to server failed:");
        return -1;
    }
    char buffer[BUFFER_SIZE];
    memset(buffer, 'a', BUFFER_SIZE);
    send(socket_fd, buffer, BUFFER_SIZE, 0);
    close(socket_fd);
    return 0;
}
```

```shell
#服务端启动
$ ./size_server 54321 50
I want to set recv buf is 50, actually recv buf is 2304
I'm waiting for client...

#客户端启动
$ ./a.out lab.local 54321 50
I have found the ip address of host lab.local is:
ipv4: 192.168.11.67
I want to set send buf is 50, actually it is 4608
```

可以看到接收缓冲区大小会被限制，系统会主动增加这些值。

通过 Wireshark 抓取：

![](./catch_send_recv_buffer.jpg)

分析其流程如下：

1. 握手
   + 客户端发送的窗口大小是 64240，扩大因子是 128
   + 服务端返回的窗口大小是 1152，扩大因子是 1
2. 发送：在这个过程中，客户端会分段多次发送数据，等待服务端读取数据后再次发送
3. 断开：这次断开是 4 次挥手，服务端先返回应答，然后再返回对于`FIN`数据报的应答 
   - 客户端发送`FIN`数据报的时候也顺带发送了最后的数据

## IPPROTO_IP(IPv4 选项）

- IP_TOS：服务类型，用于设置最大延迟、最大吞吐等
- IP_TTL：存活时间，最多可以中转多少个路由器

## IPPROTO_IPV6(IPv6 选项)

- IPV6_NEXTHOP: 下一跳 IP 地址
- IPV6_RECVPKTINFO：接收分组信息
- IPV6_DONTFRAG：禁止分片
- IPV6_RECVTCLASS：接收通信类型

## IPPROTO_TCP(TCP 选项)

- TCP_MAXSEG: TCP 最大报文段大小
- TCP_NODELAY: 禁止 Nagle 算法

# 网络信息

socket 地址指的是 IP 地址和端口号的集合，但这两个信息都是数值。

如果能够通过字符串的形式转换一次，客户端的访问将比较方便。

- 其中 IP 地址对应**主机名** ，端口号对应**服务名**
- 服务端修改 IP 地址后并不会影响客户端。

在局域网中，如果没有架设 DNS，则可以通过在服务端和客户端安装 `avahi-daemon` 通过 `hostname.local` 的方式访问。

## gethostbyname, gethostbyaddr

```c
#include <netdb.h>

struct hostent {
    char  *h_name;            /* official name of host */
    char **h_aliases;         /* alias list */
    int    h_addrtype;        /* host address type */
    int    h_length;          /* length of address */
    char **h_addr_list;       /* list of addresses */
}


//根据主机名称获取主机的完整信息
struct hostent *gethostbyname(const char *name);

#include <sys/socket.h>       /* for AF_INET */
//根据 IP 地址获取主机的完整信息
struct hostent *gethostbyaddr(const void *addr,
                            socklen_t len, int type);
```

`gethostbyname` 函数首先在本地的 `/etc/hosts` 文件中查找主机，如果没有找到再去访问 DNS 服务器。

**需要注意的是**: `h_addr_list` 是以网络字节序存放的字节数组，而不是字符串！要以字符串显示需要使用 `inet_ntoa` 函数。

## getservbyname, getservbyport

```c
#include <netdb.h>

struct servent {
    char  *s_name;       /* official service name */
    char **s_aliases;    /* alias list */
    int    s_port;       /* port number */
    char  *s_proto;      /* protocol to use */
}

//根据名称获取某个服务的完整信息
struct servent *getservbyname(const char *name, const char *proto);
//根据端口号获取某个服务的完整信息
struct servent *getservbyport(int port, const char *proto);
```

以上的转换关系都是通过读取 `/etc/services` 文件来获取服务信息的。

## getaddrinfo

```c
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>

struct addrinfo {
    int              ai_flags;
    int              ai_family;
    int              ai_socktype;
    int              ai_protocol;
    socklen_t        ai_addrlen;
    struct sockaddr *ai_addr;
    char            *ai_canonname;
    struct addrinfo *ai_next;
};
//通过主机名和服务名获得 IP 地址和端口号
int getaddrinfo(const char *node, const char *service,
              const struct addrinfo *hints,
              struct addrinfo **res);
//res 资源是在函数内被申请，所以需要主动释放
void freeaddrinfo(struct addrinfo *res);
```

## getnameinfo

```c
#include <sys/socket.h>
#include <netdb.h>

//通过 socket 地址同时获得以字符串表示的主机名和服务名
int getnameinfo(const struct sockaddr *sa, socklen_t salen,
              char *host, socklen_t hostlen,
              char *serv, socklen_t servlen, int flags);
```
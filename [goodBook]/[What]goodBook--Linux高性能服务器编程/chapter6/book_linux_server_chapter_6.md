---
title: '[What]Linux 高级 I/O 函数'
tags: 
- CS
date:  2019/11/13
categories: 
- book
- Linux高性能服务器编程
layout: true
---

APUE 对 IO 函数都有详细的解释，现在再来回顾一下。

<!--more-->

# pipe
关于 pipe 的使用，[之前就已经写过了](http://kcmetercec.top/2018/04/19/linux_operations_process_communication/#org2e68f11)。
# dup
``` c
#include <unistd.h>

//得到一个文件描述符副本
int dup(int oldfd);
int dup2(int oldfd, int newfd);

#define _GNU_SOURCE             /* See feature_test_macros(7) */
#include <fcntl.h>              /* Obtain O_* constant definitions */
#include <unistd.h>

int dup3(int oldfd, int newfd, int flags);
```
`dup` 得到文件描述符副本，副本和原文件描述符指向同一个文件。

dup 的关键在于： *返回当前可用的最小描述符*

比如先关闭标准输出，然后立即调用 dup，此时 dup 返回最小描述符则是 1。
也就是说 1 和当前文件描述符指向同一个文件，那个调用 `printf` 时，内容也就写入文件了。

看下面示例：
``` c
  #include <stdio.h>
  #include <unistd.h>
  #include <sys/types.h>
  #include <sys/stat.h>
  #include <fcntl.h>

  int main(int argc, char *argv[]){
    int fd = open("./output", O_RDWR);
    if(fd < 0){
        perror("create file failed:");
        return -1;
      }

    printf("This message is before dup\n");

    close(STDOUT_FILENO);
    int ret_fd = dup(fd);

    printf("This message is after dup\n");
    printf("dup return fd is %d\n", ret_fd);

    return 0;
  }
```

# readv 和 writev
``` c
  #include <sys/uio.h>

  struct iovec {
    void  *iov_base;    /* Starting address */
    size_t iov_len;     /* Number of bytes to transfer */
  };

  //从 fd 读取内容到分散的 iov 指向的内存中
  ssize_t readv(int fd, const struct iovec *iov, int iovcnt);

  //将 iov 指向的分散的内存写入到 fd 中 
  ssize_t writev(int fd, const struct iovec *iov, int iovcnt);

  ssize_t preadv(int fd, const struct iovec *iov, int iovcnt,
                 off_t offset);

  ssize_t pwritev(int fd, const struct iovec *iov, int iovcnt,
                  off_t offset);
```
# sendfile
``` c
  #include <sys/sendfile.h>

  //从 in_fd 的 offset 处拷贝 count 字节到 out_fd 中
  //in_fd 对象必须能支持 mmap 类操作，out_fd 可以是任意文件
  ssize_t sendfile(int out_fd, int in_fd, off_t *offset, size_t count);
```
sendfile 是零拷贝函数，因为是在内核中完成文件内容的复制，就没有用户空间到内核空间这一层的拷贝了。
- 显然这样的操作效率更高

下面验证服务端将一个文件发送给客户端，服务端代码：
``` c
  #include <sys/types.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  #include <sys/socket.h>
  #include <stdio.h>
  #include <stdlib.h>
  #include <string.h>
  #include <unistd.h>     
  #include <sys/sendfile.h>    
  #include <fcntl.h>      
  #include <sys/stat.h>                                                             
  int main(int argc, char *argv[]){                                                                                              
      if(argc != 3){
          printf("usage: %s <port> <filepath>\n", argv[0]);
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
      if(socket_fd < 0){
          perror("can't create socket!\n");
          return -1;
      }                                                                                          
      //bind
      if(bind(socket_fd, (const struct sockaddr *)&socket_addr, sizeof(socket_addr)) < 0){
          perror("bind socket and address failed!\n");
          return -1;
      }                                                                                          
      //listen
      if(listen(socket_fd, 5) < 0){
          perror("listen failed!\n");
          return -1;
      }   
      printf("I'm waiting for client...\n");
      //accept
      int client_fd = 0;
      struct sockaddr_in client_addr;
      socklen_t     addr_len = sizeof(client_addr);
      if((client_fd = accept(socket_fd, (struct sockaddr *)&client_addr, &addr_len)) < 0){
          perror("accept failed!\n");
          return -1;
      }
      printf("connected to client ip: %s, port: %d\n",                                           
      inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));
      printf("send file %s to client\n", argv[2]);  

      int file_fd = open(argv[2], O_RDONLY);

      struct stat file_stat;
      fstat(file_fd, &file_stat);

      if(sendfile(client_fd, file_fd, NULL, file_stat.st_size) < 0){
          perror("sendfile failed:");
      }
      close(client_fd);
      close(socket_fd);
      return 0;
  }
```

通过 `telnet` 连接服务端后便可以获取到该文件了。
# mmap 和 munmap
``` c
  #include <sys/mman.h>

  //将 fd 的 offset 处开始的内存映射 length 字节到 addr
  void *mmap(void *addr, size_t length, int prot, int flags,
             int fd, off_t offset);
  int munmap(void *addr, size_t length);
```
prot 设置内存段的访问权限：
- PROT_READ : 可读
- PROT_WRITE: 可写
- PROT_EXEC: 可执行
- PROT_NONE: 不能被访问

flags 控制内存段内容被修改后程序的行为：
- MAP_SHARED: 共享内存，对内存的修改被映射到文件中
- MAP_PRIVATE: 私有内存，对内存的修改不会被映射到文件中
- MAP_ANONYMOUS: 这段内存不是从文件映射来的，内容被初始化为全 0
- MAP_FIXED: 内存段必须位于 addr 参数指定的地址处，start 必须与内存页对齐
- MAP_HUGETLB: 按照大内存页面来分配内存空间
# splice
``` c
  #define _GNU_SOURCE         /* See feature_test_macros(7) */
  #include <fcntl.h>

  //将 fd_in 从 off_in 处拷贝 len 字节到 fd_out 的 off_out 处
  // fd_in 和 fd_out 中必须至少有一个是管道文件描述符
  ssize_t splice(int fd_in, loff_t *off_in, int fd_out,
                 loff_t *off_out, size_t len, unsigned int flags);
```
此函数也是直接在内核操作，属于零拷贝高效率操作。

flags 控制数据如何移动：
- SPLICE_F_MOVE : 内核尝试按整页移动数据
- SPLICE_F_NONBLOCK : 以非阻塞的形式操作
- SPLICE_F_MORE: 提示内核后续还会读取更多数据

# tee
``` c
  #define _GNU_SOURCE         /* See feature_test_macros(7) */
  #include <fcntl.h>

  //复制两个管道文件描述符之间的数据，不消耗数据
  ssize_t tee(int fd_in, int fd_out, size_t len, unsigned int flags);
```
# fcntl
``` c
  #include <unistd.h>
  #include <fcntl.h>

  //对文件描述符控制
  int fcntl(int fd, int cmd, ... /* arg */ );
```


---
title: Linux 内存应用
tags: 
- linux
categories:
- linux
- memory
- overview
date: 2024/8/18
updated: 2024/8/18
layout: true
comments: true
---

课程: 宋宝华老师的内存管理

理解了内存概念后再来看应用方面的知识就会比以前深入得多。

| kernel version | arch  |
| -------------- | ----- |
| v5.4.0         | arm32 |

<!--more-->

# memory cgroup

linux通过 cgroup 对系统中的3大资源： 内存资源，I/O资源,进程占用CPU资源。都可以为它们加入各自的组，进行对应的资源限制。

对内存的限制就称为memroy cgroup。

## 体验

编写测试代码:

```C
  #include <stdlib.h>
  #include <stdio.h>
  #include <string.h>

  int main(int argc , char **argv)
  {
    int max = -1;
    int mb = 0;
    char *buffer;
    int i ;
  #define SIZE 2000
    unsigned int *p = malloc(1024*1024*SIZE);
    printf("malloc buffer : %p\n", p);
    for(i = 0; i < 1024*1024*(SIZE/sizeof(int));i++)
      {
        p[i] = 123;
        if((i&0xfffff) == 0)
          {
            printf("%dMB written\n", i >> 18);
            usleep(100000);
          }
      }
    pause();
    return 0;
  }
```

```shell
  #关闭swap分区
  swapoff -a
  #允许应用程序申请内存
  echo 1 > /proc/sys/vm/overcommit_memory
  #进入memory cgroup 并创建 group
  cd /sys/fs/cgroup/memory/
  mkdir A
  cd A
  #限制此group可以使用的最大内存为200M
  echo $((200*1024*1024)) > memory.limit_in_bytes

  #添加进程到memory group A,并运行
  sudo cgexec -g memory:A ./a.out
  #可以发现其申请到200M内存时就被系统kill掉了
```

# 脏页的写回

内存中脏页写回到硬盘，是由内核来完成的，它需要考虑时间和空间的维度。

- 时间：脏页在内存中待的时间需要合适
  + 如果太长则提高了掉电丢数据的概率
  + 如果太短则会由于写硬盘操作过于频繁而降低系统的处理能力
- 空间维度：脏页在内存中所占的比例不能太高
  + 如果太高则一次写硬盘的时间太长，当其他进程需要内存时则需要等待这个操作完成

## 时间配置

- `/proc/sys/vm/dirty_expire_centisecs` : 此文件配置当脏页存在的时间超过此值时，则会触发写回操作
  + 最终的时间计算是: `值 * 10ms`

## 空间配置

- `/proc/sys/vm/dirty_background_ratio` : 当进程写的脏页比例超过此值时，内核将触发写回操作
  + 此时有可能进程还依然在产生脏页
- `/proc/sys/vm/dirty_ratio` : 当进程写的脏页比例超过此值时，内核将禁止进程产生脏页
  + 此时进程这部分操作就被停止了，所以 `dirty_ratio` 的值大于 `dirty_background_ratio` 的值

# 内存回收原则

正常情况下，当内存不够用时，内核会将内存中的 `file-backed pages` 和 `anonymous pages` 进行swap。

- `/proc/sys/vm/min_free_kbytes` : 决定了内存中无论如何都要保持的最小空闲内存。
  + 这段内存是为了用于运行系统紧急处理时所需要的进程。
    - 申请紧急内存使用标志位 `PF_MEMALLOC`
  + `min_free_kbytes = 4 * sqrt(lowmem_kbytes); //lowmem_kbytes指的是低端内存所占用的kb`

当 `min_free_kbytes` 被确定后， `dma_zone`, `normal_zone`, 会根据此值计算它们的水位。

- dma_min = dma_zone_size / (dma_zone_size + normal_zone_size) * min_free_kbytes
  + 低水位: low = dma_min * 125%
  + 高水位: high = dma_min * 150%
- normal_min = normal_zone_size / (dma_zone_size + normal_zone_size) * min_free_kbytes
  + 低水位: low = normal_min * 125%
  + 高水位: high = normal_min * 150%

基于上面的公式，这样 `dma_zone` 和 `normal_zone` 都会具有 min,low,high 3个值，作用分别如下：

- min : 当内存到此值，内核在应用程序的进程上下文进行回收内存(direct reclaim)，会阻塞应用
- low : 当内存到此值，内核的 `kswapd` 服务启动内存回收(reclaim),不会阻塞应用
- high : 当内存到此值，内核停止内存回收

可以看出这个工作机制和脏页写回机制类似。

**但是脏页写回的触发条件是以脏页的时间或空间为基准的，而内存回收则是以内存不够用为基准触发条件的。**

# swap空间触发时机

swappiness 反映是否积极的使用swap空间(也就是swap anonymous pages)，其设定值位于 `/proc/sys/vm/swappiness` 文件中。

根据其取值来决定:

- 0 : 仅在内存不足的情况下使用swap空间
  + 也就是空闲的内存和file-backed页空间之和小于zone的 high 水位之时
- 60 : 默认值
- 100 : 积极的使用swap空间

某个进程也可以通过系统调用 `mlockall(MCL_CURRENT | MCL_FUTURE)` 来禁止内核对此进程的所占用的一切内存空间进行swap，可以提高该进程在内存应用上的是实时性。

# 获取进程延迟

`Documentation/accounting/getdelays.c` 工具用于测量调度、I/O、swap、Reclaim延迟。

此代码是一个独立代码不是内核模块，所以可以将其直接通过gcc编译。

使用格式为: 

```shell
  #<exec>即为可执行文件名
  ./getdelays -d -c <exec>
```

# 获取系统的动态情况

vmstat 可以展现给Linux的CPU使用率、内存使用、虚拟内存交换情况、I/O读写情况等。

- vmstat <period> : <period> 代表每隔几秒刷新一次监控情况

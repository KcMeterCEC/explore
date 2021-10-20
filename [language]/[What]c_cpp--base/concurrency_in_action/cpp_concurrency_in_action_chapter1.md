---
title: '[What] C++ Concurrency in Action 2nd ：c++ 中的并发'
tags: 
- c++
date:  2021/2/2
categories: 
- language
- c/c++
- Concurrency
layout: true
---
c++ 对于多线程的支持是在 c++11 及以后才出现的。
<!--more-->

# c++ 多线程的历史

在 c++98 的年代，并不支持多线程。程序员只能调用系统 API 或 boost 这种第三方库完成多线程编程。

但由于缺乏标准的支持，c++ 在内存模型上对于多线程的支持并不友好，容易遇到很多坑。

c++11 在参考 boost 库的基础上将多线程支持纳入了标准，包括内存模型、多线程同步、原子操作等。

c++14 进而又增加了互斥类型，c++17 增加了并行算法。



当然，c++ 并没有完全支持对于多线程操作的所有封装，还是会有些时候需要使用系统 API。

这种情况下为了尽量的保证可移植性，应该使用`native_handle`方法来获取底层数据结构。

比如要修改 linux 下线程的调度策略：

```cpp
#include <thread>
#include <mutex>
#include <iostream>
#include <chrono>
#include <cstring>

#include <pthread.h>
 
std::mutex iomutex;
void f(int num) {
    std::this_thread::sleep_for(std::chrono::seconds(1));
 
    sched_param sch;
    int policy; 
    pthread_getschedparam(pthread_self(), &policy, &sch);
    std::lock_guard<std::mutex> lk(iomutex);
    std::cout << "Thread " << num << " is executing at priority "
              << sch.sched_priority << '\n';
}
 
int main() {
    std::thread t1(f, 1), t2(f, 2);
 
    sched_param sch;
    int policy;
    
    pthread_getschedparam(t1.native_handle(), &policy, &sch);
    sch.sched_priority = 20;
    if (pthread_setschedparam(t1.native_handle(), SCHED_FIFO, &sch)) {
        std::cout << "Failed to setschedparam: " << std::strerror(errno) << '\n';
    }
 
    t1.join(); t2.join();
}
```

# 一个简易的多线程示例

```cpp
#include <iostream>
//多线程管理的头文件
#include <thread>

void hello(void) {
    std::cout << "Hello world!\n";
}

int main(void) {

    std::thread t1(hello);

    //等待线程 t1 运行完毕
    t1.join();

    return 0;
}
```


---
title: '[What] Effective Modern C++ ：基于任务编程优于基于线程编程'
tags: 
- c++
date:  2021/10/7
categories: 
- language
- c/c++
- Effective
layout: true
---

要异步运行一个可调用对象，有两个选择：
- 基于线程编程：使用`std::thread`创建新的线程
```cpp
int doAsyncWork();
std::thread t(doAsyncWork);
```
- 基于任务编程：使用`std::async`
```cpp
auto fut = std::async(doAsyncWork);        // "fut" for "future"
```
基于任务编程优于基于线程编程的原因是：
1. 基于任务编程所需的代码略少于基于线程编程
2. `std::async`返回的`std::future`可以获取任务的返回及异常，而`std::thread`则没有简单的方式来获取
  > `std::thread`中如果抛出异常，则默认会调用到`std::terminate`而终止进程
3. 线程的切换所消耗的上下文切换、cache miss 时间也较多

<!--more-->

但并不意味着不能使用`std::thread`，在下面这些场合使用基于线程编程是更加合适的：

- 需要对线程做更多的配置：这种情况下需要用到系统层的 API，`std::thread`提供了`native_handle`成员函数以完成设置。而`std::future`则没有
- 需要对线程的使用做特定优化
- 需要对线程做更高级的抽象：比如线程池这些应用


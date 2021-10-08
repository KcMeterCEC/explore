---
title: '[What] Effective Modern C++ ：需要异步执行时，使用 std::launch::async'
tags: 
- c++
date:  2021/10/7
categories: 
- language
- c/c++
- Effective
layout: true
---

当使用`std::async`来调用一个可执行对象时，作者的本意是希望异步执行，但实际还与`std::async`的启动策略有关。

<!--more-->

`std::async`具有两个启动策略：

- `std::launch::async`：被运行对象**立即**以异步的方式执行
- `std::launch::deferred`：被运行对象，当`std::future`的`get(),wait()`成员被调用是才同步运行，就是推迟运行

然而默认的策略却是二者的或：

```cpp
auto fut1 = std::async(f);                     // run f using
                                               // default launch
                                               // policy
auto fut2 = std::async(std::launch::async |    // run f either
                       std::launch::deferred,  // async or
                       f);                     // deferred
```

这完全由标准库根据当前系统负载来决定应该具体以哪种策略来执行。

这在有些时候就容易误导程序员，比如：

```cpp
using namespace std::literals;        // for C++14 duration
                                      // suffixes; see Item 34
void f()                              // f sleeps for 1 second,
{                                     // then returns
  std::this_thread::sleep_for(1s);
}
auto fut = std::async(f);             // run f asynchronously
                                      // (conceptually)
while (fut.wait_for(100ms) !=         // loop until f has
       std::future_status::ready)     // finished running...
{                                     // which may never happen!
  …
}
```

如果策略使用`std::launch::deferred`,则这个 while 循环将一直为真。

> 这个时候的状态是 std::future_status::deferred

一个解决办法就是首先判断一下状态再确定是否进入 while 循环：

```cpp
auto fut = std::async(f);                  // as above
if (fut.wait_for(0s) ==                    // if task is
    std::future_status::deferred)          // deferred...
{
                        // ...use wait or get on fut
  …                     // to call f synchronously
} else {                // task isn't deferred
  while (fut.wait_for(100ms) !=            // infinite loop not
         std::future_status::ready) {      // possible (assuming
                                           // f finishes)
    …                  // task is neither deferred nor ready,
                       // so do concurrent work until it's ready
  }
  …                    // fut is ready
}
```

所以，当在需要明确异步运行的情况下，需要显示的指明`std::launch::async`：

```cpp
auto fut = std::async(std::launch::async, f);
```

其实还可以把这种显示异步配置封装为一个函数模板：

```cpp
// c++ 11 版本
template<typename F, typename... Ts>
inline
std::future<typename std::result_of<F(Ts...)>::type>
reallyAsync(F&& f, Ts&&... params)       // return future
{                                        // for asynchronous
  return std::async(std::launch::async,  // call to f(params...)
                    std::forward<F>(f),
                    std::forward<Ts>(params)...);
}

// c++ 14 版本
template<typename F, typename... Ts>
inline
auto                                           
reallyAsync(F&& f, Ts&&... params)
{
  return std::async(std::launch::async,
                    std::forward<F>(f),
                    std::forward<Ts>(params)...);
}
```


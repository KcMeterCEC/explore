---
title: '[What] Effective Modern C++ ：避免使用默认捕获'
tags: 
- c++
date:  2021/9/30
categories: 
- language
- c/c++
- Effective
layout: true
---

lambda 使得 c++ 更有魅力，使用 lambda 可以创建一个可调用的对象，一般用于以下场合：
1. 快速创建一个简短的函数，仅在父函数中使用，避免繁琐的创建成员函数的过程。
2. 为标准库的算法（`std::find_if,std::sort` 等），优雅的创建一个可调用对象。
3. 快速为标准库创建删除器，比如`std::unique_ptr,std::shared_ptr`等

<!--more-->

# 引用捕获要注意被捕获对象的作用域

如果引用捕获对象的作用域是局部作用域，而 lambda 对象的使用超出了该作用域则会导致引用指向的对象无意义，最终会导致 undefined behavior。

比如设计一个容器，里面包含了函数对象：

```cpp
using FilterContainer = std::vector<std::function<bool(int)>>;

FilterContainer filters;
```

然后在一个函数中，插入可调用对象到容器中：

```cpp
void addDivisorFilter() {
  auto calc1 = computeSomeValue1();
  auto calc2 = computeSomeValue2();
  auto divisor = computeDivisor(calc1, calc2);
  filters.emplace_back(                              
    [&](int value) { return value % divisor == 0; }  
  );                                                
} 
```

由于`divisor`变量在退出函数后，其栈内存就被回收了，所以当该 lambda 被调用时，就是 undefined behavior。

为了避免这种情况，应该使用 passed by value 的形式形成闭包：

```cpp
void addDivisorFilter() {
  auto calc1 = computeSomeValue1();
  auto calc2 = computeSomeValue2();
  auto divisor = computeDivisor(calc1, calc2);
  filters.emplace_back(                              
    [=](int value) { return value % divisor == 0; }  
  );                                                
}
```

同理，如果捕获的参数是一个指针，也需要注意指针指向的内存被释放的情况。

# 静态存储变量与捕获

实际上，lambda 无法捕获静态存储变量而形成闭包：

```cpp
#include <cmath>
#include <chrono>
#include <cstdio>
#include <vector>
#include <iostream>

int main() {
    static int v = 10;

    // 实际上这里加不加 = 都不影响，因为没有捕获到任何变量
    auto func = [=]() {
        std::cout << "The value of v is " << v << "\n";
    };

    v = 3;

    func();

    return 0;
}
```

输出为：

```shell
The value of v is 3
```




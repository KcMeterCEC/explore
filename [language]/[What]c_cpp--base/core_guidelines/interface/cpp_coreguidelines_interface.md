---
title: C++ Core Guidelines：接口
tags: 
- cpp
categories:
- cpp
- CoreGuidelines
date: 2022/7/26
updated: 2022/7/26
layout: true
comments: true
---

通过阅读 [CppCoreGuidelines](https://github.com/isocpp/CppCoreGuidelines) 来理解现代 c++ 编码规范，同时也是对 [Effective C++](https://book.douban.com/subject/1842426/)，[Effective Modern C++](https://book.douban.com/subject/25923597/)，[C++ Concurrency in Action](https://book.douban.com/subject/27036085/) 的温习。

<!--more-->

# 让接口清晰

不能让接口还有一些隐藏属性，导致接口的行为是用户无法预知的。

比如下面的对浮点数取整：

```cpp
int round(double d) {
    return (round_up) ? std::ceil(d) : d;    // don't: "invisible" dependency
}
```

有全局变量`round_up`来决定函数`round`来进行向上取整还是向下取整，这对用户来说是无法预知的。

为了使得接口清晰，需要让用户了解有这个设置项：

```cpp
int round(bool round_up, double d) {
    return (round_up) ? std::ceil(d) : d;
}
```

# 尽量避免`non-const`全局变量

`non-const`全局变量就可能：
1. 导致该变量被多处使用，造成依赖关系
2. 并发`data race`




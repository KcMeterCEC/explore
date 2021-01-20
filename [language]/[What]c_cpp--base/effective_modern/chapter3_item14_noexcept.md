---
title: '[What] Effective Modern C++ ：当函数不会抛出异常时，应该加上 noexcept 修饰'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---

这一个 item 目前还没有完全理解，不过其想表达的主要意思是：**当确认一个函数不会抛出异常时，应该使用`noexcept`修饰**。

> 但是大部分情况下都不会增加这个修饰，因为并不能特别的肯定它以后不会抛出异常，如果以后要改的话，就会比较麻烦。

这样的好处在于：
1. 增加代码的可读性
2. 提高代码的运行效率


---
title: '[What] Effective Modern C++ ：让 const 成员函数是多线程安全的'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---
`const`成员函数在正常情况下，不能对该对象的私有成员变量进行更改，那该函数执行的就是只读操作。

那么多线程调用该成员函数是可以的，例外的是对`mutable`修饰的变量进行更改。
为了避免`const`成员函数的`mutalbe`变量在多线程情况下的数据竞争，需要使用互斥锁、原子锁等方式保证临界区的互斥。

> 当有多个原子锁且有一定顺序时，应该使用互斥锁将它们做成一个整体。
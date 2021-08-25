---
title: '[What] Effective  C++ ：别让异常逃离析构函数'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---
google 编码规范[不使用异常](https://zh-google-styleguide.readthedocs.io/en/latest/google-cpp-styleguide/others/#exceptions)。

<!--more-->
但我们所使用的第三方库很可能会抛出异常，那么就谨记以下原则：

- 如果该操作不在析构/构造函数中，那么就在调用可能抛出异常的对象上使用捕获异常。
  + 这样可以尽量缩小异常的范围
- 如果该操作存在于析构/构造函数中，就需要在捕获异常后做出对应的反应。要么停止程序，要么记录该错误后继续运行。
  + 为了提供更好的灵活性，可以将操作移动到普通成员函数中供用户调用。析构函数中再做一下检查即可。


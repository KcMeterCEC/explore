---
title: '[What] Effective Modern C++ ：区分通用引用和右值引用'
tags: 
- c++
date:  2021/1/27
categories: 
- language
- c/c++
- Effective
layout: true
---
声明一个右值引用，使用`T&&`这种格式，但是这玩意并不是表面上看到的那么简单。
```cpp
void f(Widget&& param);             // 右值引用
Widget&& var1 = Widget();           // 右值引用
auto&& var2 = var1;                 // 通用引用
template<typename T>
void f(std::vector<T>&& param);     // 右值引用
template<typename T>
void f(T&& param);                  // 通用引用
```
<!--more-->

# `T&&`的意义

`T&&`实际上具有两种意义：

- 一种意义是其代表的是右值引用，具有满足移动语义的可能性
- 一种意义是它既可以是右值引用，也可以是左值引用。它可以绑定多种类型`const`或非`const`，`volatile`或非`volatile`等等，所以也将其称为通用引用。

# 通用引用

通用引用出现在两种场合。

一种是作为函数模板的参数：

```cpp
template<typename T>
void f(T&& param);             // param is a universal reference
```

一种是使用`auto`做推导时：

```cpp
auto&& var2 = var1;            // var2 is a universal reference
```

可以看到，通用引用都是出现在有推导的情况下，也就是说它们到底最终是左右还是右值引用，得要更具传入的参数或给其赋值的对象而决定：

```cpp
Widget w;
f(w);                  // lvalue passed to f; param's type is
                       // Widget& (i.e., an lvalue reference)
f(std::move(w));       // rvalue passed to f; param's type is
                       // Widget&& (i.e., an rvalue reference)
```

需要注意的是：**通用引用必须要严格遵从`T&&`的格式**。

比如以下两种都是右值引用：

```cpp
template<typename T>
void f(std::vector<T>&& param);  // param is an rvalue reference

template<typename T>
void f(const T&& param);         // param is an rvalue reference

template<class T, class Allocator = allocator<T>>  
class vector {                                     
public:
  //虽然 push_back 满足 T&&，但是其并没有推导过程
  //而是由对象创建时指明给类的（std::vector<widget> v;）
  //所以它还是一个右值引用
  void push_back(T&& x);
  …
};
```

由于`push_back`并没有推导过程，所以其不是通用引用，但是`emplace_back`因为有推导过程，所以它是通用引用：

```cpp
template<class T, class Allocator = allocator<T>>  // still from
class vector {                                     // C++
public:                                            // Standards
  template <class... Args>
  void emplace_back(Args&&... args);
  …
};
```






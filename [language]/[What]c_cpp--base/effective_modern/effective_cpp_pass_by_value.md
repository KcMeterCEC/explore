---
title: Effective C++ ：如果拷贝和移动的负担很小，那么考虑使用拷贝
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/5/14
updated: 2022/5/14
layout: true
comments: true
---

为了兼顾性能和功能性，有些类会提供拷贝和移动两个版本：
```cpp
class Widget {
public:
  void addName(const std::string& newName)    // take lvalue;
  { names.push_back(newName); }               // copy it
  void addName(std::string&& newName)         // take rvalue;
  { names.push_back(std::move(newName)); }    // move it;
private:
  std::vector<std::string> names;
}; 
```

使用完美转发来实现一个简易版本：
```cpp
class Widget {
public:
  template<typename T>                          // take lvalues
  void addName(T&& newName)                     // and rvalues;
  {                                             // copy lvalues,
    names.push_back(std::forward<T>(newName));  // move rvalues;
  }                                             
};
```

但通用引用可以接收各种类型的参数，这在传入错误的参数时，编译器的报错信息会异常繁琐。其实还有更好的选择。

<!--more-->

如果使用值传递：
```cpp
class Widget {
public:
  void addName(std::string newName)           // take lvalue or
  { names.push_back(std::move(newName)); }    // rvalue; move it
  …
};
```

对于 c++ 11，如果传入的参数是左值，则会进行一次拷贝构造。而如果传入的是右值，则进行的是移动构造：

```cpp
Widget w;

std::string name("Bart");
w.addName(name);                 // call addName with lvalue

w.addName(name + "Jenne");       // call addName with rvalue
```

下面比较这 3 种方法的性能：

- 拷贝构造和移动构造：传入左值时，会进行一次拷贝。传入右值时，会进行一次移动。
- 完美转发构造：完美转发会匹配对应的左值和右值函数，所以性能和方法 1 一样
- 值传递：传入左值时，一次拷贝加一次移动。传入右值时，两次移动
  - 首先是构造形参，传入左值时，会调用拷贝构造函数。传入右值时，会调用移动构造函数（`std::string`具有移动构造函数）。
  - 然后是将形参移动到内部容器中

可以看到，方法 3 相比方法 1，2 多了一次移动操作，如果移动操作耗时很低，那么可以考虑使用方法 3。

因为方法 3 足够简单，阅读性也好。
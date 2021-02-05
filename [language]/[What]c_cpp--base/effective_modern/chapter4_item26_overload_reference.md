---
title: '[What] Effective Modern C++ ：不用创建通用引用的重载函数'
tags: 
- c++
date:  2021/1/28
categories: 
- language
- c/c++
- Effective
layout: true
---
如果创建通用引用的重载函数，但很多时候还是会调用到通用引用函数，这会让人很迷惑。
<!--more-->

# 普通版本

假设我们要实现一个函数，用于存入传递进来的`std::string`，普通版本如下：

```cpp
std::multiset<std::string> names;     // global data structure
void logAndAdd(const std::string& name)
{
  auto now =                          // get current time
    std::chrono::system_clock::now();
  log(now, "logAndAdd");              // make log entry
  names.emplace(name);                // add name to global data
}                                     // structure; 
```

在使用的时候如下：

```cpp
std::string petName("Darla");
logAndAdd(petName);                   // pass lvalue std::string
logAndAdd(std::string("Persephone")); // pass rvalue std::string
logAndAdd("Patty Dog");               // pass string literal
```

第一种情况传入的是左值，且形参`name`也是左值，它以拷贝的方式加入全局变量`names`。

第二种情况创建了临时对象传递给`name`，形参`name`是左值，它以拷贝的方式加入全局变量`names`。但这种情况下，我们实际上是可以以移动的方式加入`names`的。

第三种情况隐式通过字面值字符串创建了临时对象给`name`，与第二种情况一样，它们也是可以以移动的方式加入`names`的。

所以以上第二、三种情况都可以被优化。

# 优化版本

当传入的参数是左值时，使用拷贝。当传入的参数是右值时，使用移动。那么基于通用引用的`std::forward`转换便是一个比较好的方式：

```cpp
template<typename T>
void logAndAdd(T&& name)
{
  auto now = std::chrono::system_clock::now();
  log(now, "logAndAdd");
  names.emplace(std::forward<T>(name));
}
```

使用上面这个函数模板后，第一种情况依然以拷贝方式加入全局变量`names`。而第二、三种情况则是以移动的方式加入`names`。

# 加入重载

下面假设，用户可以查询索引的方式传入字符串，那么`logAndAdd`就需要一个重载版本：

```cpp
std::string nameFromIdx(int idx);      // return name
                                       // corresponding to idx
void logAndAdd(int idx)                // new overload
{
  auto now = std::chrono::system_clock::now();
  log(now, "logAndAdd");
  names.emplace(nameFromIdx(idx));
}
```

那么要调用该函数的方式如下：

```cpp
logAndAdd(22);                         // calls int overload
```

但如果传入一个变量，便会出错：

```cpp
short nameIdx;
…                                      // give nameIdx a value
logAndAdd(nameIdx);                    // error!
```

这是因为，当传入的参数是`short`时，函数模板就将`T`推导成了`short`，虽然`int`版本的重载函数也可以接受`short`类型，但是函数模板的推导结果更为准确。最终`short`无法构造出`std::string`而导致报错。
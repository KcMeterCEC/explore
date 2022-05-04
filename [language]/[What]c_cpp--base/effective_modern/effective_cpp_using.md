---
title: Effective C++ ：using 优于 typedef
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/5/3
updated: 2022/5/3
layout: true
comments: true
---

在 c 中，`typedef`是我经常使用的别名语法。但在 cpp 中，`using`才是更好的选择。

<!--more-->

# 可读性比较

在 cpp 中为了避免命名污染，通常会在使用一个对象、方法时都要输入其完整的命名空间：

```cpp
std::vector<int> val;

std::unique_ptr<std::unordered_map<std::string, std::string>> val;
```

上面第二种写法实在是累，就算使用复制粘贴的方式，以后如果要修改，改起来也非常麻烦。

这种情况下可以使用 `typedef` 或`using`：

```cpp
typedef
  std::unique_ptr<std::unordered_map<std::string, std::string>>
  UPtrMapSS;
using UPtrMapSS =
  std::unique_ptr<std::unordered_map<std::string, std::string>>;
```

上面这两种方式看不出孰优孰劣，但如果在函数指针的情况下：

```cpp
// FP is a synonym for a pointer to a function taking an int and
// a const std::string& and returning nothing
typedef void (*FP)(int, const std::string&);      // typedef
// same meaning as above
using FP = void (*)(int, const std::string&);     // alias
                                                  // declaration
```

很明显，使用`using`的可读性比`typedef`要好得多。

下面再看别名一个模板：

```cpp
//使用 using
template<typename T>                           // MyAllocList<T>
using MyAllocList = std::list<T, MyAlloc<T>>;  // is synonym for
                                               // std::list<T,
                                               //   MyAlloc<T>>
MyAllocList<Widget> lw;                        // client code

template<typename T>
class Widget {
private:
  MyAllocList<T> list;                         // no "typename",
  …                                            // no "::type"
};

//使用 typedef
template<typename T>                     // MyAllocList<T>::type
struct MyAllocList {                     // is synonym for
  typedef std::list<T, MyAlloc<T>> type; // std::list<T,
};                                       //   MyAlloc<T>>
MyAllocList<Widget>::type lw;            // client code

template<typename T>
class Widget {                         // Widget<T> contains
private:                               // a MyAllocList<T>
  typename MyAllocList<T>::type list;  // as a data member
  …
};
```

可以说是高下立判了，并且在使用`typedef`的情况下，还有可能使得编译结果不是自己所预期的……

# 模板

`typedef`对模板的支持度不够，很多时候会导致编译错误，而`using`则不会。
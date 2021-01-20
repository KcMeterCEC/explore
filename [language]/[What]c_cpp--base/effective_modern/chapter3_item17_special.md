---
title: '[What] Effective Modern C++ ：理解特殊的成员函数生成机理'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---
当类没有显示定义以下成员函数时，编译器将会在必要的时候默认生成以下特殊成员函数：
-  默认构造函数：当类没有定义其它构造函数时，编译器会隐式创建（除非使用`default`显示声明）

- 析构函数：隐式的`noexcept`

- 拷贝构造函数：没有移动函数显示定义时，拷贝函数才会被隐式的创建

- 拷贝赋值函数

- 移动构造函数：当没有显示定义移动、拷贝、析构函数时，默认移动函数才会被隐式的创建

- 移动赋值函数
  <!--more-->
生成的特殊函数是隐含的`public`和`inline`的，但大部分情况下都是非虚函数。
> 只有当一个类继承自基类，基类的析构函数是虚函数时，生成派生类的析构函数才也是虚函数

# 移动构造与移动赋值的特殊性

## 逐字节的移动

```cpp
class Widget {
public:
  …
  Widget(Widget&& rhs);              // move constructor
  Widget& operator=(Widget&& rhs);   // move assignment operator
  …
};
```

只有当使用移动构造和移动赋值，并且被操作的对象允许移动时，编译器才会使用其默认移动构造与移动赋值。

> 移动的时候就是很忠实的将一个对象的非静态成员变量逐字节的移动过去。
>
> 拷贝构造和拷贝赋值则是很忠实的将对象的非静态成员变量逐字节拷贝过去。

## 两个并不独立

需要注意的是：这两个移动函数并不是独立的，一旦用户定义了其中任意一个函数，另一个函数就算不显示定义，编译器也不会在需要的时候主动生成了。

> 拷贝构造与拷贝赋值确实独立的，就算用户只定义了其中一个，一旦需要使用另一个函数时，编译器也会默认创建。

## 拷贝与移动

一旦一个类显示的定义了拷贝构造或拷贝赋值函数，移动构造和移动赋值函数便不会被隐式的创建了。

其逻辑在于：既然显示的创建了拷贝操作，那就说明逐个字节的拷贝是不能满足要求的，那么进而说明逐个字节的移动也是不能满足要求的。

同理，当一个类显示的定义了移动操作，那么编译器也不会隐式的创建拷贝操作了。理由同上。

# The Big Three

基于以上的基础认识，就有一个基本的类定义法则：

> 一旦定义了拷贝构造函数、拷贝赋值函数、析构函数中的任何一个，那么这 3 个函数都应该被显示的定义。

这是因为只要显示定义了这 3 个函数中的其中一个，必然会涉及到一些内存管理，这是编译器的默认操作所不能完成的。



所以移动操作只有当以下 3 个条件同时满足时，编译器才会隐式的构建：

1. 没有显示定义拷贝操作
2. 没有显示定义移动操作
3. 没有显示定义析构函数

# default 修饰

当需要依赖编译器隐式构建的特殊函数时，使用`default`进行修饰不仅可以更能展现自己的意图，更能避免一些坑：

```cpp
class Base {
public:
  virtual ~Base() = default;                // make dtor virtual
  Base(Base&&) = default;                   // support moving
  Base& operator=(Base&&) = default;
  Base(const Base&) = default;              // support copying
  Base& operator=(const Base&) = default;
  …
};
```

比如下面这个类：

```cpp
class StringTable {
public:
  StringTable()
  { makeLogEntry("Creating StringTable object"); }     // added
  
  ~StringTable()                                       // also
  { makeLogEntry("Destroying StringTable object"); }   // added
  …                                     // other funcs as before
private:
  std::map<int, std::string> values;    // as before
};
```

由于显示的定义了析构函数，编译器有可能不会隐式创建移动构造和移动拷贝函数。

那么在实际需要移动的场景，是会使用拷贝操作来完成的，这效率就大打折扣了。

比较简单的解决办法就是使用`dafault`显示声明移动操作。

# 模板的特殊行

当类中以函数模板的形式定义拷贝构造和拷贝赋值时，编译器还是会隐式的创建默认和移动操作函数：

```cpp
class Widget {
  …
  template<typename T>                // construct Widget
  Widget(const T& rhs);               // from anything
  template<typename T>                // assign Widget
  Widget& operator=(const T& rhs);    // from anything
  …
};
```


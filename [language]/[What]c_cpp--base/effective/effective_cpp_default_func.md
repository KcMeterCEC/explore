---
title: Effective  C++ ：认识编译器的默认生成函数
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/4/13
updated: 2022/4/14
layout: true
comments: true
---

编译器默认会为一个类提供（如果它们需要被使用的话）：

- 默认构造函数：如果类编写了构造函数，则编译器就不会自动提供默认构造函数了
  + 使用 `default` 显示声明也可以在有其他构造函数的情况下，让编译器产生默认构造函数
- 拷贝构造函数：**没有移动函数显示定义时，拷贝函数才会被隐式的创建**。其单纯地将每一个数据成员进行拷贝
  + 如果数据成员中的对象具有它自己的拷贝构造函数，则也会调用它
- 拷贝赋值函数：单纯地将每一个数据成员进行拷贝
  + 如果数据成员中的对象具有它自己的拷贝赋值函数，则也会调用它
- 析构函数：隐式的`noexcept`
- 移动构造函数：当没有显示定义移动、拷贝、析构函数时，默认移动函数才会被隐式的创建
- 移动赋值函数

生成的特殊函数是隐含的`public`和`inline`的，但大部分情况下都是非虚函数。
> 只有当一个类继承自基类，基类的析构函数是虚函数时，生成派生类的析构函数才也是虚函数

<!--more-->

# 拷贝与赋值

但有些时候，并不是都可以使用默认拷贝构造和拷贝赋值函数。

比如类中有指针的情况下，不能简单的进行成员变量拷贝就行了，还要拷贝指针所指向的内存。
> 这个时候就需要用户自己定义拷贝构造和拷贝赋值

还有一种情况，是编译器无法生成拷贝构造和拷贝赋值，在比如下面这种情况：

``` cpp
#include <iostream>
#include <string>

class Hello {
    public:
        Hello(std::string& name): name_(name) {

        };
    private:
        std::string& name_;
};

int main(void) {
    std::string name1("hello1");
    std::string name2("hello2");

    Hello hello1(name1);
    Hello hello2(name2);

    // 这里想使用拷贝赋值函数，但是如果是单纯的位拷贝，
    // 相当于要将对象 hello1 中的引用改变，这就和引用的概念相冲突了
    // 编译器就不会为这个类生成默认的拷贝赋值函数
    hello1 = hello2;

    return 0;
}
```

编译时错误如下：

``` shell
hello.cc:23:12: error: object of type 'Hello' cannot be assigned because its copy assignment operator is implicitly deleted hello1 = hello2;
                 ^
hello.cc:10:22: note: copy assignment operator of 'Hello' is implicitly deleted because field 'name_' is of reference type 'std::string &' (aka 'basic_string<char> &') std::string& name_;
```

# 移动构造与移动赋值的特殊性

## 逐字节的移动

``` cpp
class Widget {
public:
  …
  Widget(Widget&& rhs);              // move constructor
  Widget& operator=(Widget&& rhs);   // move assignment operator
  …
};
```

只有当使用移动构造和移动赋值，并且被操作的对象允许移动时，编译器才会生成其默认移动构造与移动赋值。

> 移动的时候就是很忠实的将一个对象的非静态成员变量逐字节的移动过去。
>
> 拷贝构造和拷贝赋值则是很忠实的将对象的非静态成员变量逐字节拷贝过去。

## 两个并不独立

需要注意的是：这两个移动函数并不是独立的，一旦用户定义了其中任意一个函数，另一个函数如果不显示定义，编译器也不会在需要的时候主动生成。

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

``` cpp
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
如上代码描述，基类的析构需要被声明为`virtual`才能在多态析构时行为正确，如果析构什么事情都不用做，那么使用`default`是个简而美的办法。

比如下面这个类：

``` cpp
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

# 模板的特殊行为

当类中以函数模板的形式定义拷贝构造和拷贝赋值时，编译器还是会隐式的创建默认和移动操作函数：

``` cpp
class Widget {
  …
  template<typename T>                // construct Widget
  Widget(const T& rhs);               // from anything
  template<typename T>                // assign Widget
  Widget& operator=(const T& rhs);    // from anything
  …
};
```
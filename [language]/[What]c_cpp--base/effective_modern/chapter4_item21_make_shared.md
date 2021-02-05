---
title: '[What] Effective Modern C++ ：make_shared 和 make_unique 优于使用 new'
tags: 
- c++
date:  2021/1/25
categories: 
- language
- c/c++
- Effective
layout: true
---
`std::make_shared` 是 c++11 的一部分，但是`std::make_unique`是在 c++14 才被加入标准的。如果要在 c++ 11 中使用，可以自己定义一个简易版本：
```cpp
template<typename T, typename... Ts>
std::unique_ptr<T> make_unique(Ts&&... params)
{
  return std::unique_ptr<T>(new T(std::forward<Ts>(params)...));
}
```
<!--more-->

# 为什么要使用`make`函数

## 简洁性

```cpp
auto upw1(std::make_unique<Widget>());      // with make func
std::unique_ptr<Widget> upw2(new Widget);   // without make func
auto spw1(std::make_shared<Widget>());      // with make func
std::shared_ptr<Widget> spw2(new Widget);   // without make func
```

从上面这段代码可以看出，使用`make`函数，便可以使用`auto`来推导对象的类型。

而使用`new`来创建对象的话，就需要显示的写明对象的类型，这在以后修改类型时，就有点麻烦。

## 保证安全性

比如有如下函数定义：

```cpp
void processWidget(std::shared_ptr<Widget> spw, int priority);
```

并且使用`new`来传入对象：

```cpp
processWidget(std::shared_ptr<Widget>(new Widget),  // potential
              computePriority());                   // resource
                                                    // leak!
```

这种情况下就有可能造成内存泄漏。

`shared_ptr`的创建一定要在`new`之后，以获取`new`的地址进行管理，那么正常的流程应该是：

1. `new`先创建一个 Widget 对象
2. 调用`shared_ptr`的构造函数，获取 Widget 对象的地址进行管理
3. 执行 computePriority() 函数

但如果编译器进行了优化，就有可能会执行下面这个顺序：

1. `new`先创建一个 Widget 对象
2. 执行 computePriority() 函数
3. 调用`shared_ptr`的构造函数，获取 Widget 对象的地址进行管理

假设在执行第二步时，computePriority() 抛出了一个异常，那么第三步就无法执行，第一步申请的内存无法释放就造成了内存泄漏。

使用`make`函数便可以避免此问题：

```cpp
processWidget(std::make_shared<Widget>(),   // no potential
              computePriority());           // resource leak
```

因为使用`make`函数就将步骤变成了两步，这样无论谁先执行，都能保证不会造成内存泄漏。

## 效率

对于`shared_ptr`要管理一段资源，除了要申请该资源的内存还要申请对应的 control block。

如果使用`new`来创建对象资源，那么申请资源就要分为两步：

```cpp
std::shared_ptr<Widget> spw(new Widget);
```

如果使用`make`函数，那就将两个步骤合并为一个步骤，提高了效率：

```cpp
auto spw = std::make_shared<Widget>();
```

# `make`函数的缺陷

## `delete`函数

使用`make`函数时，并不能定义`delete`函数，这种情况下只能使用`new`来完成：

```cpp
auto widgetDeleter = [](Widget* pw) { … };
std::unique_ptr<Widget, decltype(widgetDeleter)>
  upw(new Widget, widgetDeleter);
std::shared_ptr<Widget> spw(new Widget, widgetDeleter);
```

所以，在之前的安全性讨论中，如果需要新建`delete`方法，那么就需要将对象的创建分为单独的一行来实现：

```cpp
std::shared_ptr<Widget> spw(new Widget, cusDel);
processWidget(spw, computePriority()); 
```

## 初始化的限制

使用`make`函数调用的是括号初始化：

```cpp
auto upv = std::make_unique<std::vector<int>>(10, 20);
auto spv = std::make_shared<std::vector<int>>(10, 20);
```

以上代码都是创建有 10 个元素，每个元素值为 20 的 vector。

如果想使用列表初始化，除了使用`new`以外，还可以使用`auto`进行推导：

```cpp
// create std::initializer_list
auto initList = { 10, 20 };
// create std::vector using std::initializer_list ctor
auto spv = std::make_shared<std::vector<int>>(initList);
```

## 自定义类

有些类会定义自己的申请和释放方法，但是这些方法往往自会计算自身对象的大小而忽略了 control block 的大小，这种情况下也不能用`make`函数。

## 占用很大的申请

前面讲过，使用`weak_ptr`来判定`shared_ptr`所管理的资源是否已经释放。

但实际上，是在 control block 中也有一个 weak count 来表明`weak_ptr`，所以只有当`weak_ptr`被销毁时，相关内存资源才算真的被释放完了。

由于`make`函数申请资源内存和 control block 是一个整体，那么在有`weak_ptr`的情况下，即使`shared_ptr`已经被完全销毁了，但是其资源的内存及 control block 的内存都既然存在，直到`weak_ptr`被销毁。

如果`make`函数申请的内存很大，那么在一些应用场景下就有可能出现其它代码申请不到内存的情况。

如果使用`new`就不会有这个问题，因为对象资源和 control block 的内存不是一个整块被申请的，所以当`shared_ptr`被完全销毁了，对象的资源也会被释放掉。仅需要保留 control block 给`weak_ptr`使用即可。
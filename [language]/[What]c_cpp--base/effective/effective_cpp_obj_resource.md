---
title: Effective  C++ ：管理资源
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/4/17
updated: 2022/4/17
layout: true
comments: true
---

这里的资源主要是：内存、文件描述符、互斥锁、数据库连接、socket 等，一旦不使用它们，都要归还给系统。

<!--more-->

# 以对象管理资源

首先在编写一个类的时候，就需要在它的析构函数中仔细整理它需要释放的资源。

而在使用对象时，需要使用 RAII 类来管理这些资源，比如智能指针。

编写 RAII 类时，除了管理原始资源外，还需要提供接口`get()`来获取原始资源。

因为一些 C API 是需要操作原始资源的。

# 小心资源管理类中的拷贝行为

假设用一个类以 RAII 的方式来管理互斥量：

- 在构造函数中获取锁
- 在析构函数中释放锁

那么就这样定义：

```cpp
class Lock {
  public:
    explicit Lock(Mutex* pm) : mutex_(pm) {
        lock(mutex_);
    }
    ~Lock() {
        unlock(mutex_);
    }
  private:
    Mutex* mutex_ = nullptr;  
};
```

然后这样使用：

```cpp
Mutex m;
{
    //传入锁的地址同时创建 RAII 对象，即可获得锁
    Lock m1(&m);
    // ...
}
// 退出区块后，调用 m1 析构函数释放锁
```

但是如果对 RAII 对象进行了拷贝：

```cpp
Mutex m;
{
    //传入锁的地址同时创建 RAII 对象，即可获得锁
    Lock m1(&m);
    // 调用拷贝构造函数，如果拷贝构造函数里面也获取锁，便会造成死锁
    Lock m2(m1);
}
// 如果拷贝构造里面没有获取锁，但是析构里面也会释放锁，就会出现重复释放
```

对此的应对方法有以下几种：

## 禁止拷贝

可以对拷贝构造和拷贝赋值函数使用`delete`关键字，以禁止拷贝操作的合理性。

## 使用引用计数

将需要被保护的资源使用`shared_ptr`管理起来，便可以基于引用计数来完成合理申请和释放。

> 需要注意的是：`shared_ptr`的默认行为在计数为 0 时是删除其指定资源，而对于像互斥量这样的资源。**我们希望的是释放锁，而不是删除锁。**
>
> 这种情况下，就需要为`shared_ptr`指定删除器。

```cpp
class Lock {
  public:
    // 指定 shared_ptr 的删除器是 unlock 操作
    explicit Lock(Mutex* pm) : mutex_(pm, unlock) {
        lock(mutex_.get());
    }
    ~Lock() {
		// 有了智能指针，析构函数就不需要主动释放了
    }
  private:
    std::shared_ptr<Mutex> mutex_;  
};
```

## 复制底部资源

对类管理的资源进行深拷贝，也可以避免这个问题。

比如对互斥量资源进行深拷贝，相当于又新建了一个互斥量。

## 转移底部资源的拥有权

这就相当于使用了移动语义，以转移资源的所有权。

# 使用 `new` 和 `delete` 时要采取相同形式

`new`和`delete`要成对使用，`new[]`和`delete[]`也是要一一对应成对使用。

> 如果 new[] 对应 delete，那 delete 操作很可能因为不知道应该释放多少资源而导致内存泄漏。
>
> 反之，如果 new 对应 delete[]，那 delete 操作可能误认为会多次释放而释放了其他不属于自己的资源。

# 以独立语句将 newed 对象置入智能指针

假设有一个函数接口是这样设计的：

```cpp
void ProcessWidget(std::shared_ptr<Wdiget> pw, Window win);
```

然后进行调用时是这样的：

```cpp
ProcessWidget(std::shared_ptr<Widget>(new Widget), win);
```

那么编译器在进行参数传递时，有可能会以以下顺序进行传递：

- 申请内存，使用`new Widget`
- 创建临时对象 `win`
- 将第一步的地址传递给智能指针

那么假设，在创建临时对象`win`是发生了异常而导致中断操作，那么第一步所申请的内存就没有被智能指针所接管。造成了**很难排查的内存泄漏**！

所以应该养成好的习惯：先创建智能指针，再进行调用：
> 或者使用 `std::make_unique` 和 `std::make_shared 来替代` `new`。

```cpp
std::shared_ptr<Widget> pw(new Widget);

ProcessWidget(pw, win);
```


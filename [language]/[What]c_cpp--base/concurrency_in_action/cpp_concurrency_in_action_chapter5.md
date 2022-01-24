---
title: '[What] C++ Concurrency in Action 2nd ：C++ 内存模型及原子操作'
tags: 
- c++
date:  2021/10/25
categories: 
- language
- c/c++
- Concurrency
layout: true
---
这一章从未涉及，应该还需要看其他的书籍来弥补一些空缺知识。
<!--more-->

# 基础内存模型

内存模型主要指两个方面：

- 结构上的：指的是对象在内存中的组织方式
- 并发上的：指的是内存的排布方式对并发访问的影响



关于对象的一些概念需要谨记：

1. 所有的变量都是对象，不管是 Plain 变量还是类。

   > 这里的对象是以其内存的放置方式来看的

2. 所有的对象都会占有内存，只是占有多少的区别

3. 只要有两个及以上的线程的会访问同一块内存区域，且只要有一个线程会写该区域那就会出现 data race。

# c++ 所支持的原子操作

在头文件`<atomic>`中有标准支持的[原子操作类型](https://en.cppreference.com/w/cpp/atomic)，实际上用户完全可以使用 mutex 来完成多个操作的原子性。

但标准支持的原子操作类型，具有`is_lock_free()`成员函数：

- 当返回为`true`时，则代表可以以汇编指令的方式支持原子性，也就是无锁编程
- 当返回为`false`时，则需要编译器及库来辅助实现原子性

使用只有当原子操作优于 mutex 时才使用原子操作，如果一个原子操作其内部还是使用了 mutex，那还不如用 mutex 来实现。

在 C++17，所有的原子操作类型都具有静态函数`is_always_lock_free()`，这个函数用于表示一个原子操作是否对所有的硬件平台都满足无锁编程。有些类型仅在部分平台所支持的指令集中，才能实现无锁编程。这种情况下该类型的`is_always_lock_free()`将返回 `false`。

标准库还提供了[ATOMIC_xxx_LOCK_FREE](https://en.cppreference.com/w/cpp/atomic/atomic_is_lock_free)宏以表示原子操作类型对无锁编程的支持度：

- 0：不支持无所编程
- 1：仅在部分平台下支持
- 2：任何平台下都支持

`std::atomic_flag`是一个例外，它没有提供`is_lock_free()`成员函数，因为它总是被编译器所保证是 lock free 的布尔类型。

> 对于它的操作也不是简单的赋值，而是使用[test_and_set](https://en.cppreference.com/w/cpp/atomic/atomic_flag/test_and_set)来置 1，使用[clear](https://en.cppreference.com/w/cpp/atomic/atomic_flag/clear)来完置 0。

其他的类型都可以使用`std::atomic<>`的方式实例化对象，也可以通过`atomic_bool`这种 typedef 来快捷使用。

除此之外，atomic 还支持通过枚举`std::memory_order`内存顺序的设定，如果不指定则默认为` std::memory_order_seq_cst`，不同的操作方式其可指定的内存顺序是不同的：

- `Store`：`memory_order_relaxed`,`memory_order_release`,`memory_order_seq_cst`
- `Load`：`memory_order_relaxed`,`memory_order_consume`,`memory_order_acquire`,`memory_order_seq_cst`
- `Read-modify-write`:`memory_order_relaxed`,`memory_order_consume`,`memory_order_acquire`,`memory_order_release`,`memory_order_acq_rel`,`memory_order_seq_cst`

**需要注意的是：**所有的原子操作类型都不支持拷贝构造及拷贝赋值。

> 因为当进行拷贝构造或拷贝赋值时，就有读和写两个操作，而这两个操作是无法保证它们是原子性的！

## std::atomic_flag

`std::atomic_flag`是标准库所支持的最简单的原子操作类型，它是一个布尔类型的标志，只有`set`和`clear`两种状态。

`std::atomic_flag`对象的初始化**必须**是以`ATOMIC_FLAG_INIT`来**等号初始化**，以设置其状态为`clear`。

```cpp
#include <atomic>
 
std::atomic_flag static_flag = ATOMIC_FLAG_INIT; // static initialization,
// guaranteed to be available during dynamic initialization of static objects.
 
int main() {
    std::atomic_flag automatic_flag = ATOMIC_FLAG_INIT; // guaranteed to work
//    std::atomic_flag another_flag(ATOMIC_FLAG_INIT); // unspecified
}
```

初始化以后，对此标志就只有`clear()`和`test_and_set()`两种操作了，且这两种操作都可以设置内存顺序。

其中`clear()`属于`Store`操作，而`test_and_set()`属于`Read-modify-write`操作，对应前面可以选择对应的内存顺序。

`std::atomic_flag`还可以被包装成自旋锁：由于`test_and_set()`会返回之前的设置值，那么当返回的值为`false`时，则代表其他线程已经释放了该锁：

```cpp
class spinlock_mutex {
    std::atomic_flag flag;
public:
    spinlock_mutex():
    flag(ATOMIC_FLAG_INIT) {
    }
    void lock() {
		// 如果返回值为 ture ,则代表其他线程还没有释放该标志
        while (flag.test_and_set(std::memory_order_acquire));
    }
    void unlock() {
        flag.clear(std::memory_order_release);
    }
};
```

由于上面这个类已经提供了`lock()`和`unlock()`方法，那么它就可以被用于`std::lock_guard`类实现 RAII 操作：

```cpp
#include <thread>
#include <vector>
#include <iostream>
#include <atomic>
#include <mutex>

class spinlock_mutex {
    std::atomic_flag flag;
public:
    spinlock_mutex():
    flag(ATOMIC_FLAG_INIT) {
    }
    void lock() {
        while (flag.test_and_set(std::memory_order_acquire));
    }
    void unlock() {
        flag.clear(std::memory_order_release);
    }
};

static spinlock_mutex sp_mutex;

void f(int n) {
    for (int i = 0; i < 40; ++i) {
        std::lock_guard<spinlock_mutex> lk(sp_mutex);

        std::cout << "t[" << n << "]: "
            << i << " ";
    }
    std::cout << "\n";
}

int main(void) {
    std::vector<std::thread> v;

    for (int i = 0; i < 10; ++i) {
        v.emplace_back(f, i);
    }

    for (auto& t : v) {
        t.join();
    }

    return 0;
}
```

## std::atomic\<bool>

`std::atomic<bool>`类型虽然也只有两种状态，但是比`std::atomic_flag`操作起来就更加自然。

它可以被普通的`true`，`false`所构造和赋值：

```cpp
std::atomic<bool> b(true);
b = false;
```

相对比`std::atomic_flag`，`std::atomic<bool>`具有如下操作：

- `store()`：用于设置布尔值
- `load()`：用于读取布尔值
- `exchange()`：设定值并返回上次的值，这是一个读-修改-写的操作

除此之外，还有一个 compare exchange 操作，该操作支持的前两个参数是`expected`和`desired`。

其操作逻辑为：

- 当当前原子变量的值与`expected`值一致时，则将原子变量的值修改为`desired`的值，并且返回`true`以表示操作成功。
- 当当前原子变量的值与`expected`值不一致时，则将`expected`的修改为和原子变量的值一样，并返回`false`以表示操作失败。

该操作扩展为两个成员函数`compare_exchange_weak()`和`compare_exchange_strong()`。

`compare_exchange_weak()`并不能保证整个操作的原子性，比如：

- `expected`的值为`false`，而`desired`的值为`true`，此时原子变量的值也为`false`。
- 由于原子变量值与`expected`值一致，则将原子变量的值修改为`true`，并预备返回`true`以示修改成功
- 而此时另一个线程的操作该原子变量，最终导致返回的值为`false`

这就会出现返回值为`false`，但是`expected`的值仍然没有被改变的现象。

应对方法就是使用`while`来检查返回值和`expected`：

```cpp
bool expected = false;
extern atomic<bool> b;
// 要么修改成功，要么修改失败而 expected 被修改为 true 才退出循环以保证操作完整性
while (!b.compare_exchange_weak(expected,true) && !expected);
```

`compare_exchange_strong()`则是可以保证返回值的一致性，而不会被其他线程所破坏。

使用 compare exchange 操作的一个用途是，用来检查是否有其他线程修改了原子变量：

> 一开始将 expected 的值和原子变量的值设为一样。
>
> 那么如果没有其他线程修改这个值，其返回将会一直为 true。
>
> 如果其他线程修改了这个值，则返回将会为 false，且可以通过 expected 来获取到被修改的值是多少。

两种 compare exchange 操作都可以设置两个内存顺序操作，以对应 true 和 false 两种情况。

## std::atomic<T*>

`std::atomic<T*>`是指指向类型 T 的指针为原子变量，这种类型的变量相比`std::atomic<bool>`增加了指针的算术运算操作。

通常的`+=`,`-=`,`++`,`--`是支持的，还增加了`fetch_add()`和`fetch_sub()`这类成员函数。

> `fetch_add()`和`fetch_sub()`会返回调整之前的值，而算术运算符则是根据情况返回之前的还是现在的值。

```cpp
class Foo {
};
Foo some_array[5];
std::atomic<Foo*> p(some_array);
// p 往后移动两个位置，但返回调整之前的值
Foo* x = p.fetch_add(2);            
assert(x == some_array);
assert(p.load() == &some_array[2]);
// p 往前移动一个位置，并且返回调整之后的值
x = (p -= 1);                         
assert(x == &some_array[1]);
assert(p.load() == &some_array[1]);
```

## 整型的原子操作

整型的原子操作除了具有指针类型原子变量的操作外，还有与或非等这些逻辑运算操作，就和操作正常的整型一样。

**但是：它们没有乘、除、移位这种可能会丢失数据的操作。**

## std::atomic<>






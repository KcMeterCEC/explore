---
title: '[What] Effective  C++ ：定制 new 和 delete'
tags: 
- c++
date: 2021/9/20
categories: 
- language
- c/c++
- Effective
layout: false
---

为了使得 c++ 程序具有最佳的效率，有些时候需要定制 new 和 delete。

<!--more-->

# 了解 new-handler 行为

当`operator new`无法满足内存分配需求时，它会抛出异常。但在抛出异常前，还会先调用客户指定的错误处理函数`new-handler`。

而这个处理函数，只需要调用`std::set_new_handler`设置即可：

```cpp
#include <new>
#include <iostream>

void OutOfMem(void) {
    std::cerr << "Unable to satisfy request for memory!\n";
	// 要主动退出，否则会重复触发该函数
    std::abort();
}


int main()
{
    std::set_new_handler(OutOfMem);

    int* bit_data_array = new int[9999999999UL];


    return 0;
}
```

一个设计良好的`new-handler`必须做以下事情：

- 让更多内存可被使用：这样使用`operator new`下一次分配可能成功。

  > 一个做法是程序一开始执行就分配一大块内存，然后当`new-handler`第一次被调用时，将它们释放还给程序使用。

- 安装另一个`new-handler`：如果当前函数无法释放更多内存，那么它应该使用`std::set_new_handler`让另一个`new-handler`来处理

- 卸载`new-handler`：或者是当前函数无法处理，那么就将`null`传给`std::set_new_handler`，以让标准库执行默认行为

- 抛出`bad_alloc`：抛出该异常，以让标准库来处理。

- 不返回：避免重复调用，使用`std::abort()`或`std::exit()`

# 了解 `new`和 `delete`的合理替换时机

一般以下情况会需要替换标准库提供的默认`new`和`delete`：

- 用来检测运用上的错误：定制的`new`和`delete`可以用于检查内存泄漏、double free 等常见错误
- 进行统计：在定制操作中，加入一些监控信息。使得可以统计当前程序对内存的使用特性。
- 提高性能：定制特化版本，以提高针对当前场景性能更好的分配和释放处理


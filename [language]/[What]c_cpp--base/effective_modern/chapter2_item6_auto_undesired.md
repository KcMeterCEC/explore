---
title: [What] Effective Modern C++ ：auto 初始化可能会遇到的坑
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---



理解了 `auto`的推导原则后，和`auto`的便利性后，也需要注意`auto`推导可能会遇到的问题。

<!--more-->

# 类型的隐式转换

假设要从一个`std::vector<bool>`类型容器中获取一个结果，可以像如下的编写方式：

```cpp
#include <iostream>
#include <vector>

std::vector<bool> GetResult(void){
    std::vector<bool> ret = {0, 0, 1, 1, 1};

    return ret;
}

int main()
{
    bool ret = GetResult()[2];

    std::cout << "ret value is " << ret << "\n";

    return 0;
}
```

运行的结果是：

> ret value is 1

这个代码验证无误，但是为了在获取返回值时更为智能一点，我们将返回类型用`auto`进行推导：

```cpp
auto ret = GetResult()[2];
```

在 MSVC 环境下运行便会报错：

> Expression:cannot dereference value-initialized vector<bool> iterator.

接下来我们主动让编译器在编译时报错来查看该`auto`推导的类型：

```cpp
#include <iostream>
#include <vector>

template<typename T>
class TypeDisplay;

std::vector<bool> GetResult(void){
    std::vector<bool> ret = {0, 0, 1, 1, 1};

    return ret;
}

int main()
{
    auto ret = GetResult()[2];

    TypeDisplay<decltype(ret)> type;

    std::cout << "ret value is " << ret << "\n";

    return 0;
}
```

编译时报错如下：

> error: implicit instantiation of undefined template 'TypeDisplay<std::_Vb_reference<std::_Wrap_alloc<std::allocator<unsigned int> > > >'

按照正常理解，`auto`应该推导出`bool`类型才是，结果却是`std::vector<bool>::reference`。



大部分情况下，`std::vector::operator[]`会返回该容器元素的引用，但是由于上面定义的容器元素类型为`bool`。

这在底层的表示为，一个`bool`占用一个`bit`，而**c++ 是禁止返回一个位的引用的**。

所以实际上`bool ret = GetResult()[2]`的操作顺序是：

1. 返回`std::vector<bool>::reference`类型
2. 取第 3 位的值，隐式转换为`bool`类型

而`auto ret = GetResult()[2]`得到的类型确是`std::vector<bool>::reference`，实际上这个步骤比想象的复杂：

1. `GetResult()`函数返回的是`std::vector<bool>`的副本，也就是一个临时对象`tmp`
2. 接下来`operator[]`由于不能返回位的引用，所以得到的是`std::vector<bool>::reference`对象
3. 这个对象实际上是指向`bool`的指针，接下来再索引到下标为 2 的地址处，也就指向了第 3 位
4. `ret`得到的就是第 3 位的地址（在上面正确的结果中，如果进行了隐式转换，是将第 3 位的值拷贝了一次，而此处并未拷贝）
5. `tmp`临时对象内存被释放，最终`std::cout`语句所获取的就是个野指针！


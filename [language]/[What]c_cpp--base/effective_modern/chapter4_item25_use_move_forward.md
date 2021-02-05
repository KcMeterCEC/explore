---
title: '[What] Effective Modern C++ ：对右值引用使用 std::move，对通用引用使用 std::forward'
tags: 
- c++
date:  2021/1/28
categories: 
- language
- c/c++
- Effective
layout: true
---
当形参被声明为右值引用时，意味着传入的实参需要是右值引用，并且该参数是可移动的。既然目的如此明确，那么使用`std::move`是正确的选择：
```cpp
class Widget {
public:
  Widget(Widget&& rhs)               // rhs is rvalue reference
  : name(std::move(rhs.name)),
    p(std::move(rhs.p))
    { … }
  …
private:
  std::string name;
  std::shared_ptr<SomeDataStructure> p;
};
```
但如果形参被声明为通用引用时，则意味着实参有可能是右值引用，该参数有可能可被移动。那么对应的使用`std::forward`是正确的选择：
```cpp
class Widget {
public:
  template<typename T>
  void setName(T&& newName)               // newName is
  { name = std::forward<T>(newName); }    // universal reference
  …
};
```

<!--more-->

# 如果将`std::move`应用于通用引用会怎样？

如下代码所示：

```cpp
#include <vector>
#include <iostream>
#include <array>
#include <memory>

class Widget {
public:
  template<typename T>
  void setName(T&& newName)         // universal reference
  { name = std::move(newName); }    // compiles, but is
                                   // bad, bad, bad!
private:
  std::string name;
};

int main(void){

    std::string str = {"hello,world\n"};

    std::cout << "The contents of str before move : " << str;

    Widget widget{};

    widget.setName(str);

    std::cout << "The contents of str after move : " << str;


    return 0;
}
```

其输出为：

> The contents of str before move : hello,world
> The contents of str after move : 

作为`widget`的使用者，其本意是将`str`的内容拷贝一份给`widget`，但是由于使用了`std::move`进行无条件转换。最终`str`指向的内容被移动到了`widget`的私有成员`name`中。

但作为使用这还以为`str`中依然是原来的内容，如果继续操作`str`便会遇到未定义的错误！

# 对返回值使用`std::move`或`std::forward`

## 好心办坏事

当满同时满足以下两个条件时，c++ 会应用返回值优化策略（return value optimization，RVO）：

1. 局部变量的类型和函数的返回类型一致
2. 当前局部变量就是被返回的变量

那么编译器会尝试使用移动语义，以提高返回变量的效率。

假设在满足 RVO 的前提下，用户主动使用`std::move`转换返回的变量会怎么样？

```cpp
Widget makeWidget()        
{
  Widget w;
  …
  return std::move(w);     
} 
```

其实这是会起反作用的，因为使用`std::move`转换后，返回的类型便是`Widget`的右值引用了，这反而影响了编译器的判断（不满足条件 2）而最终使用拷贝的方式返回。

## 正确的使用场景

那么哪种情况下比较适合主动使用`std::move`或`std::forward`呢？

也就是返回的变量不满足上面两个条件时，可以主动使用移动语义：

```cpp
Matrix                                        // by-value return
operator+(Matrix&& lhs, const Matrix& rhs)
{
  lhs += rhs;
  return std::move(lhs);                      // move lhs into
}                                             // return value
```

上面这个`+`重载函数是以值的方式返回，参数`lhs`是一个通用引用。

这种情况下使用`std::move`转换一下，编译器便会尝试使用移动语义来提高效率：

- 如果`Matrix`类支持移动操作，那么就会调用移动操作。
- 如果`Matrix`类不支持移动操作，那么就会使用拷贝操作

```cpp
template<typename T>         
Fraction                           // by-value return
reduceAndCopy(T&& frac)            // universal reference param
{
  frac.reduce();
  return std::forward<T>(frac);    // move rvalue into return
}                                  // value, copy lvalue
```

当参数`frac`是左值时，那么就使用拷贝操作。

当参数`frac`是右值时，则将其转换为右值引用，并尝试使用移动操作。


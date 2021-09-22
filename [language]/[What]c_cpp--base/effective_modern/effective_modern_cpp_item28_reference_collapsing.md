---
title: '[What] Effective Modern C++ ：理解引用折叠'
tags: 
- c++
date:  2021/9/22
categories: 
- language
- c/c++
- Effective
layout: true
---

如果一个模板函数的形参是通用引用，那么：
1. 如果传入的实参是左值，那么推导出来的形参就是左值引用
2. 如果传入的实参是右值，那么推导出来的形参就是**不带引用的普通形参**
```cpp
Widget widgetFactory();     // function returning rvalue
Widget w;                   // a variable (an lvalue)
func(w);                    // call func with lvalue; T deduced
                            // to be Widget&
func(widgetFactory());      // call func with rvalue; T deduced
                            // to be Widget
```

<!--more-->

# 引用折叠

但是为什么在里面加上`std::forward`却又可以区分出来左值引用和右值引用？

```cpp
#include <vector>
#include <iostream>
#include <string>
#include <utility>

void SomeFunc(std::vector<int>& param) {
    std::cout << "This is lvalue!\n";
}

void SomeFunc(std::vector<int>&& param) {
    std::cout << "This is rvalue!\n";
}

template<typename T>
void Func(T&& param) {
    SomeFunc(std::forward<T>(param));
}

int main(void){


    std::vector<int> v1{1};

    Func(v1);
    Func(std::vector<int>(2));

    return 0;
}
```



上面的推导逻辑，在编译器内部就叫做引用折叠（`reference collapsing`）,也就是两个引用化简为一个引用。

既然引用分为左值和右值引用，那么就会有 4 种组合：

1. 两个左值引用
2. 一个左值引用，一个右值引用
3. 一个右值引用，一个左值引用
4. 两个右值引用

其化简原则如下：

- 只要其中一个是左值引用，那么结果就是左值引用
- 只有两个都是右值引用时，结果才是右值引用

好了，现在来看`std::forward`的简易实现：

```cpp
template<typename T>                                // in
T&& forward(typename                                // namespace
              remove_reference<T>::type& param)     // std
{
  return static_cast<T&&>(param);
}
```

下面来推导传入左值的情况，当传入的是`v1`按照前面的规则，则`param`会被推导为`std::vector<int>&`，那么对于`forward`就是：

```cpp
std::vector<int>& && forward(typename                                
              remove_reference<std::vector<int>&>::type& param)     
{
  return static_cast<std::vector<int>& &&>(param);
}
```

那么按照引用折叠的规则，最终返回的就是`std::vector<int>&`。

而如果传入的是右值，那么`param`会被推导为`std::vector<int>`，对于`forward`就是：

```cpp
std::vector<int> && forward(typename                                
              remove_reference<std::vector<int>>::type& param)     
{
  return static_cast<std::vector<int> &&>(param);
}
```

那么就直接返回一个右值引用即可。

# 引用折叠发生的场景

引用折叠发生在以下 4 种场景种：

1. 模板推导过程种
2. `auto`推导
3. 使用`typedef`
4. 使用`decltype`

## `auto`推导

`auto`推导和模板推导很类似：

```cpp
Widget w;                   // a variable (an lvalue)
// 首先 w 被 auto 推导为 Widget&
// 然后展开就是 Widget& && w1 = w;
// 最终就是 Widget& w1 = w;
auto&& w1 = w;

// 首先临时变量被 auto 推导为 Widget
// 展开就是最终情况 Widget&& w2 = WidgetFactory();
auto&& w2 = WidgetFactory();
```

## `typedef`

假设有一个模板类设计如下：

```cpp
template<typename T>
class Widget {
public:
  typedef T&& RvalueRefToT;
  …
};
```

那么传入的参数不同，则会得到相应的左右值引用：

```cpp
Widget<int&> w;
// 内部扩展为 typedef int& && RvalueRefToT;
// 那么最终就是 typedef int& RvalueRefToT;

Widget<int&&> w;
// 内部扩展为 typedef int&& && RvalueRefToT;
// 那么最终就是 typedef int&& RvalueRefToT;
```

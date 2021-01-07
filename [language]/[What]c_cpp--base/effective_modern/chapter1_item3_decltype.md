---
title: [What] Effective Modern C++ ：理解 decltype
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---

# decltype 规则

- decltype 对于变量和表达式的推导，总是忠实的反应其类型
- 对于左值表达式，由于其可被赋值，所以推导的类型总是 T&
- c++14 支持 decltype(auto)，使得 auto 以 decltype 的规则进行推导

# 使用 decltype 的场合

## c++ 11

在 c++11 中，decltype 经常使用的场景是用于模板函数：当输入的参数类型不一样，得到的函数返回类型也不一样。

``` cpp
template<typename Container, typename Index>
auto AuthAndAccess(Container& c, Index i)
-> decltype(c[i])
{
    AuthenticateUser();
    return c[i];
}
```

对于上面的模板函数，要返回 c[i] 类型，但是由于 c 和 i 的类型并无法提前知晓，那么这里使用 decltype 是合理的方式。

## c++ 14 

对于 c++14 而言，从语法上来讲是可以忽略上面的尾置返回类型的，使用 auto 来推导返回的类型，但是这可能会出错：当需要将函数的返回作为左值时：

```cpp
std::deque<int> d;
//由于 auto 推导规则是会省略引用，所以此函数的返回类型最终为 int，而不是 int &
AuthAndAccess(d, 5) = 10;
```

为了能够在 c++14 中返回引用，也需要使用 decltype：

```cpp
template<typename Container, typename Index>
decltype(auto) AuthAndAccess(Container& c, Index i){
    AuthenticateUser();
    return c[i];
}
```

decltype 与 auto 合用，可以使得以 decltype 的形式进行推导：

```cpp
Widget w;
const Widget& cw = w;
//my_widget 的类型是 Widget
auto my_widget = cw;
//my_widget2 的类型是 const Widget&
decltype(auto) my_widget2 = cw;
```

# 使用 decltype 的注意事项

- 当直接推导变量名时，得到的是变量名对应的类型
- 当变量名由括号所包含时，得到的是变量名对应类型的引用

这种特性使得在函数返回时，很有趣：

``` cpp
decltype(auto) F1(){
    int x = 0;
    
    //decltype(x) 得到 int
    return x;
}
decltype(auto) F2(){
    int x = 0;
    
    //decltype(x) 得到 int&
    return (x);
}
```


---
title: '[What] Effective Modern C++ ：理解 auto 类型的推导'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---

《Effective Modern C++》第一章的 Item2 学习，理解 auto 类型推导规则。。
<!--more-->
# auto 推导与模版推导的相同之处
有了前面 Item1 的基础，就可以比较容易的理解 `auto` 推导的逻辑。

其实 `auto` 推导和模版推导几乎一致：
- 模版中使用实参和形参决定 `T` 和 形参
- 而 `auto` 就类似于 `T`，其他附加限定符就类似于形参，右值就相当于实参

比如如下示例：
``` cpp
  //对 auto 的使用
  auto x = 27; //auto 为 int，x 为 int
  const auto cx = x;//auto 为 int，cx 为 const int
  const auto &rx = x;//auto 为 int，rx 为 const int &

  auto && uref1 = x;// auto 和 uref1 均为 int &
  auto && uref2 = cx;// auto 和 uref2 均为 const int &
  auto && uref3 = 27;//auto 为 int，uref3 为 int &&
  //分别对应于函数模版
  template<typename T>
  void func_for_x(T param);

  func_for_x(27);//T 和 param 均为 int

  template<typename T>
  void func_for_cx(const T param);

  func_for_cx(x);//T 为 int，param 为 const int

  template<typename T>
  void func_for_rx(const T& param);

  func_for_rx(x);// T 为 int，param 为 const int &
```

同样的，`auto` 推导也具有 3 种情况：
- 限定符是指针或引用，但不是通用引用
- 限定符是通用引用
- 限定符既不是指针也不是引用
  

同样的，对于数组和函数指针也有例外：
```cpp
  const char name[] = "R. N. Briggs";//name 的长度为 13 字节

  auto arr1 = name;//auto 和 arr1 均为 const char *
  auto &arr2 = name;//auto 为 const char()[13]，arr2 为 const char (&)[13]

  void someFunc(int, double);

  auto func1 = someFunc;//auto 和 func1 均为 void (*)(int, double)
  auto &func2 = someFunc;//auto 为 void()(int, double),fun1 为 void(&)(int, double)
```
# auto 的独特之处
c11 初始化一个变量有以下 4 种语法：
```cpp
  int x1 = 27;
  int x2(27);
  int x3 = {27};
  int x4{27};
```
以上 4 种语法得到的都是一个`int`型变量，其值为 27。但如果使用 `auto`，情况就有些不同：
``` cpp
  auto x1 = 27; // x1 是 int
  auto x2(27);// x2 是 int
  auto x3 = {27};//x3 是 std::initializer_list<int> 类型并包含一个元素，其值为 27
  auto x4{27};//x4 是 std::initializer_list<int> 类型并包含一个元素，其值为 27
```
可以看到，当使用初始值列表而推导得到的变量类型也是初始值列表。

实际上使用初始值列表推导有两个步骤：
- 因为右值是初始值列表，所以首次推导为 std::initializer_list<T> 类型
- 然后是根据初始值列表中的值，再次推导 T 的类型
  

基于以上认识，下面这些情况下推导就会出错：

``` cpp
  //错误！
  //虽然第一步推导出了 std::initializer_list<T>
  //但是第二步却由于列表中的值类型不同，而导致推导失败
  auto x5 = {1, 2, 3.0};

  auto x = {11, 23, 9};//x 为 std::initializer_list<int> 类型

  template<typename T>
  void f(T param);

  //错误！
  //函数模版却没有 auto 那么智能
  f({11, 23, 9});

  template<typename T>
  void f1(std::initializer_list<T> initList);

  //正确
  //f1 仅仅需要一步推导即可得出 T 为 int
  f1({11, 23, 9});
```

在 c++ 14 中，函数可以使用 auto 作为返回，但是这种情况下就无法正确的推导初始化列表了：
``` cpp
  auto createInitList()
  {
    //错误，无法推导
    return {1, 2, 3};
  }
```

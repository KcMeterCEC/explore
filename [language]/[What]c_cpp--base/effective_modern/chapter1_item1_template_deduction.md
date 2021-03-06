---
title: '[What] Effective Modern C++ ：理解模板类型的推导'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---

《Effective Modern C++》第一章的 Item1 学习，粗略理解模板是如何进行类型推导的。
<!--more-->

# 基础
一个普通的函数模板就像下面这样：

```cpp
#include <iostream>
#include <cstdint>

template<typename T>
T GetSum(const T *buf, int size){
  T sum = 0;
  for(int i = 0; i < size; ++i){
    sum += buf[i];
  }

  return sum;
}

int main(void){
  uint16_t u16_buf[] = {0, 1, 2, 3, 4, 5};
  uint32_t u32_buf[] = {6, 7, 8, 9, 10};
  float float_buf[] = {1.123, 2.234, 3.345, 4.456};

  std::cout << "The sum of u16 buffer is " << GetSum(u16_buf, sizeof(u16_buf) / sizeof(u16_buf[0])) << std::endl;
  std::cout << "The sum of u32 buffer is " << GetSum(u32_buf, sizeof(u32_buf) / sizeof(u32_buf[0])) << std::endl;
  std::cout << "The sum of float buffer is " << GetSum(float_buf, sizeof(float_buf) / sizeof(float_buf[0])) << std::endl;

  return 0;
}
```

对应的输出为：

>  The sum of u16 buffer is 15
>   The sum of u32 buffer is 40
>   The sum of float buffer is 11.158

使用函数模板来代替函数重载，这是一种简单而优雅的做法。

从表面上来看，似乎编译器是自然而然的就可以根据实参的类型推导出类型`T`，然而实际上类型`T`和形参所使用的`T`是不同的。
 > 就拿上面的 GetSum 函数模板举例，被推导的类型实际上有：
 > 1. 模板类型 T
 > 2. 函数形参 const T *

最终，真正决定`T`的类型，是由实参和形参类型共同所决定的，具有以下 3 种情况：
1. 形参是一个指针或引用类型，但并不是一个普通的引用
2. 形参是一个普通的引用
3. 形参既不是指针也不是引用

# 形参是一个指针或引用类型，但并不是一个普通的引用
这种情况下的推导步骤如下：
- 如果实参是一个引用（无论是左值还是右值引用）或指针，那么就忽略引用或指针的部分
- 然后再根据实参剩余部分和形参共同决定类型`T`
``` cpp
  /**
   * 第一种函数模板形参
   */
  template<typename T>
  void f(T& param);

  // 具有以下 3 种实参
  int x = 27;
  const int cx = x;
  const int & rx = x;
  //对应的推导结果就是
  f(x);   //T 类型为 int，形参类型为 int&
  f(cx);  //T 类型为 const int，形参类型为 const int&
  f(rx);  //T 类型为 const int，形参类型为 const int&
```
可以看到，实参`rx`的引用被去掉了，最终类型`T`和`cx`是一致的情况。
``` cpp
  /**
   * 第二种函数模板形参
   */
  template<typename T>
  void f(const T& param);

  // 具有以下 3 种实参
  int x = 27;
  const int cx = x;
  const int & rx = x;
  //对应的推导结果就是
  f(x);   //T 类型为 int，形参类型为 const int&
  f(cx);  //T 类型为 int，形参类型为 const int&
  f(rx);  //T 类型为 int，形参类型为 const int&
```

可以看到，这一次的类型`T`统一为`int`型。
- 由于第一种情况下，形参并没有使用`const`限定符，而实参使用了`const`限定符，那么用户的期望是希望`T`是无法被改变的类型，所以`T`被推导成了 const int。
- 但是第二种情况下，形参已经使用了`const`限定符，那么实参是否有`const`已经不重要了，这种情况下就可以使用更为宽松的`int`类型。
``` cpp
  /**
   * 第三种函数模板形参
   */
  template<typename T>
  void f(T* param);

  // 具有以下 2 种实参
  int x = 27;
  const int *px = &x;
  //对应的推导结果就是
  f(&x);   //T 类型为 int，形参类型为 int*
  f(px);  //T 类型为 const int，形参类型为 const int*

  /**
   * 第四种函数模板形参
   */
  template<typename T>
  void f(const T* param);

  // 具有以下 2 种实参
  int x = 27;
  const int *px = &x;
  //对应的推导结果就是
  f(&x);   //T 类型为 int，形参类型为 int*
  f(px);  //T 类型为 int，形参类型为 const int*
```

可以看到，使用指针的情况也是和引用类似的。
# 形参是一个普通的引用
- 如果实参是一个左值，那么类型 T 和形参都会被推导成左值引用
  - 即使形参是右值引用，也会被推导成左值引用
- 如果实参是一个右值，那么就会使用情况 1 来进行推导
``` cpp
  //假设如下的函数模板
  template<typename T>
  void f(T&& param);

  //实参如下
  int x = 27;
  const int cx = x;
  const int &rx = x;
  //对应的推导结果就是
  f(x); //x 是左值，T 类型就是 int&，形参类型也是 int&
  f(cx);//cx 是左值，T 类型就是 const int&，形参类型也是 const int&
  f(rx);//rx 是左值，T 类型就是 const int&，形参类型也是 const int&
  f(27);//27 是右值，T 类型就是 int，形参类型是 int&&
```
# 形参既不是指针也不是引用
- 如果实参是一个引用，忽略掉引用部分
- 忽略掉引用后，如果实参部分是 const 或 volatitle，也忽略掉 const 或 volatitle。
``` cpp
  //假如如下的函数模板
  template<typename T>
  void f(T param);

  //实参如下
  int x = 27;
  const int cx = x;
  const int &rx = x;
  const char *const ptr = "Fun with pointers";
  //对应的推导结果就是
  f(x); // 类型 T 和 形参均为 int 型
  f(cx); // 类型 T 和 形参均为 int 型
  f(rx); // 类型 T 和 形参均为 int 型
  f(ptr); //类型 T 和 形参均为 const char * 型
```
- 虽然`cx`和`rx`都是`const`类型，但由于函数模板是普通形参，无论实参如何，形参都是对实参的拷贝。所以形参都是`int`类型。
- 而`ptr`是指向`const char *`型的`const`指针，所以`ptr`本身的`const`被 passed by value，但该`ptr`所指向的对象依然应该是`const char *`。
# 数组参数
需要注意的是：对于模版参数而言，数组参数和指针参数不是一个东西
``` cpp
  //假如如下的函数模板
  template<typename T>
  void f(T param);

  //实参如下
  const char name[] = "J.P. Briggs";
  //对应的推导结果就是
  f(name); //类型 T 和 形参均为 const char * 型
```
上面这种情况下，name 和上一个情况的 ptr 是一样的，但如果函数模版形参是引用的话：
``` cpp
  //假如如下的函数模板
  template<typename T>
  void f(T& param);

  //实参如下
  const char name[] = "J. P. Briggs";//name 的长度是 13 字节
  //对应的推导结果就是
  f(name); //类型 T 为 const char [13], 形参为 const char(&)[13]
```
可以看到此时形参就被推导成为了对固定长度数组的引用
# 函数参数
另一个需要注意的就是函数指针：
``` cpp
  void someFunc(int, double);

  template<typename T>
  void f1(T param);

  template<typename T>
  void f2(T& param);

  f1(someFunc);// 类型 T 和形参均为 void(*)(int, double);

  f2(someFunc);// 类型 T 为 void()(int, double)，形参为 void(&)(int, double)
```

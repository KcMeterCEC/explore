---
title: Effective C++ ：尽可能的使用 constexpr
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/5/4
updated: 2022/5/4
layout: true
comments: true
---

使用`constexpr`以让编译器来检查该值是否是常量表达式，降低程序员负担。

<!--more-->

# `const` 与 `constexpr`

`constexpr`修饰的表达式，需要在**编译时**就确定其值，且该值以后不可被改变。而`const`修饰的表达式，是在运行时才能够确定其值：

> 所有的`constexpr`都是`const`的，但所有的`const`都不一定是`constexpr`的

```cpp
#include <vector>
#include <iostream>
#include <array>

int main(void) {

    int sz; //非常量表达式
    constexpr auto array_size = sz; //由于 sz 不是常量表达式，所以 array_size 无法编译通过
    std::array<int, sz> array1; //由于 sz 不是常量表达式，所以无法创建该数组

    constexpr int sz2 = 20;
    std::array<int, sz2> array2;

    return 0;
}
```

```cpp
#include <vector>
#include <iostream>
#include <array>


int main(void){

    int sz; //非常量表达式
    const auto array_size = sz; //array_size 的值由运行时确定
    std::array<int, array_size> array1; //由于 array_size 不是常量表达式，所以无法创建该数组

    return 0;
}
```

# `constexpr`函数

`constexpr`函数具有的特性：

- 当传入该函数的实参是`constexpr`时，该函数的结果就是可以在编译期确定的。
- 如果传入的实参不是`constexpr`的，该函数就是普通的在运行时确定的函数

```cpp
#include <vector>
#include <iostream>
#include <array>

constexpr int pow(int base, int exp) noexcept {
    //c++ 11 仅允许一条 return 语句
    return (exp == 0 ? 1 : base * pow(base, exp - 1));

    //c++ 14 允许多条语句
//    int result = 1;
//    for (int i = 0; i < exp; ++i) {
//        result *= base;
//    }

//    return result;
}

int main(void) {

    constexpr int exp = 5;
    //当传入的值是 constexpr 时，可以用在编译时确定值
    std::array<int, pow(3, exp)>();

    //当传入的值不是 constexpr 时，就用在运行时
    int exp2 = 10;
    std::cout << "Result " << pow(2, exp2) << "\n";


    return 0;
}
```

# `constexpr`类

如下的类：

```cpp
class Point {
public:
  constexpr Point(double xVal = 0, double yVal = 0) noexcept
  : x(xVal), y(yVal)
  {}
  constexpr double xValue() const noexcept { return x; }
  constexpr double yValue() const noexcept { return y; }
  void setX(double newX) noexcept { x = newX; }
  void setY(double newY) noexcept { y = newY; }
private:
  double x, y;
};
```

当构造函数被传入的实参是`constexpr`的是，这个类所实例化的对象也是`constexpr`的，进而该类就可以被`constexpr`函数所调用：

```cpp
constexpr    
Point midpoint(const Point& p1, const Point& p2) noexcept {
  return { (p1.xValue() + p2.xValue()) / 2,    // call constexpr
           (p1.yValue() + p2.yValue()) / 2 };  // member funcs
}
constexpr Point p1(9.4, 27.7);      // fine, "runs" constexpr
                                    // ctor during compilation
constexpr Point p2(28.8, 5.3);      // also fine

constexpr auto mid = midpoint(p1, p2);     // init constexpr
                                           // object w/result of
                                           // constexpr function
```

最终以上对象的创建都是在**编译期**就完成了，虽然编译的时间会加长，但是代码的运行效率确更高。
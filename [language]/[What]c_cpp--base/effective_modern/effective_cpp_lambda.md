---
title: Effective C++ ：正确使用 lambda
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/5/12
updated: 2022/5/12
layout: true
comments: true
---

lambda 使得 c++ 更有魅力，使用 lambda 可以创建一个可调用的对象，一般用于以下场合：
1. 快速创建一个简短的函数，仅在父函数中使用，避免繁琐的创建成员函数的过程。
2. 为标准库的算法（`std::find_if,std::sort` 等），优雅的创建一个可调用对象。
3. 快速为标准库创建删除器，比如`std::unique_ptr,std::shared_ptr`等

<!--more-->

# 避免使用默认捕获

默认捕获会被编码者带来一定的误导，忽视一些错误捕获或无法捕获的场景。

> google 编码规范中，也 [提到了这点](https://zh-google-styleguide.readthedocs.io/en/latest/google-cpp-styleguide/others/#lambda)。

## 引用捕获要注意被捕获对象的作用域

如果引用捕获对象的作用域是局部作用域，而 lambda 对象的使用超出了该作用域则会导致引用指向的对象无意义，最终会导致 undefined behavior。

比如设计一个容器，里面包含了函数对象：

```cpp
using FilterContainer = std::vector<std::function<bool(int)>>;

FilterContainer filters;
```

然后在一个函数中，插入可调用对象到容器中：

```cpp
void addDivisorFilter() {
  auto calc1 = computeSomeValue1();
  auto calc2 = computeSomeValue2();
  auto divisor = computeDivisor(calc1, calc2);
  filters.emplace_back(                              
    [&](int value) { return value % divisor == 0; }  
  );                                                
} 
```

由于`divisor`变量在退出函数后，其栈内存就被回收了，所以当该 lambda 被调用时，就是 undefined behavior。

为了避免这种情况，应该使用 passed by value 的形式形成闭包：

```cpp
void addDivisorFilter() {
  auto calc1 = computeSomeValue1();
  auto calc2 = computeSomeValue2();
  auto divisor = computeDivisor(calc1, calc2);
  filters.emplace_back(                              
    [=](int value) { return value % divisor == 0; }  
  );                                                
}
```

同理，如果捕获的参数是一个指针，也需要注意指针指向的内存被释放的情况。

使用默认捕获很容易让人忽视这类问题，而在捕获位置明确指出需要捕获的对象，则更容易提醒编码人员。

## 捕获成员变量

需要理解的是：类中的成员变量的完整形式其实是：`this->member_variable`

比如下面这段代码是会编译错误的：
```cpp
class Hello {
public:
    void DoSomething(void) {
        auto func = [val_]() {
            std::cout << "The value of val is " << val_ << "\n";
        };

        func();
    }
private:
    int val_ = {10};
};
```

因为`val_`变量实际上是`this->val_`。

而使用默认捕获是可以编译通过的：

```cpp
class Hello {
public:
    void DoSomething(void) {
        auto func = [=]() {
            std::cout << "The value of val is " << val_ << "\n";
        };

        func();
    }
private:
    int val_ = {10};
};
```

实际上，这就等同于:

```cpp
void DoSomething(void) {
    auto obj_ptr = this;
    auto func = [obj_ptr]() {
        std::cout << "The value of val is " << obj_ptr->val_ << "\n";
    };

    func();
}
```

这就容易出现问题了，如果代码也是按照前面那一节将`lambda`对象放入容易，以后再来调用。
那么该对象完全可能在调用之前就被析构了，后来的操作就又是 undefined behavior。

最好的方式就是来捕获成员变量的拷贝：
```cpp
void DoSomething(void) {
    int val_copy = val_;

    auto func = [val_copy]() {
        std::cout << "The value of val is " << val_copy << "\n";
    };

    func();
}
```

c++ 14 还有更加简单的写法：
```cpp
void DoSomething(void) {
    // 直接在捕获语句类生成拷贝
    auto func = [val_ = val_]() {
        std::cout << "The value of val is " << val_ << "\n";
    };

    func();
}
```

## 静态存储变量与捕获

实际上，lambda 无法捕获静态存储变量而形成闭包：
> 这里的静态存储变量包括：全局变量、在命名空间内的变量、`static`修饰的变量

```cpp
#include <cmath>
#include <chrono>
#include <cstdio>
#include <vector>
#include <iostream>

int main() {
    static int v = 10;

    // 实际上这里加不加 = 都不影响，因为没有捕获到任何变量
    auto func = [=]() {
        std::cout << "The value of v is " << v << "\n";
    };

    v = 3;

    func();

    return 0;
}
```

输出为：

```shell
The value of v is 3
```


# 使用初始捕获来完成移动对象的闭包

如果有些对象（比如容器）以拷贝的方式形成闭包，其效率太低了。这种情况下应该以移动的方式来形成闭包。
> c++14 有现成的语法支持，称之为初始捕获（init capture）

## 基于 c++ 14 的初始捕获

所谓的初始捕获，其实简单来讲就是：使用局部变量来初始化 lambda 表达式闭包中的变量：

```cpp
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <array>

int main(int argc, char *argv[]) {

    std::vector<int> vec = {1, 2, 3, 4, 5};

    // c++ 14 支持将 vec 内容移动给 v 以形成闭包
    auto func = [v = std::move(vec)]() {
        std::cout << "The contenes of v are:\n";

        for (auto val : v) {
            std::cout << val << ",";
        }

        std::cout << "\n";
    };

    func();


    // 移动后的 vec 则不包含内容了
    std::cout << "vec size " << vec.size() << "\n";

    return 0;
}
```

## 基于 c++ 11 的初始捕获

由于 c++ 11 没有语法支持，所以需要借助`std::bind`来完成这个需求：

```cpp
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <array>
#include <functional>

int main(int argc, char *argv[]) {

    std::vector<int> vec = {1, 2, 3, 4, 5};

    auto func = std::bind(
            [](const std::vector<int>& v) {

                std::cout << "The contenes of v are:\n";

                for (auto val : v) {
                    std::cout << val << ",";
                }

                std::cout << "\n";
            },
            std::move(vec)
            );

    func();


    std::cout << "vec size " << vec.size() << "\n";

    return 0;
}
```

# lambda 与完美转发

c++14 中，lambda 的参数可以由`auto`推导，这就如同模板一样：
```cpp
auto f = [](auto x){ return func(normalize(x)); };

// 等同于
class SomeCompilerGeneratedClassName {
public:
  template<typename T>                   
  auto operator()(T x) const             
  { return func(normalize(x)); }
  …                                      
};                                       
```

但需要注意的是，如果 lambda 中调用了其他对象，且具有左值及右值对应的版本那么就需要使用完美转发：

```cpp
auto f = [](auto&& x)
         { return func(normalize(std::forward<???>(x))); };
```

但问题是，`std::forward`中并无法确定参数类型。

这个时候就可以使用`decltype`来推导类型：

```cpp
auto f = [](auto&& x)
         { return func(normalize(std::forward<decltype(x)>(x))); };
```

除此之外，c++14 的 lambda 还支持变参数：

```cpp
auto f =
  [](auto&&... params)
  {
    return
    func(normalize(std::forward<decltype(params)>(params)...));
  };
```

# lambda 优于 std::bind

lambad 综合上优于 `std::bind`，最主要的是其优异的可读性。

比如要编写一个声音报警程序，先声明以下类型：
```cpp
// 时间点
using Time = std::chrono::steady_clock::time_point;
// 报警的类型
enum class Sound { Beep, Siren, Whistle };
// 时间长度
using Duration = std::chrono::steady_clock::duration;

// 设置报警的函数
void setAlarm(Time t, Sound s, Duration d);
```

然后以 lambda 的方式来封装，产生一个 1 小时后响铃 30 秒的可调用对象：

```cpp
// setSoundL ("L" for "lambda") is a function object allowing a
// sound to be specified for a 30-sec alarm to go off an hour
// after it's set
auto setSoundL =                             
  [](Sound s)
  {
    // make std::chrono components available w/o qualification
    using namespace std::chrono;
    setAlarm(steady_clock::now() + hours(1),  // alarm to go off
             s,                               // in an hour for
             seconds(30));                    // 30 seconds
  };
```

基于 c++ 14 的话，还可以再次简化：

```cpp
auto setSoundL =                             
  [](Sound s)
  {
    using namespace std::chrono;
    using namespace std::literals;         // for C++14 suffixes
    setAlarm(steady_clock::now() + 1h,     // C++14, but
             s,                            // same meaning
             30s);                         // as above
  };
```

但使用`std::bind`来实现同样的可调用对象，则要麻烦得多，并且可读性很差：

```cpp
using namespace std::chrono;           // as above
using namespace std::literals;
using namespace std::placeholders;     // needed for use of "_1"
auto setSoundB =                       // "B" for "bind"
  std::bind(setAlarm,
            // 使用下面这种方式，那么获取到得则是绑定时得时间点，而不是调用时的时间点
            // steady_clock::now() + 1h,
            
            // 应该如下，c++ 14 中，std::plus 中的类型可以忽略
            std::bind(std::plus<>(), steady_clock::now(), 1h),
            _1,
            30s);
```
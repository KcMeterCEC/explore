---
title: Effective C++ ：熟悉完美转发的错误情况
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

要认识到完美转发的一些错误用例，才能够很好的使用它。

<!--more-->

# 基本使用

再来看看完美转发的基本使用：根据输入参数的类型，调用对应的函数。

```cpp
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <array>

void func(std::string& val) {
    std::cout << "This is lvalue function!\n";
}

void func(std::string&& val) {
    std::cout << "This is rvalue function!\n";
}

template<typename T>
void hello(T&& param) {
    // 如果不使用完美转发，那么最终只会调用到其左值版本
    func(std::forward<T>(param));
}

int main(int argc, char *argv[]) {

    std::string a("Hello world!\n");

    hello(a);
    hello(std::string("haha"));


    return 0;
}
```

不仅仅是一般的模板函数，可变参模板也是可以这样用的：

```cpp
template<typename... Ts>
void fwd(Ts&&... params) {             // accept any arguments
  f(std::forward<Ts>(params)...);      // forward them to f
}
```

# 完美转发失败的情况

## 列表初始化

列表初始化对于转发函数无法通过编译：

```cpp
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <array>

void func(std::vector<int>& val) {
    std::cout << "This is lvalue function!\n";
}

void func(std::vector<int>&& val) {
    std::cout << "This is rvalue function!\n";
}

template<typename T>
void hello(T&& param) {
    func(std::forward<T>(param));
}

int main(int argc, char *argv[]) {

    // 直接使用可以通过编译
    func({1, 2, 3, 4, 5});
	// 无法通过编译
    hello({1, 2, 3, 4, 5});

    return 0;
}
```

编译报错如下：

```shell
move.cc: In function ‘int main(int, char**)’:
move.cc:24:26: error: no matching function for call to ‘hello(<brace-enclosed initializer list>)’
     hello({1, 2, 3, 4, 5});
                          ^
move.cc:16:6: note: candidate: template<class T> void hello(T&&)
 void hello(T&& param) {
      ^~~~~
move.cc:16:6: note:   template argument deduction/substitution failed:
move.cc:24:26: note:   couldn't deduce template parameter ‘T’
     hello({1, 2, 3, 4, 5});
```

这是因为直接调用的情况下，编译器可以通过函数形参来推导出实参的类型。而通用引用函数则无法完成推导。

解决办法是，我们可以将列表的类型传递进去：

```cpp
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <array>

void func(std::vector<int>& val) {
    std::cout << "This is lvalue function!\n";
}

void func(std::vector<int>&& val) {
    std::cout << "This is rvalue function!\n";
}

template<typename T>
void hello(T&& param) {
    func(std::forward<T>(param));
}

int main(int argc, char *argv[]) {

    func({1, 2, 3, 4, 5});

    // 这种方式也可以
    //hello(std::initializer_list<int>({1, 2, 3, 4, 5}));

    // 但这种方式更优雅
    auto v = {1, 2, 3, 4, 5};
    hello(v);

    return 0;
}
```

## 以 0 或 NULL 来表示空指针

这是因为`nullptr`是空指针，而 0 或 NULL 则无法被通用引用函数正确的推导。

## 仅声明`static const`数据成员

可以直接在类内声明`static const`数据成员，只要不取其地址，那么可以正常使用。

但在通用引用函数中，由于引用在编译器内部也是一个指针，所以在这种情况下就需要提供其定义：

```cpp
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <array>

class Player {
    public:
        static const int count = 10;
};

// 在使用通用引用时，如果没有定义则无法编译通过
const int Player::count;

void func(std::size_t& val) {
    std::cout << "This is lvalue function!\n";
}

void func(std::size_t&& val) {
    std::cout << "This is rvalue function!\n";
}

template<typename T>
void hello(T&& param) {
    func(std::forward<T>(param));
}

int main(int argc, char *argv[]) {

    hello(Player::count);

    return 0;
}
```

## 重载函数名和模板

当通用引用函数的形参是函数指针时，如果输入的函数还有重载（重载函数或函数模板），那么将无法推导。

## 位字段

如果通用引用函数的输入是位字段，则无法完成推导，因为引用在编译器内部是指针，而无法获取位字段的地址。
> 函数形参是拷贝形式或`const`引用形式，就可以传入位字段。因为编译器会为这些位字段生成拷贝。
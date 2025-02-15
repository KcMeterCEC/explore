---
title: Effective C++ ：属性
tags: 
- cpp
categories:
- cpp
- professional
date: 2025/2/15
updated: 2025/2/15
layout: true
comments: true
---

从 c++11 开始，就具备了一些属性，其语法是 `[[attribute]]` 。

<!--more-->

# [[fallthrough]]

如果在 `switch` 语句中的 `case` 后没有跟 `break`，则编译器会给出警告。

使用 `[[fallthrough]]` 可以阻止编译器发出这种警告：

```cpp
int main(int argc, char* argv[]) {
    int i = 0;

    switch (i) {
        case 0: {
            std::cout << "i == 0\n";
            [[fallthrough]];
        }
        case 1: {
            std::cout << "i == 1\n";
            [[fallthrough]];
        }
        case 2: {
            std::cout << "i == 2\n";
            [[fallthrough]];
        }
        default:break;
    }

    return 0;
};
```

# [[nodiscard]]

如果一个函数有返回值，而调用者没有使用该返回值，使用 `[[nodiscard]]`可以让编译器发出警告。

```cpp
[[nodiscard]] int func(void) {
    return 0;
}


int main(int argc, char* argv[]) {

    func();

    return 0;
};
```

以上代码编译将会给出警告：

```shell
test.cc: In function ‘int main(int, char**)’:
test.cc:15:9: warning: ignoring return value of ‘int func()’, declared with attribute nodiscard [-Wunused-result]
   15 |     func();
      |     ~~~~^~
test.cc:8:19: note: declared here
    8 | [[nodiscard]] int func(void) {
      |  
```

此属性可以用于有返回错误状态的函数，以告知用户不要忽略函数的返回。

c++ 20 及以后，可以在 `[[nodiscard]]`中加入提示的字符：

```cpp
 [[nodiscard("Hello")]] int func(void) {
     return 0;
 }


 int main(int argc, char* argv[]) {

     func();

     return 0;
 };
```

编译将会输出：

```shell
main.cpp: In function 'int main(int, char**)':
main.cpp:15:10: warning: ignoring return value of 'int func()', declared with attribute 'nodiscard': 'Hello' [-Wunused-result]
   15 |      func();
      |      ~~~~^~
main.cpp:8:29: note: declared here
    8 |  [[nodiscard("Hello")]] int func(void) {
```

这个属性主要是对一些重要的函数、类使用，便于提示调用者不要忽视返回值。

> 如果对类使用，则调用类中的任何方法都会应用该属性。

# [[maybe_unused]]

当某些变量、参数、函数未被使用时，编译器会给出警告。此属性可以抑制该警告：

```cpp
 // var2 加了此属性后便不会给出警告，var1 则会给出警告
 void func(int var1, [[maybe_unused]]int var2) {

 }


 int main(void) {

     func(0, 1);

     return 0;
 };
```

# [[noreturn]]

此属性抑制无返回函数的警告，比如下面的代码进入 func2() 会无返回退出进程。加上该属性，编译器便不会给出警告。

```cpp
 [[noreturn]] void func2(void)
 {
     std::cout << "hello\n";
     exit(1);
 }

 bool func(int var1) {
    if (var1 > 10) {
        func2();
    } else {
        return true;
    }
 }


 int main(void) {

     bool result = func(20);

     return 0;
 };
```

# [[deprecated]]

使用此属性用于提醒用户，该 API 已被弃用，可以通过提示信息告知用户使用对应的版本：

```cpp
[[deprecated("Unsafe method, please use func2")]] int func(void) {
    return 0;
}


int main(int argc, char* argv[]) {

    int v = func();

    return 0;
};
```

# [[likely]] 和 [[unlikely]]

这两个属性用于更好的帮助编译器做优化，一般是用在具有判断的代码处：

```cpp
int main(int argc, char* argv[]) {

    int v = 10;

    [[likely]] if (v > 8) {
        std::cout << "v > 8\n";
    } else {
        std::cout << "v <= 8\n";
    }

    return 0;
};
```

# [[assume]]

`[[assume]]`是 c++ 23 增加的属性，告知编译器假定当前表达式条件在编译时判断，而不是在运行时再来判断，以优化代码性能。

比如下面的代码：

```cpp
int divideBy32(int x)
{
    return x / 32;
}
```

正常情况下编译器会产生可以处理正负两种情况的除法，如果确认`x`的值不会为负数，那么就可以加上`[[assume]]`:

```cpp
int divideBy32(int x)
{
    [[assume(x>=0)]];
    return x / 32;
}
```

这样子编译器就可以针对非负数除法做优化，比如上面的代码可以优化为`x>>5`，以单条指令就可以完成达到优化性能的目的。

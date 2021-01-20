---
title: '[What] Effective Modern C++ ：nullptr 优于 0 和 NULL'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---
在 c 中，通常使用`NULL`表示一个空指针，但是在 cpp 中有更优的`nullptr`可供选择。
<!--more-->

首先需要明白：

1. `0` 是一个`int`型的数，而不是指针类型
2. `NULL`也是一个宏定义的`0`
   - 在 c++11 及以后的版本中， `NULL`的宏定义为：`#define NULL nullptr`
3. `nullptr`实际上是`std::nullptr_t`类型，它可以转换为任何指针类型，且不会有二义性

# `nullptr`与二义性

```s
#include <vector>
#include <iostream>

void f(int i){
    std::cout << "int parameter " << i << "\n";
}
void f(int *i){
    std::cout << "pointer paramter " << i << "\n";
}

int main(void){
    f(0);
    f(NULL);
    f(nullptr);

    return 0;
}
```

上述代码，在`msvc`编译环境中输出为：

> int parameter 0
> int parameter 0
> pointer paramter 00000000

而在`g++`编译环境中，由于这种使用`NULL`的方式具有二义性，编译器干脆就报错：

> $ g++ main.cpp
> main.cpp: In function ‘int main()’:
> main.cpp:13:11: error: call of overloaded ‘f(NULL)’ is ambiguous
>      f(NULL);
>            ^
> main.cpp:4:6: note: candidate: void f(int)
>  void f(int i){
>       ^
> main.cpp:7:6: note: candidate: void f(int*)
>  void f(int *i){
>       ^

所以，当明确要使用指针类型时，使用`nullptr`是最好的选择。

# `nullptr`与可读性

比如使用如下代码：

```cpp
auto result = Record();
if(result == 0){
    
}
```

上面这样的代码，并不易于阅读，读代码的人并不能确定`result`一定是整型，或是指针。

但如果改为下面这样，那么`result`的类型就确认无疑是指针，这就增加了代码的可读性。

```cpp
auto result = Record();
if(result == nullptr){
    
}
```

# `nullptr`与正确性

由于`0`和`NULL`并不能转换为任意指针类型，所以在调用有些需要特定指针类型的函数时，编译器就会报错。

而`nullptr`却可以转为该类型，保证编译的正确执行。

 
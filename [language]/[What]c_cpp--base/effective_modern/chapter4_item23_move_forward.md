---
title: '[What] Effective Modern C++ ：理解 std::move 和 std::forward'
tags: 
- c++
categories: 
date:  2021/1/26
- language
- c/c++
- Effective
layout: true
---
- 移动语义：使用移动内存的方式替代拷贝方式，以提高效率
- 完美转发：将接受任意参数的函数模板参数转发给其它函数，其它函数获得与自己需求参数同样的实参
- 右值引用：用于粘合以上两个特性
  - 区别左值与右值的一个方法是：如果一个对象可以取地址，那么它是左值，否则它是右值。
  <!--more-->

# `std::move`和`std::forward`

`std::move`相当于无条件的将其参数转换为右值，而`std::forward`则是判定条件否则满足来进行转换。

`std::move`的简易实现如下：

```cpp
//c++11 版本
template<typename T>                       // in namespace std
typename remove_reference<T>::type&&
    move(T&& param)
{
    using ReturnType =                       // alias declaration;
        typename remove_reference<T>::type&&;  
    return static_cast<ReturnType>(param);
}

//c++14 版本
template<typename T>                          
decltype(auto) move(T&& param)                
{
    using ReturnType = remove_reference_t<T>&&;
    return static_cast<ReturnType>(param);
}
```

可以看到，`move`函数将参数`param`使用`static_cast`强制转换为了`remove_reference<T>::type&&`，也就是参数的右值引用。

也就是说标准的`std::move`也仅仅是做转换作用，它并没有像它的名字那样实现移动的操作。

而是向编译器指明，该对象是可以被移动的。

# 理解`std::move`

对于`std::string`，其有构造函数如下：

```cpp
class string {            // std::string is actually a 
public:                   // typedef for std::basic_string<char>
…
    string(const string& rhs);    // copy ctor
    string(string&& rhs);         // move ctor
…
};
```

一个是接收`const string`的左值引用的拷贝构造函数，另一个是`string`的右值引用移动构造函数，因为移动构造函数是要修改形参对象内存的，所以不能添加`const`限定。

下面假设有一个类的构造函数需要传入`string`:

```cpp
class Annotation {
    public:
    explicit Annotation(const std::string text)
        private:
    std::string value;
};
```

这个类的构造函数接受一个`const std::string`来完成对私有成员`value`的赋值。

下面假设我们希望使用移动语义来完成`value`的赋值：

```cpp
class Annotation {
    public:
    explicit Annotation(const std::string text)
        : value(std::move(text))  // "move" text into value; this code
        { … }                     // doesn't do what it seems to!

    …
    private:
    std::string value;
};
```

但实际上，依然调用的是拷贝构造函数！

因为虽然使用了`std::move`将`text`确实转换成了右值引用，但是其`const`限定依然存在。既然有`const`存在，就无法使用`string`的移动构造函数，转而使用其拷贝构造函数！

所以，`std::move`只能说是将参数转换成了右值引用，至于是否真的执行了移动操作，要根据当前的上下文而定。

# 理解`std::forward`

相对于`std::move`的无条件转换，`std::forward`则是根据情况来判定是否转换。

`std::forward`主要是将函数模板参数转为特定的类型，给予不同的函数：

```cpp
#include <vector>
#include <iostream>
#include <array>
#include <memory>

void process(const int& lvalArg){
    std::cout << "This is process function with const int&\n";
}
void process(int&& rvalArg){
    std::cout << "This is process function with int&&\n";
}

template<typename T>
void func(T&& param){
    process(std::forward<T>(param));
}

int main(void){
    int a = 10;

    func(a);
    func(std::move(a));

    return 0;
}
```

其输出为：

>This is process function with const int&
>This is process function with int&&

`std::forward`根据传入参数是左右引用还是右值引用来判定调用对应版本的重载函数。

`std::forward`虽然看起来更加智能，但是其需要参考的条件也多：

- 首先要指定转换的具体类型是什么
- 其次还要参数的类型是右值引用时，才会调用右值引用版本的函数

但`std::move`好就好在简单粗暴，不管类型和传入参数，直接转换为右值引用。
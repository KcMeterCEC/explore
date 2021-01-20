---
title: '[What] Effective Modern C++ ：delete 优于私有未定义行为'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---
如果不想让用户使用某个函数，那么有以下 3 种做法：
1. 使用`delete`限定
2. 将该函数设定为私有
3. 直接不定义该函数

最为合适的做法，就是使用`delete`限定。
<!--more-->

# 3 种方法的差别

如果一个函数完成度不够或在实际行为上不允许用户调用该函数，那么：

## 直接将该函数屏蔽或删除

对于自己定义的函数，屏蔽它是一个做法，但这样总是看起来不优雅。

对于拷贝构造，拷贝赋值这类函数，如果不定义编译器也会有个默认版本，是无法将其直接删除的。

## 将该函数设定为私有

私有成员不能被用户调用，但是可以被`friend`或其它成员函数无意调用，这会造成逻辑漏洞。

## 使用`delete`限定

使用`delete`是作为稳妥的办法，因为这是由编译器帮你把各个环节都限定了该函数不能被访问。

# `delete`函数需要被设定为`public`访问权限

用户在访问一个方法的时候，编译器首先是检查其访问权限，然后才是检查其相关限定。

如果将一个`delete`函数放在`private`区，那么当用户访问的时候，就只会出现访问权限错误的警告。

而如果将一个`delete`函数放在`public`区，那么编译器就会给出正确的提示警告。

# 使用`delete`限定参数类型

```cpp
bool isLucky(int number);            // original function
bool isLucky(char) = delete;         // reject chars
bool isLucky(bool) = delete;         // reject bools
bool isLucky(double) = delete;       // reject doubles and
                                     // floats
```

以上就限定了`isLucky`的输入参数必须是`int`类型。

对于模板函数，也可以对特点类型进行限定：

```cpp
template<typename T>
void processPointer(T* ptr);
//限制 void* 
template<>
void processPointer<void>(void*) = delete;
template<>
void processPointer<const void>(const void*) = delete;
template<>
void processPointer<const void>(const volatile void*) = delete;
//限制 char*
template<>
void processPointer<char>(char*) = delete;
template<>
void processPointer<const char>(const char*) = delete;
template<>
void processPointer<const char>(const volatile char*) = delete;
```

在类种的函数模板，也可以如此使用：

```cpp
class Widget {
public:
  …
  template<typename T>
  void processPointer(T* ptr)
  { … }
  …
};
template<>                                          // still
void Widget::processPointer<void>(void*) = delete;  // public,
                                                    // but
                                                    // deleted
```


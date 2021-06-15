---
title: [What]compiler -> 区分编译器及系统
tags: 
- compiler
date:  2018/4/2
categories: 
- program
- compiler
layout: true
---

关于编译器和系统的区分老是忘记，故在此记录一下。

<!--more-->

在区分编译器和系统时，都是使用下面这个方式来判断对应宏：
``` c
//单独区分
#ifdef xxx
#elif xxx
#endif

//组合
#if (defined(xxx) && defined(xxx))
#endif
```
# 区分编译器
## gcc
gcc 具有以下宏来标识自己：
```shell
__GNUC__
__GNUC_MINOR__
__GNUC_PATCHLEVEL__
```
实际上这些宏都是带有数值的，以表示 gcc 的版本号。

- 如果仅仅是判断一个编译器是不是 gcc，那么使用以下方式即可
``` c
#ifdef __GNUC__
...
#endif
```
- 如果对应的代码需要对于 gcc 不同版本，需要用以下方式
``` c
#define GCC_VERSION (__GNUC__ * 10000 \
                     + __GNUC_MINOR__ * 100 \
                     + __GNUC_PATCHLEVEL__)
…
/* Test for GCC > 3.2.0 */
#if GCC_VERSION > 30200
```
## Visual C++
visual c++ 下判断最常用的就是:
```shell
_MSC_FULL_VER
_MSC_VER 
```
- 如果仅仅是判断一个编译器是不是 visual c++，那么使用以下方式即可
``` c
#ifdef _MSC_VER
...
#endif
```
- 如果要判断版本则需要以下方式
``` c
//15.00.20706
#if _MSC_FULL_VER > 150020706
...
#endif
//此宏仅包含前两个版本
#if _MSC_VER > 1700
...
```
# 区分系统
## 通过 CPU 字长 / cmake 区分
在嵌入式开发中，应用代码经常在 PC 上进行模拟，模拟无误后再在目标板上执行。
现在 PC 基本上都是 64 位了，所以可以通过其字长来判断当前代码是在 PC 上运行还是在目标机上运行。

``` c
#if __SIZEOF_POINTER__ == 8
//PC 64bit
#else
//target
#endif
```

> 但是这种方式并不靠谱，比如需要在 64 位机上来指定使用 32 位的形式编译，这种方式就不适用
了。

更为稳妥的办法是基于 cmake 来判断 CPU 架构，然后将配置写入配置文件中：
```cmake
if(${CMAKE_SYSTEM_PROCESSOR} EQUAL "arm")
  list(APPEND STATIC_LIBRARIES "${PROJECT_SOURCE_DIR}/lib/abc_arm.a")
else()
  # 以 32 位形式编译
  add_compile_options(-m32)
  add_link_options(-m32)
  set(ARCH_X86 "1")
  list(APPEND STATIC_LIBRARIES "${PROJECT_SOURCE_DIR}/lib/abc.a")
endif() 
```



## 通过系统类型区分

不同的系统定义了不同的宏：
- windows 
  + _WIN32  
  + _WIN64  
- linux
  + __linux__

---
title: highway 使用体验
tags: 
- framework
categories:
- framework
- highway
date: 2023/3/21
updated: 2023/3/21
layout: false
comments: true
---

[highway](https://github.com/google/highway) 是谷歌开源的 SIMD 代码库，它封装了各个不同平台的底层接口，大大简化了编程难度。

<!--more-->

# 基本认识

在其文档 `quick_reference.md` 中包含了对该库的基本说明，下面是对该文档自己的理解。

## 编译和运行方式

highway 支持动态部署和静态部署的方式：

- 使用动态部署，则是在编译时编译所有 target 的文件，然后在运行时再进行选择对应的 target，这种方式当然会增大运行时开销。

- 使用静态部署，则是已经明确了 target，那么仅需要编译对应 target 就可以了。这种方式不会带来运行时的额外开销。

不管使用哪种部署方式，API 都不需要改变。

## 数据类型

highway 中的向量是由多个`lane`来组合而成，`lane`所拥有的类型有：

- uint##\_t,int##\_t：`##`的值可以是 8，16，32，64
- float##\_t：`##`的值可以是 16，32，64
- bfloat16\_t：二进制浮点数

> float16_t 和 bfloat16_t 仅支持 load、store、与 float32_t 转换的功能

`lane`的数量可以由函数`Lanes(d)`来获取，`lane`的数量很可能无法在编译时确定，所以需要在运行时动态的申请内存（`AllocateAligned(Lanes(d))`）.

> lane 的数量必须是 2 的指数的值

---
title: '[What] Effective Modern C++ ：让 std::thread 是 unjoinable'
tags: 
- c++
date:  2021/10/7
categories: 
- language
- c/c++
- Effective
layout: false
---

`std::thread`具有`joinable`和`unjoinable`两种状态。

`unjoinable`状态出现在以下几种情况中：
- `std::thread` 的默认构造函数：由于没有可执行对象与之关联，所以是 `unjoinable`
- `std::thread` 对象已经被移动：与之关联的可执行对象已被移动
- `std::thread` 已经被 join 过了：已经被 join 过了的可执行对象说明已经执行完成
- `std::thread` 被设置为 detached：意味着分离式运行，退出后资源会被自动回收

<!--more-->
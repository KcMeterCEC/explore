---
title: '[What]Qt c++ 扩展 QML'
tags: 
- Qt
date:  2021/2/25
categories: 
- Qt
- Quick
layout: true
---

学习书籍：
1. [《QmlBook》](http://qmlbook.github.io/index.html)

Qt 版本：Qt 5.12.10

c++ 主要实现业务逻辑，qml/js 实现 UI 逻辑，是比较好的开发组合方式。
<!--more-->

# 理解 Qml 运行时环境

## 工程配置

对于一个纯以 Qt Quick 实现的 UI 逻辑，工程中需要包含的是`quick`模块，而不是`widget`模块。

为了加快`qml`文件的加载速度，它们需要能够被预先编译为字节码，需要满足以下条件：

1. 所有的`qml`文件必须被放置在资源文件系统中

并且 qml 文件以资源的形式被引擎所加载。
---
title: Matlab 的选择与循环
tags: 
- matlab
categories:
- matlab
- hello
date: 2023/9/7
updated: 2023/9/8
layout: true
comments: true
---

认识 Matlab 中的选择和循环。

<!--more-->

# 选择

## 关系表达式

关系运算符与 c/c++ 大同小异，唯一需要注意的是不等于的运算符是 `~=`。

同样的，逻辑运算符中的非，也是`~`。

关于异或，需要使用函数`xor()`。

## if 语句

```shell
if 条件表达式
    语句
else
    语句
end
```

```shell
if 条件1
    语句1
elseif 条件2
    语句2
elseif 条件3
    语句3
else
    语句4
end
```

## switch 语句

```shell
switch 表达式
    case 情况1 表达式
        语句1
    case 情况2 表达式
        语句2
    case 情况3 表达式
        语句3
    otherwise
        语句4
end
```

case 也可以把几种情况包含在一起：

```shell
switch 表达式
    case {情况1 表达式, 情况2 表达式}
        语句1
    case 情况3 表达式
        语句3
    otherwise
        语句4
end
```

## `menu()` 函数

`menu` 函数显示带有多个选项按钮的图形窗口，供用户选择，返回选择的索引。

```matlab
mypick = menu('Pick a pizza', 'Cheese', 'Shroom', 'Sausage');
```

## `is` 函数

is 相关函数用于判断内容是否为真，常常会与`if`语句使用：

- `isletter()`：判断内容是否是字母

- `isempty()`：判断变量是否为空

- `iskeywork()`：名称是否是 MATLAB 关键词

# 循环

## for 循环

```shell
for loopvar = range
    语句
end
```

最简单的方式就是使用冒号运算来指定范围：

```matlabag-0-1h9mjluqtag-1-1h9mjluqt
for i = 1 : 5
    fprintf(' %d\n', i);
end
```

## while 循环

``` shell

while 条件
	语句
end

```

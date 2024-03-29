---
title: 初识 Matlab
tags: 
- matlab
categories:
- matlab
- hello
date: 2023/9/3
updated: 2023/9/4
layout: true
comments: true
---

建立对 Matlab 的最基本的认识。

<!--more-->

# 变量

matlab 中的变量名和 c/c++ 一样，都是以字母开头，后跟字母、数值、下划线，同样会区分大小写。

> 可以通过内置函数 `namelengthmax()` 来获取变量的最大长度。

与变量相关的常用命令：

- `who` : 显示当前已经定义了的变量名称
- `whos` : 显示当前已经定义了的变量的详细信息
- `clear` : 清除所有变量，也可以使用 `clear <var_name>` 来清除指定变量

# 表达式

## format 函数

`format` 命令可以指定表达式的输出格式，默认的输出小数位数为 4，相当于`format short`。

- `format long` : 设置浮点数显示小数位数为 15 位

- `format short` : 设置浮点数显示小数位数为 4 位

- `format loose` : 命令行输出之间有空行

- `format compact` : 命令行输出之间没有空行

## 表达式续行

当表达式一行太长，可以在尾部输入 3 个或更多的点来延续到下一行。

## 运算符

Matlab 的运算符与 c/c++ 一致，但还有：

- \\ : 反向除法，比如 5\\10 = 2
- \^ : 幂运算

## 常量

Matlab 中的常量有：

- pi : 3.141592653...
- i / j : 虚数
- inf : 无穷大
- NaN : 不是一个数

## 类型

在 Matlab 中变量的类型被称为类（classes）。

- 对于浮点数、实数有单精度（single）和双精度（double）
- 对于整数，有 int8,int16,int32 等
- 对于字符，就是 char 类型。**字符和字符串都使用单引号**
- 逻辑类型使用 true/false 来表示

以上类型基本上和 c/c++ 一致。

整数的类型可以通过函数 `intmin()` 和 `intmax()` 来查询。

默认的变量类型就是 `double`，有很多函数可以将值进行类型转换：

- int32(val) : 将值 val 的输出转为 int32 类型

## 随机数

函数 `rand()` 用于产生 0 到 1 范围内的实数。

要产生一个范围从 low 到 high 的实数：

```matlab
low = 3;
high = 5;
v = rand() * (high - low) + low;
```

要产生随机整数，一般配合 `round()` 函数使用来取整：

```matlab
%% 产生 0 ~ 10 的整数
round(rand() * 10)
```

# 字符和编码

在 Matlab 中字符用**单引号**引用，同理也可以使用 `int32('a')` 这种方式对类型进行转换。

可以对字符串进行批量操作：

```matlab
%% 将会得到 bcde
char('abcd' + 1);
```

# 向量和矩阵

向量和矩阵都是用来存储具有**相同类型的**值的集合。

向量可以是行向量和列向量，如果一个向量有 n 个元素，行向量就是 $1*n$，列向量就是$n*1$。相当于一维数组。

矩阵则是二维向量，是行向量和列向量的组合。相当于二维数组。

## 创建及修改行向量

最直接的方法是使用方括号创建，数值之间使用空格或逗号隔离：

```matlab
v = [1 2 3 4];
v = [1,2,3,4];
```

如果元素的值是有规律的，则可以使用冒号操作符：

```matlab
%% 创建 1~5 的行向量，step = 1
v = 1:5;
%% 创建 1~9 的行向量，step = 2
v = 1:2:9;
```

`linspace()`函数也可以创建：

```matlab
%% 创建 3~5 的行向量，共 5 个元素
ls = linspace(3, 15, 5);
```

也可以使用已经存在的向量拼接为新的向量：

```matlab
vv = [v vec];
```

访问元素使用向量名加括号访问，括号中是元素索引（索引从 1 开始）：

```matlab
v = vv(3);
```

同样也可以使用冒号来选择一个范围的索引：

```matlab
v = vv(3:5);
```

还可以使用方括号包含索引的方式：

```matlab
v = vv([1 4 7]);
```

当然也可以对向量元素值进行更改：

```matlab
vv(3) = 10;
```

如果上述索引超出了原来的范围，则会对内容进行扩充。

可以使用空向量对元素进行删除：

```matlab
vv(3)=[];
```

## 创建列向量

创建列向量的直接方法是使用方括号中的分号将值分开：

```matlab
c = [1;2;3;4];
```

但由于它不能使用行向量的冒号操作符，并不那么方便。更为通用的办法是先创建行向量，然后通过矩阵转置来创建列向量：

```matlab
c = 1:4;
r = c';
```

## 创建及修改矩阵

创建矩阵就是创建行列向量：

```matlab
mat = [1 2 3; 4 5 6];
```

不同行也可以用 enter 键来分隔：

```matlab
mat = [1 2 3
4 5 6];
```

同样也可以使用冒号来迭代：

```matlab
mat = [1:3;4:6];
```

也可以通过函数 `rand()`创建随机数矩阵：

```matlab
%% 创建 2 行 2 列的随机数矩阵，元素值在 0~1 范围内
rand(2);

%% 创建 2 行 3 列的随机数矩阵，元素值在 0~1 范围内
rand(2， 3);
```

还可以通过函数 `zeros`创建全 0 矩阵：

```matlab
%% 3x3
zeros(3);
%% 2x4
zeros(2, 4);
```

定位矩阵就是在括号中给出行列的索引即可：

```matlab
mat(2,3);
```

也可以指定一个范围：

```matlab
mat(1:2,2:3);
```

也可以用冒号代表一整行或一整列：

```matlab
%% 获取第一行整个列，也就是获取整个第一行
mat(1,:);
%% 获取第二列整行，也就是获取整个第二列
mat(:,2);
```

如果只使用单个索引，则是使用列的方式来查找：

```matlab
mat = [1 2 3; 4 5 6];
%% 得到 1
mat(1);
%% 得到 4
mat(2);
%% 得到 2
mat(3);
```

修改矩阵元素也是通过索引的方式：

```matlab
mat = [2:4; 3:5];
%% 将第 1 行第 2 列的元素修改为 11
mat(1,2)=11;
%% 修改第二行的元素值为 5~7
mat(2,:)=5:7;
```

扩展矩阵时，需要根据矩阵的行或列长度来扩展：

```matlab
%% 增加第 4 列
mat(:,4) = [9 2]';
%% 增加第 4 行
mat(4,:) = 2:2:8;
```

同样也可以通过空向量删除一整行或一整列：

```matlab
mat(:,4) = [];
```

## 维度

- `length()`返回向量元素的个数，对于矩阵则返回行数或列数中的较大值

- `size()`返回矩阵的行数和列数。

- `numel()`返回数组中所有元素的个数

```matlab
%% 返回矩阵行列并存储于行向量中
[r c]=size(mat);
```

内置表达式`end`对于向量表示最后一个元素，对于矩阵则表示最后一行或最后一列：

```matlab
mat=[1:3;4:6]';
%% 返回最后一行第一列的元素
mat(end,1)
%% 返回最后一列第二行的元素
mat(2,end)
```

除了矩阵的转置，还有一些内置函数可以改变矩阵的维度或格局：

- `reshape()`:改变矩阵的维数

```matlab
%% 产生一个 3 行 4 列的矩阵
mat = rand(3, 4);
%% 重新排列维 2 行 6 列的矩阵
v = reshape(mat, 2, 6);
```

- `fliplr()` 将矩阵左右翻转
- `flipud()` 将矩阵上下翻转
- `rot90()` 将矩阵逆时针选择 90 度
- `repmat()` 将矩阵复制成更大的矩阵

```matlab
%% 复制矩阵 v 为两行一列的更大矩阵
repmat(v, 2, 1)
```

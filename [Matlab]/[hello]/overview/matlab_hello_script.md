---
title: 初识 Matlab 脚本
tags: 
- matlab
categories:
- matlab
- hello
date: 2023/9/5
updated: 2023/9/7
layout: true
comments: true
---

初步认识 Matlab 脚本。

<!--more-->

# 输入与输出

## 输入函数

`input()`就是最简单的输入函数：

```matlab
% 从终端获取输入并赋值给变量 rad
rad = input('Enter the radius: ');

% 将输入以字符串的形式赋值给 letter，用户也可以在输入参数中加入引号，而不用在后面加入参数 's'
letter = input('Enter string: ', 's');
```

## 输出函数

- `disp()`：输出字符串、表达式、变量的结果
- `fprintf()`：和 c/c++ 一样，格式化的输出

方便之处在于，它们可以直接输出向量和矩阵：

```matlab
vec = 2:5;
fprintf('%d', vec);
fprintf('%d %d %d %d', vec);
```

# 绘图

## plot 函数

```matlab
x = 11;
y = 48;
% 以红色的 * 绘制点
plot(x, y, 'r*');
% 改变坐标的范围，前两个是 x 轴的最小和最大值，后两个是 y 轴的最小和最大
axis([9 12 35 55]);
% 加入 x y 轴的注释
xlabel('Time');
ylabel('Temperature');
% 添加标题
title('Time and Temp');
```

关于图形的定制有：

- 颜色
  
  + `b` blue（蓝色）
  
  + `c` cyan（青色）
  
  + `g` green（绿色）
  
  + `k` black（黑色）
  
  + `m` magenta（品红）
  
  + `r` red（红色）
  
  + `y` yellow（黄色）

- 点的标记
  
  - `o` circle（圆）
  
  - `d` diamond（菱形）
  
  - `p` pentagram（五角星）
  
  - `+` plus（加号）
  
  - `.` point（点）
  
  - `s` square（平方）
  
  - `*` star（星号）
  
  - `v` down trangle（下三角）
  
  - `<` left triangle （左三角）
  
  - `>` right trangle（右三角）
  
  - `^` up trangle（上三角）
  
  - `x` x-mark（x 标记）

- 连线的线型
  
  + `--` dashed（短线）
  
  + `-.` dash dot（短线点）
  
  + `:` dotted（虚线）
  
  + `-` solid（实现）

- 辅助函数
  
  + `clf` 清除图像窗口
  
  + `figure` 创建一个新的空图形窗口
  
  + `hold on`,`hold off` 在两个命令中，绘制多个曲线到同一张图
  
  + `legend` 将图中曲线按照画图顺序给与字符串说明
  
  + `grid on`,`grid off` 在两个命令中的图像显示网格

## bar 柱状图

```matlab
y1 = [2 11 6 9 3];
y2 = [4 5 8 6 2];

figure(1);
bar(y1);

figure(2);
plot(y1,'k');
hold on;
plot(y2, 'ko');
grid on;
legend('y1', 'y2');
```

# 文件输入与输出

## save() 向文件写数据

```matlab
% 以 ASCII 的格式存储矩阵数据

mymat = rand(2, 3);
save('testfile.dat', 'mymat', '-ascii');

% 加上 -append 就是以附加的形式写入
save('testfile.dat', 'mymat', '-ascii', '-append');
```

## load() 从文件读取

load 函数仅能读出列数相同的文件。

```matlab
mymat = load('testfile.dat');
```

# 返回单个值的用户自定义函数

一般是将每个函数都单独保存在一个 M 文件中，并且函数名和 M 文件名一致。

```shell
function outputargument = functionname(argument1, [argument2], ...)
% Comment describing the function
Statements here;
```

比如下面这个函数（函数名一般使用小写字母）：

```matlab
function area = calcarea(rad)
% This function calculates the area of a circle
area = pi * rad * rad;
```

可以通过 `type` 命令输出脚本内容，`help` 命令输出函数说明。

在命令行和脚本中直接调用函数即可。

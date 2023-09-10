---
title: Matlab 的向量化代码
tags: 
- matlab
categories:
- matlab
- hello
date: 2023/9/10
updated: 2023/9/10
layout: true
comments: true
---

向量化代码可以降低使用循环的必要性。

<!--more-->

# 向量和矩阵的运算

假设要将矩阵的元素都乘以一个值，使用`for`循环可以这样写：

```matlab
vec = [1,2,3;4,5,6];
[r,c] = size(vec);

for row = 1:r
    for column = 1:c
        vec(row, column) = vec(row, column) * 3;
    end
end
```

但更为简洁的方式是使用点乘：

```matlab
vec = vec .* 3;
```

对于向量之间的运算也是如此：

```matlab
r1 = [1, 2, 3];
r2 = [4, 5, 6];
rc = r1 .* r2;
```

同样的，对于函数来说也是如此，传入向量相当于一个`for`循环将向量依次传入函数：

```matlab
function area = calcarea(rad)
% This function calculates the area of a circl
% 注意这里得使用点乘
area = pi * rad .* rad;
```

# 逻辑向量

假设要对向量的元素进行逐个判断，那也可以使用向量运算：

```matlab
vec = [1, 3, 4, 5, 6];
% 逐个判断向量元素是否大于 5，并将输出结果赋值到变量 ret
ret = vec > 5;
% 通过逻辑索引，获取向量中元素值大于 5 的元素
vec(ret);
```

matlab 提供了一些内置的逻辑函数：

- `any()`：如果向量中的存在非零的元素，返回真，否则返回假

- `all()`：向量中所有元素都是非零的，才返回真，否则返回假

- `find()`：返回满足条件的向量中元素的索引

```matlab
vec = [1, 2, 3, 4, 5, 6];
find(vec > 3);
```

matlab 也有对矩阵进行逐元素的“或”和“与”操作的操作符，和 c/c++ 一致，对应于`|`和`&`。

# 计时函数

- `tic`：启动定时器开始计时

- `toc`：计算计时器结果并输出

使用以上两个函数就可以计算出一段代码运行花了多长时间。





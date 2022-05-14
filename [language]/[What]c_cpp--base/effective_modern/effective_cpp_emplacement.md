---
title: Effective C++ ：考虑用 emplacement 替代 insertion
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/5/14
updated: 2022/5/14
layout: true
comments: true
---

对容器的 insertion 操作，比如 `push_back`，有的时候效率并不高。

<!--more-->

比如：

```cpp
std::vector<std::string> vs;         
vs.push_back("xyzzy");               
```

上面这个`push_back`真实的执行流程如下：

1. 由于输入的是字面值，需要为其创建一个临时对象。这个时候会调用`std::string`的构造函数
2. 由于是临时对象，所以会调用对应的移动构造函数，来在 vector 中创建一个对象
3. 最后释放临时对象占用的内存，那么就会调用析构函数

这个使用使用`emplace_back`则是直接调用构造函数，在 vector 中创建对象，也就没有了步骤 1，3的性能消耗：

```cpp
vs.emplace_back("xyzzy");
```

当下面的条件都满足时，使用 emplacement 操作比插入操作更合理，效率更高：

- 需要创建一个临时对象加入到容器时，如上面所示
- 加入数据的类型与容器包含数据的类型不一致
  > 因为类型不一致，使用 emplacement 调用构造函数即可。如果用 push_back 这种则会创建临时对象
- 容器允许加入相同的值
  > 比如 std::set, std::map 这类容器不允许有重复的值，如果使用 emplacement 加入相同的值，则会先创建一个临时变量，然后又将其销毁。

比如下面这个情况就是 emplacement 快于 push_back：

```cpp
vs.emplace_back("xyzzy");   // construct new value at end of
                            // container; don't pass the type in
                            // container; don't use container
                            // rejecting duplicates
vs.emplace_back(50, 'x');   // ditto
```
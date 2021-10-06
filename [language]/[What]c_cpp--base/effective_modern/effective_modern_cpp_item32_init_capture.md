---
title: '[What] Effective Modern C++ ：使用初始捕获来完成移动对象的闭包'
tags: 
- c++
date:  2021/10/6
categories: 
- language
- c/c++
- Effective
layout: true
---

如果有些对象（比如容器）以拷贝的方式形成闭包，其效率太低了。这种情况下应该以移动的方式来形成闭包。
> c++14 有现成的语法支持，称之为初始捕获（init capture）

<!--more-->

# 基于 c++ 14 的初始捕获

所谓的初始捕获，其实简单来讲就是：使用局部变量来初始化 lambda 表达式闭包中的变量：

```cpp
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <array>

int main(int argc, char *argv[]) {

    std::vector<int> vec = {1, 2, 3, 4, 5};

    // c++ 14 支持将 vec 内容移动给 v 以形成闭包
    auto func = [v = std::move(vec)]() {
        std::cout << "The contenes of v are:\n";

        for (auto val : v) {
            std::cout << val << ",";
        }

        std::cout << "\n";
    };

    func();


    // 移动后的 vec 则不包含内容了
    std::cout << "vec size " << vec.size() << "\n";

    return 0;
}
```

# 基于 c++ 11 的初始捕获

由于 c++ 11 没有语法支持，所以需要借助`std::bind`来完成这个需求：

```cpp
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <array>
#include <functional>

int main(int argc, char *argv[]) {

    std::vector<int> vec = {1, 2, 3, 4, 5};

    auto func = std::bind(
            [](const std::vector<int>& v) {

                std::cout << "The contenes of v are:\n";

                for (auto val : v) {
                    std::cout << val << ",";
                }

                std::cout << "\n";
            },
            std::move(vec)
            );

    func();


    std::cout << "vec size " << vec.size() << "\n";

    return 0;
}
```




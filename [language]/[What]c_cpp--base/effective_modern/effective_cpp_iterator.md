---
title: Effective C++ ：const iterators 优于 iterators
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/5/4
updated: 2022/5/4
layout: true
comments: true
---

除非是需要修改容器元素的内容，否则在使用迭代器的时候，应该使用其`const`版本，也就是指向`const`类型元素的指针，以避免误操作。

<!--more-->

# 对于容器类，直接使用其成员函数

```cpp
#include <vector>
#include <iostream>

int main(void) {
    std::vector<int> val = {1, 2, 3, 4, 5};

    std::cout << "The contents of vector are:\n";
    for (auto it = val.cbegin(); it != val.cend(); ++it) {
        std::cout << *it << "\n";
    }
    std::cout << "\n";

    return 0;
}
```

# 对于非容器类，使用标准库提供的非成员函数

在 c++14 及以后的版本中，标准库才提供了`cbegin()、cend()、`这些函数：

```cpp
#include <vector>
#include <iostream>

int main(void) {
    int val[] = {1, 2, 3, 4, 5};

    std::cout << "The contents of vector are:\n";
    for (auto it = std::cbegin(val); it != std::cend(val); ++it) {
        std::cout << *it << "\n";
    }
    std::cout << "\n";

    return 0;
}
```

如果想要在 c++11 中使用，那就需要自定义函数：

```cpp
#include <vector>
#include <iostream>

/**
 * @brief : 由于传入的是 const C& 类型参数，模板推导返回的类型也会加上 const 限定符
 */
template <class C>
auto cbegin(const C& container)->decltype(std::begin(container)) {
    return std::begin(container);
}

template <class C>
auto cend(const C& container)->decltype(std::end(container)) {
    return std::end(container);
}


int main(void) {
    int val[] = {1, 2, 3, 4, 5};

    std::cout << "The contents of vector are:\n";
    for (auto it = cbegin(val); it != cend(val); ++it) {
        std::cout << *it << "\n";
    }
    std::cout << "\n";

    return 0;
}
```
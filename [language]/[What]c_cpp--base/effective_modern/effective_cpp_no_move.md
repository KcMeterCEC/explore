---
title: Effective C++ ：谨慎使用移动操作
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/5/12
updated: 2022/5/12
layout: true
comments: true
---

移动语义是 c++11 最重要的特性，但不是什么情况下都可以使用移动语义。
所以写代码的时候不能假设就有移动语义而忽视性能方面应该注意的问题。

> 比如只有当一个类没有显示的定义拷贝、移动、析构函数时，编译器才会生成一个默认的移动构造、拷贝函数。
>
> 或者是一个类的成员变量类禁止了移动操作，那么也不会生成默认移动函数。

<!--more-->

# std::array

`std::vector`，`std::deque`等这类容器，它们的内容实际上是存储于堆上，内部是由指针来指向内容所在的内存，所以是可以高效使用移动语义的。

将一个`std::vector`的内容拷贝到另一个`std::vector`，也就是将原指针的值拷贝到目的指针，且原指针的地址设为空。

> 当然，之后的代码就不能再使用原指针了。

```cpp
std::vector<Widget> vw1;
// put data into vw1
…
// move vw1 into vw2. Runs in
// constant time. Only ptrs
// in vw1 and vw2 are modified
auto vw2 = std::move(vw1);
```

但`std::array`这个容器则与其他容器不同，它内部并没有指针来指向其内容。而是内容就直接存储于该类的对象种的。在`std::array`的[说明页面](https://en.cppreference.com/w/cpp/container/array)也可以发现，它提供的仅有拷贝构造、拷贝赋值函数。

> 既然有拷贝赋值函数了，那么编译器也就不会生成移动函数了。

所以，即使给`std::array`使用了`std::move`也仅仅是调用的拷贝构造：

```cpp
std::array<Widget, 10000> aw1;
// put data into aw1
…
// move aw1 into aw2. Runs in
// linear time. All elements in
// aw1 are moved into aw2
auto aw2 = std::move(aw1);
```

示例如下：

先使用`std::vector`这不会触发`Hello`类的拷贝函数：

```cpp
#include <iostream>
#include <string>
#include <utility>
#include <vector>

class Hello {
    public:
        Hello() {
            std::cout << "Default construct!\n";
        }
        Hello(const Hello& obj) {
            std::cout << "Copy construct!\n";
        }
        Hello operator=(const Hello& obj) {
            std::cout << "Copy assignment!\n";

            return *this;
        }
        Hello(Hello&& obj) noexcept {
            std::cout << "Move construct!\n";
        }
        Hello operator=(Hello&& obj) noexcept {
            std::cout << "Move assignment!\n";

            return *this;
        }
};

int main(int argc, char *argv[]) {

    std::vector<Hello> vw1(10);

    std::cout << "construct vw2:\n";

    std::vector<Hello> vw2(std::move(vw1));

    std::cout << "vw2 size = " << vw2.size() << "\n";

    return 0;
}
```

其输出如下：

```shell
Default construct!
Default construct!
Default construct!
Default construct!
Default construct!
Default construct!
Default construct!
Default construct!
Default construct!
Default construct!
construct vw2:
vw2 size = 10
```

可以看到，仅仅是在最开始创建了对象，而接下来的移动操作并不会调用`Hello`类的拷贝、移动操作。因为直接是进行指针赋值了。

而如果使用`std::array`则不同了：

```cpp
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include <array>

class Hello {
    public:
        Hello() {
            std::cout << "Default construct!\n";
        }
        Hello(const Hello& obj) {
            std::cout << "Copy construct!\n";
        }
        Hello operator=(const Hello& obj) {
            std::cout << "Copy assignment!\n";

            return *this;
        }
        Hello(Hello&& obj) noexcept {
            std::cout << "Move construct!\n";
        }
        Hello operator=(Hello&& obj) noexcept {
            std::cout << "Move assignment!\n";

            return *this;
        }
};

int main(int argc, char *argv[]) {

    std::array<Hello, 5> vw1 = {Hello(), Hello(), Hello(), Hello(), Hello()};

    std::cout << "construct vw2:\n";

    std::array<Hello, 5> vw2(std::move(vw1));

    std::cout << "vw2 size = " << vw2.size() << "\n";

    return 0;
}
```

其输出如下：

```shell
Default construct!
Default construct!
Default construct!
Default construct!
Default construct!
construct vw2:
Move construct!
Move construct!
Move construct!
Move construct!
Move construct!
vw2 size = 5
```

可以看到，虽然使用了`std::move`，但由于`std::array`并没有移动函数，所以只能一个元素一个元素的拷贝。

> **但这里要注意，元素如果提供了移动操作，则会使用元素的移动函数。**

相比`std::vector` 的 O(1) 时间复杂度，`std::array`就是 O(n) 的时间复杂度。

# std::string

`std::string`对于短字符串会使用 SSO（small string optimization），也就是这些短字符串会直接存储在其对象中。

> 长字符串才存储于堆中，因为要使用堆就会涉及到堆内存的申请，这也会影响性能。对于短字符串就不划算了。

# 总结

以下这些情况都不能使用，或需要谨慎使用移动语义：

- 当一个类不提供移动操作时，那么就会使用其拷贝操作
- 当移动操作性能不高于拷贝操作性能时：比如短字符串的`std::string`
- 无法使用移动操作时：比如某些操作不能使用可能会抛出异常的移动函数
- 当被移动对象是左值时：有些情况下需要被移动对象是右值

> 比如左值接下来还会被使用等等
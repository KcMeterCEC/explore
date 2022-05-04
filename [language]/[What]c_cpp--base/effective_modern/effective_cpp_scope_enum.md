---
title: Effective C++ ：作用域枚举优于非作用域枚举
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/5/3
updated: 2022/5/4
layout: true
comments: true
---

简单来讲就是对于枚举类型，也需要将其存放于命名空间中，以避免枚举中元素对外部标识符的污染。

<!--more-->

# 非作用域枚举对标识符的污染

```cpp
#include <vector>
#include <iostream>

enum Color {
  kWhite,
  kBlack,
  kRed,
};

int kBlack = 1;

int main(void) {

    return 0;
}
```

比如像上面这段代码，由于枚举中已经具有`kBlack`常量，导致我们想定义一个`kBlack`变量是编译不通过的。上面这个代码很简单，一般人也不会犯错。但是当代码量大起来的时候，在头文件中有这种枚举，那么就还是会比较容易出现这类冲突。

# 使用作用域枚举解决标识符污染

```cpp
#include <vector>
#include <iostream>

enum class Color {
  kWhite,
  kBlack,
  kRed,
};

int kBlack = 1;

int main(void) {

    auto kRed = Color::kRed;
    auto kWhite = Color::kWhite;

    return 0;
}
```

如上所示，将枚举常量放入`Color`作用域中，就不会与外部标识符有冲突。

# 作用域枚举是强类型

使用非作用域枚举是可以与其它变量进行比较的（编译器会将其隐式转换为整型），但是使用作用域枚举与其他类型进行比较就会报错：

```cpp
#include <vector>
#include <iostream>

enum class Color {
  kWhite,
  kBlack,
  kRed,
};

int kBlack = 1;

int main(void) {

    auto kRed = Color::kRed;
    auto kWhite = Color::kWhite;

    //直接使用 kWhite 与 5 进行比较是编译不过的，除非显示的进行转换
    if (static_cast<int>(kWhite) < 5) {

    }

    return 0;
}
```

# 作用域枚举可以使用前置声明

下面这段代码在 g++ 中编译不会通过，使用作用域枚举便可以编译通过：

```cpp
#include <vector>
#include <iostream>

enum Color;

enum Color {
  kWhite,
  kBlack,
  kRed,
};

int main(void) {

    auto Red = kRed;
    auto White = kWhite;

    return 0;
}
```

由于作用域枚举可以使用前置声明，那就可以在`cc`文件中定义该枚举，而在其它文件中使用前置声明即可。这样可以减短因枚举内容改变而需要重新编译的时间。

> 由于编译器知道枚举的长度，所以在使用前置声明的函数中，可以直接创建一个枚举对象。

```cpp
enum class Status;                   // forward declaration
void continueProcessing(Status s);   // use of fwd-declared enum
```

默认的类型是`int`，用户也可以显示指定其存储类型：
```cpp
enum class Status: std::uint32_t;
```

# 在需要使用索引的地方使用非作用域枚举

在需要使用索引的地方，使用枚举常量能够提高代码的可读性。

但由于作用域枚举不允许类型转换，那么这种情况下使用非作用域枚举是比较好的选择。

为了避免命名污染，那么使用一个名称空间将该非作用域枚举包裹一次即可：

```cpp
#include <vector>
#include <iostream>
#include <tuple>

namespace TupleIndex {
    enum Element{
      NAME,
      ADDR,
      AGE
    };
}

int main(void) {

    using UserInfo = std::tuple<
                    std::string, // name
                    std::string, // addr
                    std::size_t //age
                    >;
    UserInfo may = {"May", "London", 30};

    std::cout << "Name " << std::get<TupleIndex::NAME>(may) <<
                 " ,addr " << std::get<TupleIndex::ADDR>(may) <<
                 " ,age " << std::get<TupleIndex::AGE>(may) <<
                 "\n";

    return 0;
}
```

如果使用作用域枚举，就需要进行一次显示转换：

```cpp
#include <vector>
#include <iostream>
#include <tuple>

enum class Element {
  NAME,
  ADDR,
  AGE
};

int main(void) {

    using UserInfo = std::tuple<
                    std::string, // name
                    std::string, // addr
                    std::size_t //age
                    >;
    UserInfo may = {"May", "London", 30};

    std::cout << "Name " << std::get<static_cast<std::size_t>(Element::NAME)>(may) <<
                 " ,addr " << std::get<static_cast<std::size_t>(Element::NAME)>(may) <<
                 " ,age " << std::get<static_cast<std::size_t>(Element::NAME)>(may) <<
                 "\n";

    return 0;
}
```

这实在是太麻烦了！
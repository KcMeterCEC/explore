---
title: Effective  C++ ：const,enum,inline 优于 define
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/4/10
updated: 2022/4/10
layout: true
comments: true
---
 
宏在 c++ 中要尽可能少的使用，在[google c++ 编码规范中](https://zh-google-styleguide.readthedocs.io/en/latest/google-cpp-styleguide/others/#preprocessor-macros)也是建议使用宏要谨慎。

<!--more-->

# 宏的弊端

## 宏无法产生符号

由于宏是在预编译过程中进行替换的，那么在随后生成的目标文件/可执行文件中，就不会包含有该宏的符号。这在某些调试的情况下，不那么方便。

比如下面的示例，先使用宏：

```cpp
#include <iostream>

#define ASPECT_RATION (1.653f)

int main(void) {

    float val = ASPECT_RATION;

    return 0;
}
```

那么在符号表中无法找到该符号：

```shell
~/lab/cpp$ readelf -s a.out | grep "ASPECT_RATION"
```

下面使用 `const` 变量来替换宏：

```cpp
#include <iostream>

const float kAspectRation = 1.653f;

int main(void) {

    float val = kAspectRation;

    return 0;
}
```

这样就可以找到符号表：

``` shell
~/lab/cpp$ readelf -s a.out | grep "kAspectRation"
    37: 0000000000000838     4 OBJECT  LOCAL  DEFAULT   16 _ZL13kAspectRation
```

## 写宏时需要小心翼翼

宏展开后的真实代码和我们以为的代码可能会不同，遇到这种问题还需要去查看预编译后的文件才能清楚。

所以写宏的时候需要小心翼翼，尤其是宏内容较复杂，有多个换行的情况下。这无疑是增加了程序员的负担。

```cpp
#include <iostream>

#define MAX(a, b) ((a) > (b) ? (a) : (b))

int main(void) {

    int a = 10;
    int b = 8;

    std::cout << "The maximum is " << MAX(++a, b) << "\n";


    return 0;
}
```

比如上面这个宏，除了要注意使用括号外，最终得到的结果也是非预期的。
> 以为返回的是 11，结果返回了 12……

## 宏没有类内范围性

比如我们只想在类内使用该宏，但其实它的作用范围已经超出了宏：

```cpp
#include <iostream>

class GamePlayer {
    public:
        int GetArraySize(void) const;
    private:
        #define NUM_TURNS   (5)
        int scores_[NUM_TURNS];
};

int GamePlayer::GetArraySize(void) const{
    return sizeof(scores_);
}

int main(void) {

    GamePlayer game_player;

    std::cout << "size of array is " << game_player.GetArraySize() << "\n";
    std::cout << "macro value " << NUM_TURNS << "\n";

    return 0;
}
```

# 使用常量替换 `#define`

## 全局常量

通常使用常量来替换`#define`时，为了常量可以被多个文件所使用，需要将其放在头文件内。

对于想要定义常量字符串，有两种做法：

- 定义指向常量字符串的常量指针：

  ```cpp
  const char* const kAuthorName = "Scott Meyers";
  ```

- 定义常量`string`对象：

  ```cpp
  const std::string kAuthorName("Scott Meyers");
  ```

定义常量`string`对象是更加合适的方法，因为不仅由于其不是指针而更好操作外，而且它还具有一系列成员函数，能满足更多的适用场合。

## 类内的常量

当仅需要在类内定义一个常量时，则需要在类的内部使用`static const`来修饰它：

> `static`修饰是为了在多个类中，仅占用一个变量的空间。

```cpp
#include <iostream>

class GamePlayer {
    public:
        int GetArraySize(void) const;
    private:
    	// 如果不取 static 常量的地址，则无需提供定义
        static const int num_turns_ = 5;
        int scores_[num_turns_];
};

int GamePlayer::GetArraySize(void) const {
    return sizeof(scores_);
}

int main(void) {

    GamePlayer game_player;

    std::cout << "size of array is " << game_player.GetArraySize() << "\n";

    return 0;
}
```

还有一种方式是使用枚举来完成常量的定义：

```cpp
#include <iostream>

class GamePlayer {
    public:
        int GetArraySize(void) const;
    private:
        enum {kNumTurns = 5};
        int scores_[kNumTurns];
};

int GamePlayer::GetArraySize(void) const {
    return sizeof(scores_);
}

int main(void) {

    GamePlayer game_player;

    std::cout << "size of array is " << game_player.GetArraySize() << "\n";

    return 0;
}
```

# 使用内联函数替代宏函数

使用`inline`函数则可以避免宏运行时无法预期的问题：
> 其实用不用`inline`在绝大部分情况下都不影响。
> 所以简单粗暴的说应该是，使用函数来代替宏函数。

```cpp
#include <iostream>

template<typename T>
inline T Max(const T& a, const T&b) {
    return (a > b ? a : b);
}

int main(void) {
    int a = 10, b = 0;

    // 由于调用的是函数，所以这里 a 只会被加一次，完全符合语义
    std::cout << "max is " << Max(++a, b) << "\n";

    std::cout << "value of a is " << a << "\n";

    return 0;
}
```
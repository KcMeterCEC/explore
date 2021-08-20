---
title: '[What] Effective  C++ ：尽可能使用 const'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---
[谷歌 c++ 编码规范](https://zh-google-styleguide.readthedocs.io/en/latest/google-cpp-styleguide/others/#const)也比较推崇尽量使用`const`。
<!--more-->

# `const`对指针的修饰

`const`对指针的修饰就看它与星号的位置关系：

- 如果`const`在星号左边，则被指对象是常量：`const int* p = &val`
- 如果`const`在星号右边，则指针自身是常量：`int* const p = &val`
- 如果`const`在星号左右都有，则被指对象和指针都是常量：`const int* const p = &val`

在使用迭代器时，如果不希望改变容器元素的内容，那么就应该使用`const_iterator`。

当函数要返回一个指针或引用时，需要考虑是否允许用户可以修改此返回值，如果不允许修改，则需要加上`const`限定。

# `const`成员函数

当成员函数不会修改成员变量时，应该为其加上`const`限定：

- 一来可以让接口更为明确
- 二来可以操作`const`对象

```cpp
#include <iostream>

class Hello{
    public:
        void print(void){
            std::cout << "non const!\n";
        }
        void print(void) const{
            std::cout << "const!\n";
        }
};

int main(void){
    Hello hello;

    hello.print();

    const Hello chello;
	// 假如没有 const 版本的 print，则此行代码无法通过编译
    chello.print();

    return 0;
}
```

**需要理解的是**：`const`仅限定该成员函数不会改变成员变量，但被该成员变量指向的内存还是有可能被改变。

```cpp
class CTextBlock{
  public:
    char& operator[](std::size_t position) const{
        return ptext[position];
    }
  private:
    char* ptext;
};

// 使用
const CTextBlock cctb("Hello");
char* pc = &cctb;
// ptext 指向的内存被改变了
*pc = 'J';
```

当一个类需要实现`const`和`non-const`两个版本函数时，为了避免代码重复，应该使`non-const`版本调用`const`版本。

> 为`non-const`添加`const`限定，使用`static_cast`即可，这是安全的。
>
> 而要去除`const`显示，使用`const_cast`，使用前需要谨慎。

```cpp
#include <iostream>

class Hello{
    public:
        void print(void) const{
            std::cout << "const hello world!\n";
        }
        void print(void){
            std::cout << "cast to non const\n";
            // 将对象 cast 为 const 型，然后就会调用到 const 限定的 print
            static_cast<const Hello>(*this).print();
        }
};

int main(void){
    const Hello chello;

    chello.print();

    Hello hello;

    hello.print();
    return 0;
}
```


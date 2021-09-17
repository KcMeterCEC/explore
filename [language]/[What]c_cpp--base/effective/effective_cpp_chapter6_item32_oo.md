---
title: '[What] Effective  C++ ：继承与面向对象设计'
tags: 
- c++
date: 2021/9/17
categories: 
- language
- c/c++
- Effective
layout: true
---
继承与面向对象设计有很多细节需要关注。
<!--more-->

# 公开继承（public）是 is-a 的关系
is-a 的关系即说明：
- 每个继承类对象同时也是一个基类对象，反之不成立
- 基类比继承类表现出更一般化的概念，而继承类比基类表现出更特殊化的概念
- 基类对象可以派上用场的任何地方，继承类对象一样可以派上用场，反之不成立

在需要继承的场合，都需要认真思考是否真的有必要继承。

# 避免遮掩继承而来的名称

继承类的名称会遮掩基类内的名称，除了多态的应用，其他情况下将会增加程序员的负担。

> 所以最好不要这样使用，除了多态以外，其他应该用不同的名称。

比如下面这样的定义：

```cpp
#include <iostream>

class Base {
    public:
        virtual void mf1() = 0;
        virtual void mf1(int val_) {
            std::cout << "Base class mf1\n";
        }
        virtual void mf2() {
            std::cout << "Base class mf2\n";
        }
        void mf3() {
            std::cout << "Base class mf3\n";
        }
        void mf3(double val_) {
            std::cout << "Base class mf3 with double\n";
        }
};

class Derived : public Base {
    public:
        virtual void mf1() {
            std::cout << "Derived class mf1\n";
        }
        void mf3() {
            std::cout << "Derived class mf3\n";
        }
        void mf4() {
            std::cout << "Derived class mf4\n";
        }
};

int main()
{
    Derived d;

    d.mf1();
    d.mf1(10); // error，派生类遮掩了基类函数
    d.mf2();
    d.mf3();
    d.mf3(20); // error, 派生类遮阳了基类函数

    return 0;
}
```

如果想要正确调用，则应该使用`using`：

```cpp
#include <iostream>

class Base {
public:
    virtual void mf1() = 0;
    virtual void mf1(int val_) {
        std::cout << "Base class mf1\n";
    }
    virtual void mf2() {
        std::cout << "Base class mf2\n";
    }
    void mf3() {
        std::cout << "Base class mf3\n";
    }
    void mf3(double val_) {
        std::cout << "Base class mf3 with double\n";
    }
};

class Derived : public Base {
public:
    using Base::mf1;
    using Base::mf3;
    virtual void mf1() {
        std::cout << "Derived class mf1\n";
    }
    void mf3() {
        std::cout << "Derived class mf3\n";
    }
    void mf4() {
        std::cout << "Derived class mf4\n";
    }
};

int main()
{
    Derived d;

    d.mf1();
    d.mf1(10);
    d.mf2();
    d.mf3();
    d.mf3(20);
    return 0;
}
```

# 区分接口继承和实现继承

- 接口继承和实现继承不同。在 public 继承下，derived classes 总是继承 base class 的接口。
- pure virtual 函数只具体指定接口函数
- 简朴的非纯 virtual 函数具体指定接口继承及其缺省实现继承
- non-virtual 函数具体指定接口继承以及强制性实现继承。

# 考虑 virtual 函数以外的其他选择

`virtual`函数的替代方案：

- 使用`non-virtual interface（NVI）`手法，以`public non-virtual`函数调用 private 或 protected 的 virtual 函数（子类重写该 virtual 函数），这算是模板方法的另类实现。
- 将`virtual`函数替换为“函数指针成员变量”，这有点类似于策略模式。
- 以`std::function`替换`virtual`以可以调用可被调用对象，相比上面的方法更为灵活
- 使用传统的策略模式

# 不要重新定义继承而来的`non-virtual`函数

由于`non-virtual`函数是静态绑定的，所以无法获得多态的效果：

```cpp
#include <iostream>

class Base {
    public:
        void Hello(void) {
            std::cout << "Hello base!\n";
        }
};

class Derived : public Base {
    public:
        void Hello(void) {
            std::cout << "Hello derived!\n";
        }
};

int main()
{
    Derived d;

    Base* p_b = &d;
    Derived* p_d = &d;

    p_b->Hello();
    p_d->Hello();

    return 0;
}
```

上面这段代码的输出是：

```shell
Hello base!
Hello derived!
```

这种方式即违反了继承的`is-a`思想，也会给使用者带来误导。

# 绝不重新定义继承而来的缺省参数值

虽然`virtual`函数是动态绑定，但**缺省参数值却是静态绑定！**

也就是说可能会在调用一个定义于 derived class 内的 virtual 函数的同时，却使用 base class 为它所指定的缺省参数值。

比如下面这段代码：

```cpp
#include <iostream>
#include <string>

class Base {
    public:
        virtual void Hello(const std::string &str = "base") {
            std::cout << "[Base] Hello " << str << " \n";
        }
};

class Derived : public Base {
    public:
        void Hello(const std::string &str = "derived") override {
            std::cout << "[Derived] Hello " << str << " \n";
        }
};

int main()
{
    Derived d;

    Base* p_b = &d;
    Derived* p_d = &d;

    p_b->Hello();
    p_d->Hello();

    return 0;
}
```

输出的是：

```shell
[Derived] Hello base
[Derived] Hello derived
```

所以，最好不好以这种方式来做。

一个解决办法是使用`non-virtual`来使用缺省值，以始终保证`virtual`没有缺省值：

```cpp
#include <iostream>
#include <string>

class Base {
    public:
        void Hello(const std::string &str = "base") const {
            DoHello(str);
        }
    private:
        virtual void DoHello(const std::string &str) const {
            std::cout << "[Base] DoHello " << str << " \n";
        };
};

class Derived : public Base {
    public:
    private:
        void DoHello(const std::string &str) const override {
            std::cout << "[Derived] DoHello " << str << " \n";
        }
};

int main()
{
    Derived d;

    Base* p_b = &d;
    Derived* p_d = &d;

    p_b->Hello();
    p_d->Hello();

    return 0;
}
```

# 组合优于继承

组合有两种意义：

1. `has-a`：一个类需要包含其他类以实现满足现实抽象意义

2. `is-implemented-in-terms-of`：这相当于是一个适配器，以使用被包含对象的部分功能实现简单易用新的类

   > 比如 stack 就是基于 deque 来实现的适配器

之所以说组合优于继承，是因为很多时候它们并不是`is-a`的关系，这个时候用组合才是最合理的方式。

# 慎用 private 继承

谷歌编码规范中也[明确使用 public 继承](https://zh-google-styleguide.readthedocs.io/en/latest/google-cpp-styleguide/classes/#inheritance)。

因为：

- 当 classes 之间的继承关系是 private 时，编译器不会自动将一个 derived class 对象转换为一个 base class 对象。
- 由 private base class 继承而来的所有成员，在 derived class 中都会变成 private 属性。即使它们在 base class 中原本是 protected 或 public 属性。

```cpp
#include <iostream>
#include <string>

class Base {
    public:
        virtual void Hello() const {
            std::cout << "Base hello!\n";
        }
};

// 如果此处是 public 继承，则可以按预期的运行
class Derived : private Base {
    public:
        void Hello() const override {
            std::cout << "Derived hello!\n";
        }
};

static void PrintHello(const Base& obj) {
    obj.Hello();
}

int main()
{
    Base base;
    Derived derived;

    PrintHello(base);
    PrintHello(derived);


    return 0;
}
```

# 慎用多重继承

谷歌编码规范中也是[不建议用多重继承](https://zh-google-styleguide.readthedocs.io/en/latest/google-cpp-styleguide/classes/#multiple-inheritance)。

多重继承具有如下弊端：

1. 当多个基类中有同名成员函数时，到底该使用哪一个便是一个迷惑人的事。
2. 多重继承很可能会导致菱形继承。


---
title: Effective  C++ ：构造，析构和继承
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/4/15
updated: 2022/4/15
layout: true
comments: true
---

1. 构造和析构函数中调用虚函数，由于其派生类还未被构造和已被析构，所以得到的结果不会是预期的。
2. 重载父类虚函数，需要加上`override`关键字

<!--more-->

# 构造和析构中使用虚函数

直接看下面代码，一目了然：

```cpp
#include <iostream>
#include <string>

class BasicClass {
    public:
        BasicClass() {
            std::cout << "BasicClass constructor!\n";
            // 此时子类还没有被初始化，所以这里调用的还是自己的 func()
            func();
        }
        virtual ~BasicClass() {
            std::cout << "BasicClass destructor!\n";
            // 此时子类已经被释放了，所以这里调用的还是自己的 func2()
            func2();
        }

        virtual void func(void) {
            std::cout << "BasicClass func!\n";
        }
        virtual void func2(void) {
            std::cout << "BasicClass func2!\n";
        }
};

class DerivedClass: public BasicClass {
    public:
        DerivedClass() {
            std::cout << "DerivedClass constructor!\n";
        }
        ~DerivedClass() {
            std::cout << "DerivedClass destructor!\n";
        }
        void func(void) override {
            std::cout << "DerivedClass func!\n";
        }
        void func2(void) override {
            std::cout << "DerivedClass func2!\n";
        }
};

int main(void) {
    {
        DerivedClass drived_class;
    }

    return 0;
}
```

输出：

```shell
BasicClass constructor!
BasicClass func!
DerivedClass constructor!
DerivedClass destructor!
BasicClass destructor!
BasicClass func2!
```

# 使用 `override`

## 满足多态的条件

在 cpp 中，要使多态生效，那么必须满足下面这些条件：

1. 基类中的方法必须是虚方法（`virtual`）
2. 派生类的方法必须与基类虚方法名称及参数保持一致
3. 派生类的方法的`const`限定也必须与基类虚方法保持一致
4. 派生类的方法的返回类型必须与基类虚方法的返回保持**兼容**

到了 c++11 还增加了以下一个条件：

1. 基类中的方法的引用限定必须与基类虚方法保持一致
> 引用限定就是限定方法只能在对象是左值还是右值时被使用

```cpp
class Widget {
public:
  void doWork() &;       // this version of doWork applies
                         // only when *this is an lvalue
  void doWork() &&;      // this version of doWork applies
};                       // only when *this is an rvalue

Widget makeWidget();     // factory function (returns rvalue)
Widget w;                // normal object (an lvalue)

w.doWork();              // calls Widget::doWork for lvalues
                         // (i.e., Widget::doWork &)
makeWidget().doWork();   // calls Widget::doWork for rvalues
                         // (i.e., Widget::doWork &&)
```

以上 5 个条件必须都要满足，所以在重载父类虚函数时，一定要多加审查。

## 为什么需要加 `override`?

根据上面的满足条件来看，我们平时是很容易写错的，并且编译器并不会报错。

但如果在方法声明后增加了`override`关键字，编译器可以代我们完成检查。

假设以后基类的虚函数这些元素发生了变化，编译器也可以帮我们检查。
---
title: '[What] Effective  C++ ：模板与泛型编程'
tags: 
- c++
date: 2021/9/17
categories: 
- language
- c/c++
- Effective
layout: false
---

模板与泛型编程是一个比较大的话题，这里来复习一下它们需要注意的地方。

<!--more-->
# 了解隐式接口和编译器多态
Templates 中虽然也有显示接口和运行期多态（哪一个 virtual 函数该被绑定），但更重要的是隐式接口（implicit interfaces）和编译期多态（compile-time polymorphism）（哪一个重载函数该被调用）。

- 对 classes 而言，接口是显示的（explicit），以函数签名为中心。多态则是通过 virtual 函数发生于运行期
- 对 template 参数而言，接口是隐式的（implicit），奠基于有效表达式。多态则是通过 template 具现化和函数重载解析发生于编译器。

# 了解`typename`的双重意义

首先，在 template 声明式中，`class` 和 `typename` 都是相同的：

```cpp
template<class T> class Widget;
template<typename T> class Widget;
```

而`typename`的另外一个用途是为编译器指明嵌套从属类型是一个类型：

```cpp
#include <iostream>
#include <string>
#include <vector>

template<typename C>
void Print2nd(const C& container) {
    if (container.size() >= 2) {
        typename C::const_iterator iter(container.begin());

        ++iter;
        int value = *iter;

        std::cout << value;
    }
}

int main()
{
    std::vector<int> v{1, 2};

    Print2nd(v);


    return 0;
}
```

如上代码所示，编译器首先要推导类型 C ，然后才能推导`C::const_iterator`。

所以需要前面加上`typename`关键字，编译器才会知道那是一个类型，从而编译通过。

**但是**在继承语句和成员初始化列表中反而不能加上`typename`：

```cpp
template<typename T>
// 继承语句不能加 typename
class Derived: public Base<T>::Nested {
    public:
        explicit Derived(int x):
    	// 初始化列表不能加 typename
        Base<T>::Nested(x) {
            // 这里必须加 typename
            typename Base<T>::Nested temp;
        }
};
```

# 学习处理模板化基类内的名称

```cpp
#include <iostream>
#include <string>
#include <vector>

class Print1 {
    public:
        void Hello(void) {
            std::cout << "This is print1 hello!\n";
        }
};
class Print2 {
    public:
        void Hello(void) {
            std::cout << "This is print2 hello!\n";
        }
};

template<typename T>
class PrintObj {
    public:
        void PrintHello(void) {
            T obj;

            obj.Hello();
        }
};

template<typename T>
class PrintLog: public PrintObj<T>{
    public:
        //1.
        using PrintObj<T>::PrintHello;
        void AddLog(void) {
            std::cout << "log before print\n";
            //1.
            PrintHello();

            //2.
            //this->PrintHello();

            //3.
            //PrintObj<T>::PrintHello();
            std::cout << "log after print\n";
        }
};


int main()
{
    PrintLog<Print1> obj1;
    PrintLog<Print2> obj2;

    obj1.AddLog();
    obj2.AddLog();

    return 0;
}
```

如上代码所示，`PrintLog`继承自模板基类，然后调用了模板基类中的成员函数。

但如果不加干预的话，是无法编译通过的：因为编译器会认为有可能继承的模板基类是特化版本的。

> 也就是说，编译器不能完全保证基类一定会有该方法。

所以，就需要做一些事来表明需要使用的是通用版本：

- 方法 1：使用`this`指针，表明是通用版本
- 方法 2：使用`PrintObj<T>::PrintHello();`语句，表明使用通用版本
- 方法 3：使用`using PrintObj<T>::PrintHello;`前置声明会使用通用版本

# 将与参数无关的代码抽离 templates

为了避免 templates 展开后过度膨胀，需要避免其代码中的膨胀。

- Templates 生成多个 classes 和多个函数，所以任何 template 代码都不该与某个造成膨胀的 template 参数产生相依关系
- 因非类型模板参数而造成的代码膨胀，往往可以消除，做法是以函数参数或 class 成员变量替换 template 参数
- 因类型参数而造成的代码膨胀，往往可降低，做法是让带有完全相同二进制表述的具现类型共享实现码


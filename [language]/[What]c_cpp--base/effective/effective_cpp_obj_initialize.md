---
title: Effective  C++ ：对象的初始化
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/4/12
updated: 2022/4/12
layout: true
comments: true
---

要养成好的习惯：永远在使用对象之前先将它初始化。
- 对于内置类型，在定义时就初始化
- 对于类类型，在构造函数初始值列表中按照**声明顺序**初始化
  + 类类型中的私有变量是内置类型时，也可以在声明时初始化，这样可以避免初始值列表过长。
  + 如果期望类类型中的对象以默认构造函数初始化时，那也可以不用放在初始值列表中

<!--more-->

# 初始化语法的迷惑

## 内置类型的初始化

对于内置类型的初始化，有以下 4 种形式：

```cpp
#include <iostream>

int main(void) {
    int i = 1;
    int j(20);
    //{} 和 = {} 的形式对于编译器来讲是同一种形式
    //所以可以简单把它们都称为列表初始化
    int k{78};
    int l = {90};

    std::cout << "The value of i is " << i << "\n";
    std::cout << "The value of j is " << j << "\n";
    std::cout << "The value of k is " << k << "\n";
    std::cout << "The value of l is " << l << "\n";

    double m = 1.123456;
    //不同类型转换，当存在丢失信息的风险，下面两种初始化最多只给出 warning
    int q = m;
    int w(m);

    std::cout << "The value of q is " << q << "\n";
    std::cout << "The value of w is " << w << "\n";

    //不同类型转换，当存在丢失信息的风险，列表初始化就会编译器报错或给出 warning
    int e{m};
    int r = {m};

    std::cout << "The value of e is " << e << "\n";
    std::cout << "The value of r is " << r << "\n";

    return 0;
}
```

由于`{}`和`={}`对于编译器同义，那么初始化方式就是 3 种：

- 赋值初始化
- 圆括号初始化
- 列表初始化

> 列表初始化如果出现`narrowing  conversions`，则编译器很可能报错！
> 比如 msvc 和 clang 都会报错，gcc 则会报 warning……

## 对象初始化

而对于对象初始化，这 3 种初始化方式差异就很大了，比如说：

```cpp
Widget w1; 	//使用默认构造函数，初始化对象
Widget w2 = w1;//使用拷贝构造函数，初始化对象
w1 = w2;//使用赋值重载方法（拷贝赋值）来赋值 w1
std::vector<int> v{1, 2, 3};//使用列表初始化，为容器内的对象设定初始值
```

同样是对内置类型的初始化，在类声明中对内置类型使用圆括号初始化就会出错：

```cpp
#include <iostream>

class Widget {
public:
    Widget() {

    }
private:
    int i = 1;
    int j{2};
    //错误！
    int k(9);
};

int main(void) {
    class Widget widget;
    return 0;
}
```

还没完，在使用`std::atomic<T>`初始化对象时，赋值初始化也会出错：

```cpp
#include <atomic>

int main(void) {
    std::atomic<int> i{0};
    std::atomic<int> j(1);
    //错误！
    std::atomic<int> k = 2;
    return 0;
}
```

那么这就可以看出来：使用**列表初始化**来初始化内置类型是一个在各种环境下都正确的做法。

列表初始化对于对象来讲，也是相对安全的做法：

```cpp
#include <atomic>
#include <iostream>

class Widget {
public:
    Widget(int i = 0) {
        std::cout << "default construct -> " << i << "\n";
    }
};

int main(void) {
    //调用默认构造函数
    Widget widget1(1);
    //这里实际上是声明了一个函数，参数为空，返回类型为 Widget ……
    Widget widget2();
    //而使用列表初始化，就可以调用默认构造函数
    Widget widget3{};
    Widget widget4{4};

    return 0;
}
```

## 列表初始化的缺陷

从上面的例子来看，列表初始化似乎是在初始化变量和对象时的完美解决方案，但实际上它也有一些限制……

### 使用 auto 推导

使用`auto`推导以列表初始化形式初始化的变量时，得到的是`std::initializer_list<T>`类型。

### 对构造函数的调用

#### 没有初始化列表构造函数时

使用列表初始化方式初始化的对象，总是倾向于调用列表初始化形式的构造函数，**而不会理会参数的匹配度！**

```cpp
#include <atomic>
#include <iostream>

class Widget {
public:
    Widget(int i, int j) {
        std::cout << "first construct i: " << i  << " j: "<< j << "\n";
    }
    Widget(int i, double j) {
        std::cout << "second construct i: " << i  << " j: "<< j << "\n";
    }
};

int main(void) {
    /**
     * @brief 在没有列表初始化构造函数的情况下，使用列表初始化能够匹配到正确的构造函数
     */
    Widget widget1(1, 2);
    Widget widget3{3, 4};

    Widget widget2(1, 2.0);
    Widget widget4{3, 4.0};

    return 0;
}
```

#### 有列表初始化函数时

当类有列表初始化构造函数后，情况就不同了：

```cpp
#include <atomic>
#include <iostream>
#include <initializer_list>

class Widget {
public:
    Widget(int i, int j) {
        std::cout << "first construct i: " << i  << " j: "<< j << "\n";
    }
    Widget(int i, double j) {
        std::cout << "second construct i: " << i  << " j: "<< j << "\n";
    }
    Widget(std::initializer_list<double> val) {
        std::cout << "third construct :\n";
        for(auto v : val){
            std::cout << v << ",";
        }
        std::cout << "\n";
    }
};

int main(void) {
    /**
     * @brief 在有列表初始化构造函数的情况下，使用列表初始化会强制调用列表初始化形式的构造函数
     */
    //调用第1个构造函数
    Widget widget1(1, 2);
    //调用第3个构造函数
    Widget widget3{3, 4};

    //调用第2个构造函数
    Widget widget2(1, 2.0);
    //调用第3个构造函数
    Widget widget4{3, 4.0};

    return 0;
}
```

`int`类型被转换成了`double`类型。

>  但如果`std::initializer_list<T>`中的元素为`int`时，编译器就会报错，因为损失了信息在列表初始化情况下编译器不予通过。

即使对于拷贝构造和移动语义也是如此：

> 使用 g++ 编译验证，但使用 msvc ，widget7{widget1} 会依然调用拷贝构造函数

```cpp
#include <atomic>
#include <iostream>
#include <initializer_list>
#include <algorithm>
#include <cstring>

class Widget {
public:
    Widget(int i, int j): i_(i), j_(j) {
        std::cout << "first construct i: " << i  << " j: "<< j << "\n";
    }
    Widget(int i, double j): i_(i), j_(j) {
        std::cout << "second construct i: " << i  << " j: "<< j << "\n";
    }
    Widget(std::initializer_list<double> val) {
        std::cout << "third construct :";
        for(auto v : val){
            std::cout << " " << v;
        }
        std::cout << "\n";
    }
    Widget(const Widget& w) {
        std::cout << "copy construct\n";

        std::memcpy(this, &w, sizeof(w));
    }
    Widget(const Widget&& w) {
        std::cout << "move construct\n";

        std::memcpy(this, &w, sizeof(w));
    }
    void print(void) const {
        std::cout << "i " << i_ << " j " << j_ << "\n";
    }
    operator float() const {
        std::cout << "operator ()\n";
        return (i_ + j_);
    }
private:
    int i_;
    int j_;
};

int main(void) {
    /**
     * @brief 在有列表初始化构造函数的情况下，使用列表初始化会强制调用列表初始化形式的构造函数
     */
    std::cout << "create widget1:";
    Widget widget1(1, 2);
    std::cout << "create widget3:";
    Widget widget3{3, 4};

    std::cout << "create widget2:";
    Widget widget2(1, 2.0);
    std::cout << "create widget4:";
    Widget widget4{3, 4.0};

    std::cout << "create widget5:";
    Widget widget5(widget1);
    std::cout << "create widget6:";
    Widget widget6(std::move(widget2));

    std::cout << "create widget7:";
    //在有转换函数的情况下，先使用转换函数，然后调用初始化列表构造函数
    Widget widget7{widget1};
    widget7.print();
    //同上
    std::cout << "create widget8:";
    Widget widget8{std::move(widget2)};


    return 0;
}
```

当类中有转换函数时，使用列表初始化传入另一个对象，就会调用列表初始化构造函数。

> 但如果类中没有转换函数，还是会调用拷贝构造函数

#### 初始值无法转换时

**当初始值不能转换为初始化列表的元素值时，就会调用其他最为匹配的构造函数：**

```cpp
#include <atomic>
#include <iostream>
#include <initializer_list>
#include <algorithm>
#include <cstring>
#include <string>

class Widget {
public:
    Widget(int i, int j): i_(i), j_(j) {
        std::cout << "first construct i: " << i  << " j: "<< j << "\n";
    }
    Widget(int i, double j): i_(i), j_(j) {
        std::cout << "second construct i: " << i  << " j: "<< j << "\n";
    }
    Widget(std::initializer_list<std::string> val) {
        std::cout << "third construct :";
        for(auto v : val){
            std::cout << " " << v;
        }
        std::cout << "\n";
    }
    Widget(const Widget& w) {
        std::cout << "copy construct\n";

        std::memcpy(this, &w, sizeof(w));
    }
    void print(void) const {
        std::cout << "i " << i_ << " j " << j_ << "\n";
    }
    operator float() const {
        std::cout << "operator ()\n";
        return (i_ + j_);
    }
private:
    int i_;
    int j_;
};

int main(void) {
    /**
     * @brief 虽然有初始值列表构造函数，但类型无法转换，那么也会调用最匹配的构造函数
     */
    std::cout << "create widget1:";
    Widget widget1(1, 2);
    std::cout << "create widget3:";
    Widget widget3{3, 4};

    std::cout << "create widget2:";
    Widget widget2(1, 2.0);
    std::cout << "create widget4:";
    Widget widget4{3, 4.0};


    return 0;
}
```

以上代码的输出为：

```shell
create widget1:first construct i: 1 j: 2
create widget3:first construct i: 3 j: 4
create widget2:second construct i: 1 j: 2
create widget4:second construct i: 3 j: 4
```

#### 当初始值列表为空时

当初始值列表为空时，就会调用默认构造函数。如果想要显示的调用初始值列表构造函数，那就需要使用圆括号或花括号把这个初始值列表再包含一次。

```cpp
#include <atomic>
#include <iostream>
#include <initializer_list>
#include <algorithm>
#include <cstring>
#include <string>

class Widget {
public:
    Widget(int i = 0, int j = 0): i_(i), j_(j) {
        std::cout << "first construct i: " << i  << " j: "<< j << "\n";
    }
    Widget(int i, double j): i_(i), j_(j) {
        std::cout << "second construct i: " << i  << " j: "<< j << "\n";
    }
    Widget(std::initializer_list<std::string> val) {
        std::cout << "third construct :";
        for(auto v : val){
            std::cout << " " << v;
        }
        std::cout << "\n";
    }
    Widget(const Widget& w) {
        std::cout << "copy construct\n";

        std::memcpy(this, &w, sizeof(w));
    }
private:
    int i_;
    int j_;
};

int main(void) {
    std::cout << "create widget1:";
    Widget widget1; //默认构造函数
    std::cout << "create widget2:";
    Widget widget2{};//同上

    std::cout << "create widget3:";
    Widget widget3({});//显示调用初始值列表构造函数
    std::cout << "create widget4:";
    Widget widget4{{}};//同上


    return 0;
}
```

### 对 vector 初始化的理解

基于上面的理解，就能够明白`vector`初始化使用圆括号和使用初始值列表的意义了：

```cpp
#include <vector>
#include <iostream>

int main(void) {
    std::vector<int> v1(5, 10);//创建具有 5 个元素，且每个元素值为 10 的 vector
    std::vector<int> v2{5, 100};//创建具有两个元素，且值依次为 5， 100 的 vector

    std::cout << "The size of v1 is " << v1.size() << "\n";

    for(auto v: v1) {
        std::cout << " " << v;
    }
    std::cout << "\n";

    std::cout << "The size of v2 is " << v2.size() << "\n";

    for(auto v: v2) {
        std::cout << " " << v;
    }
    std::cout << "\n";

    return 0;
}
```

# `static` 对象的初始化

除了上面所说的规则外，还有一个是`static`对象需要被注意，这包括：
- 全局对象：non-local static
- 定义域`namespace`作用域内的对象：non-local static
- 在类内的对象：non-local static
- 在函数内的对象：local static
- 在文件作用域的对象：non-local static

如果`non-local static`的对象，处于不同的文件中，那么他们的[初始化顺序是未定的！](https://en.cppreference.com/w/cpp/language/initialization)。

相当于编译器生成了目标文件，在最后链接的过程中，并不能保证对象按照严格的顺序进行初始化。

所以就很可能会出现让人抓瞎的问题：

>  如果一个`non-local static`对象在使用另外一个`non-local static`对象，如果另外一个`non-local static`对象还未被初始化，那最终的行为就是未定义的。

解决上面这个问题最简单的办法就是使用单例模式：

> 如果希望存在这样一个`non-local static`对象，那么我们就将它做成单例模式，也就是只有单个对象的存在。
>
> 这样其他对象在使用它时，会调用`GetInstance()`这种方法来获取对象，而在函数中会必然保证该对象会被初始化。这样也就保证了初始化顺序。
>
> 如果该对象一直未被使用，那么也不会初始化该对象，相当于还节约了内存。


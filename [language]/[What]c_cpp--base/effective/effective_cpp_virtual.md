---
title: Effective C++ ：为多态基类声明 virtual 析构函数
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/4/14
updated: 2022/4/14
layout: true
comments: true
---

为保证多态析构的正确性，需要为**基类**的虚构函数加上`virtual`：

```cpp
#include <iostream>
#include <string>

class BasicClass {
    public:
        virtual ~BasicClass() {
            std::cout << "BasicClass destructor!\n";
        }
};

class DerivedClass: public BasicClass {
    public:
        ~DerivedClass() {
            std::cout << "DerivedClass destructor!\n";
        }
};

int main(void){

    class BasicClass* p_class = new DerivedClass();

	// 如果  BasicClass 的析构函数没有 virtual 关键字
	// 那么执行 delete 后只会执行 BasicClass 的析构函数
	// 也就是说，只释放了基类内存，而派生类的内存没有被释放掉
    delete p_class;

    return 0;
}
```

<!--more-->

但这并不意味着每一个类的析构函数都需要为其加上`virtual`修饰，因为一旦加上，这个类所携带的信息就还得需要虚指针，虚指针指向对应的虚表。

```cpp
#include <iostream>
#include <string>

class BasicClass {
    public:
        virtual ~BasicClass() {
            std::cout << "BasicClass destructor!\n";
        }
    private:
        int val = 0;
};

class BasicClass2 {
    public:
        ~BasicClass2() {
            std::cout << "BasicClass2 destructor!\n";
        }
    private:
        int val = 0;
};

int main(void) {

    BasicClass basic_class;
    BasicClass2 basic_class2;

    std::cout << "sizeof BasicClass is " << sizeof(basic_class) << "\n";
    std::cout << "sizeof BasicClass2 is " << sizeof(basic_class2) << "\n";

    return 0;
}
```

输出：

```shell
sizeof BasicClass is 16
sizeof BasicClass2 is 4
BasicClass2 destructor!
BasicClass destructor!
```

所以：

- 如果一个类不希望作为基类，那它需要使用`final`关键字来限定避免被继承。自然它也就不需要为析构函数加上`virtual`修饰了。
- 如果一个类作为基类，需要应用多态的特性，就需要加上`virtual`修饰了。

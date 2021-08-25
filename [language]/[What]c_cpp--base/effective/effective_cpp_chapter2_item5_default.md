---
title: '[What] Effective  C++ ：了解 C++ 的默认函数'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---
编译器默认会为一个类提供：
- 默认构造函数：如果类编写了构造函数，则编译器就不会自动提供默认构造函数了
- 拷贝构造函数：单纯地将每一个数据成员进行拷贝
  + 如果数据成员中的对象具有它自己的拷贝构造函数，则也会调用它
- 拷贝赋值函数：单纯地将每一个数据成员进行拷贝
  + 如果数据成员中的对象具有它自己的拷贝赋值函数，则也会调用它
- 析构函数

> 对于 modern cpp 其实还有[移动构造和移动赋值](http://kcmetercec.top/2021/01/20/chapter3_item17_special/)



<!--more-->
但有些时候，并不是都可以使用默认拷贝构造和拷贝赋值函数。

比如类中有指针的情况下，不能简单的进行成员变量拷贝就行了，还要拷贝指针所指向的内存。

在比如下面这种情况：
```cpp
#include <iostream>
#include <string>

class Hello{
    public:
        Hello(std::string& name): name_(name){

        };
    private:
        std::string& name_;
};

int main(void){
    std::string name1("hello1");
    std::string name2("hello2");

    Hello hello1(name1);
    Hello hello2(name2);

    // 这里想使用拷贝赋值函数，但是如果是单纯的位拷贝，
    // 相当于要将对象 hello1 中的引用改变，这就和引用的概念相冲突了
    // 编译器就不会为这个类生成默认的拷贝赋值函数
    hello1 = hello2;

    return 0;
}
```

编译时错误如下：

```shell
hello.cc: In function ‘int main()’:
hello.cc:20:14: error: use of deleted function ‘Hello& Hello::operator=(const Hello&)’
     hello1 = hello2;
              ^~~~~~
hello.cc:4:7: note: ‘Hello& Hello::operator=(const Hello&)’ is implicitly deleted because the default definition would be ill-formed:
 class Hello{
       ^~~~~
hello.cc:4:7: error: non-static reference member ‘std::__cxx11::string& Hello::name_’, can’t use default assignment operator
```

如果不希望编译器生成默认函数，可以使用[delete](http://kcmetercec.top/2021/01/20/chapter3_item11_delete_func/)。


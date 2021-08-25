---
title: '[What] Effective  C++ ：不要在构造和析构中使用虚函数'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---

构造和析构函数中调用虚函数，而其派生类还未被构造和已被析构，所以得到的结果不会是预期的。

<!--more-->
```cpp
#include <iostream>
#include <string>

class BasicClass {
    public:
        BasicClass(){
            std::cout << "BasicClass constructor!\n";
            // 此时子类还没有被初始化，所以这里调用的还是自己的 func()
            func();
        }
        virtual ~BasicClass(){
            std::cout << "BasicClass destructor!\n";
            // 此时子类已经被释放了，所以这里调用的还是自己的 func2()
            func2();
        }

        virtual void func(void){
            std::cout << "BasicClass func!\n";
        }
        virtual void func2(void){
            std::cout << "BasicClass func2!\n";
        }
};

class DerivedClass: public BasicClass{
    public:
        DerivedClass(){
            std::cout << "DerivedClass constructor!\n";
        }
        ~DerivedClass(){
            std::cout << "DerivedClass destructor!\n";
        }
        void func(void) override{
            std::cout << "DerivedClass func!\n";
        }
        void func2(void) override{
            std::cout << "DerivedClass func2!\n";
        }
};

int main(void){

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


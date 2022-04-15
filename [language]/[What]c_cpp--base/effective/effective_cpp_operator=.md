---
title: Effective  C++ ：赋值重载的注意点
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

复制重载涉及到拷贝赋值和移动赋值两种情况，有些点需要注意一下。

<!--more-->

# 让 `operator=`类重载返回 `*this` 引用

为了满足连续赋值的需求，赋值重载方法需要返回对象。

而为了能够提高效率，返回它的引用是个好习惯。

```cpp
class Widget {
	public:
    // ...
    // +=, -=, *= 这类函数重载都要满足连续赋值要求
    Widget& operator+=(const Widget& rhs) {
        // ...
        return *this;
    }
    Widget& operator=(const Widget& rhs) {
        // ...
        return *this;
    }
    // 即使参数类型不同，也需要满足连续赋值
    Widget& operator=(int rhs) {
        // ...
        return *this;
    }
    // ...
};
```

# 在 `operator=`中处理自我赋值

在实现拷贝赋值的过程中，需要处理自我赋值（自己给自己赋值）这种特殊情况。

> 当存在别名这种情况下，自我赋值还是会比较容易发生的。

比如，当向一个含有指针的类进行赋值：

```cpp
#include <iostream>
#include <string>
#include <cstring>

class MyString {
    public:
        // ...
        MyString& operator=(const MyString& str) {
            if(this == &str){
                return *this;
            }
			// 如果没有上面判断，那么当自我赋值时，便会删除自己指向的内存
            // 接下来的操作结果便是未定义的
            delete[] str_;

            str_ = new char[str.len_];
            std::memcpy(str_, str.str_, str.len_);
            len_ = str.len_;

            return *this;
        }
    private:
        int len_ = 0;
        char *str_ = nullptr;
};
```

但是上面的处理方式仍然有不足之处：

- 如果`new`操作无法申请需求的内存而抛出异常，那么这个类的`str_`所指向的内存就会被保持被删除的状态，接下来的其他操作将会出现奇怪的行为。

使用下面的方式便可以处理异常：

```cpp
#include <iostream>
#include <string>
#include <cstring>

class MyString {
    public:
        // ...
    	MyString(const char* str) {
            int str_len = std::strlen(str);
            if(str_len == 0) {
                len_ = 1;
                str_ = new char[len_];
                str_[0] = '\0';
            }else {
                len_ = str_len + 1;
                str_ = new char[len_];
                std::memcpy(str_, str, len_);
            }
        }
    	// ...
        MyString& operator=(const MyString& str) {
            // 先使用一个副本指向当前指针指向的内存
            char* str_tmp = str_;

            // 这里使用构造函数
            // 如果此处 new 抛出异常，则不会对当前对象有任何影响
            str_ = new MyString(str.str_);
            // 删除副本的内存
            delete[] str_tmp;

            len_ = str.len_;

            return *this;
        }
    private:
        int len_ = 0;
        char *str_ = nullptr;
};
```

如上代码所示，即避免了自我赋值的问题，也避免了抛出异常的问题。
> 对于移动赋值，也需要考虑自我赋值的问题，但一般不会遇到抛出异常问题。因为移动赋值通常要声明为 noexcept 形式，已让 vector 这种容器使用。

# 注意要复制对象的每个成分

- 拷贝函数应该确保复制对象内的所有成员变量，以及**所有父类的成分**
- 通常拷贝构造和拷贝赋值函数有一部分重复代码，这个时候增加一个私有的函数是个好办法

对于第一点的示例如下：

```cpp
class Customer {
    public:
    // ...
    Customer(const Customer& rhs): name(rhs.name) {
        
    }
    Customer& operator=(const Customer& rhs) {
        name = rhs.name;
        
        return *this;
    }
    private:
    // ...
    std::string name;
};

class PriorityCustomer: public Customer {
    public:
    // ...
    PriorityCustomer(const PriorityCustomer& rhs)
    : Customer(rhs), // 调用基类的拷贝构造函数
    priority(rhs.priority) {
        
    }
    
    PriorityCustomer& PriorityCustomer(const PriorityCustomer& rhs) {
        Customer::operator=(rhs); //调用基类的拷贝赋值函数
        priority = rhs.priority;
        
        return *this;
    }
    private:
    int priority;
};
```
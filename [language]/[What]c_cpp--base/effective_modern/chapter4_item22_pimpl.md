---
title: '[What] Effective Modern C++ ：正确的使用 Pimpl'
tags: 
- c++
date:  2021/1/26
categories: 
- language
- c/c++
- Effective
layout: true
---
Pimpl 简单来讲是指在类的头文件，以指针的形式包含其它类（委托），然后在实现文件中包含类成员的头文件和内存的申请释放。
这样做的目的是减少编译时间，避免类成员发生改变后，该类头文件也受影响，尽量减少受影响的范围。
<!--more-->

# 最简单粗暴的方式

直接在头文件中包含成员头文件，那么当成员的声明被修改后，当前头文件也需要重新展开：

```cpp
class Widget {                     // in header "widget.h"
public:
  Widget();
  …
private:
  std::string name;
  std::vector<double> data;
  Gadget g1, g2, g3;               // Gadget is some user-
};                                 // defined type
```

上面这段代码，其实`std::string`和`std::vector`都不会被改变，可以这样使用。

但是由于`Gadget`类是用户自定义的，那么被修改的可能性就很大了。

# 使用指针包含成员变量

以委托的方式包含成员，可以避免头文件的编译依赖问题：

```cpp
class Widget {                 // still in header "widget.h"
public:
  Widget();
  ~Widget();                   // dtor is needed—see below
  …
private:
  struct Impl;                 // declare implementation struct
  Impl *pImpl;                 // and pointer to it
};

#include "widget.h"            // in impl. file "widget.cpp"
#include "gadget.h"
#include <string>
#include <vector>
struct Widget::Impl {          // definition of Widget::Impl
  std::string name;            // with data members formerly
  std::vector<double> data;    // in Widget
  Gadget g1, g2, g3;
};
Widget::Widget()               // allocate data members for
: pImpl(new Impl)              // this Widget object
{}
Widget::~Widget()              // destroy data members for
{ delete pImpl; }              // this object
```

# 使用`unique_ptr`

前面使用原始指针的方式一点也不优雅，所以使用智能指针才是明智的选择：

```cpp
class Widget {                      // in "widget.h"
public:
  Widget();
  …
private:
  struct Impl; 
  std::unique_ptr<Impl> pImpl;      // use smart pointer
};                                  // instead of raw pointer

#include "widget.h"                 // in "widget.cpp"
#include "gadget.h"
#include <string>
#include <vector>
struct Widget::Impl {               // as before
  std::string name;
  std::vector<double> data;
  Gadget g1, g2, g3;
};
Widget::Widget()                    // per Item 21, create
: pImpl(std::make_unique<Impl>())   // std::unique_ptr
{} 
```

## 编译期的问题

但若仅仅是上面这样，编译时便会遇到问题，编译器会报错`delete`一个非完整的类型。

这是因为前面的类并没有显示定义析构函数，而编译器会生成默认的**内联析构函数**，并且在析构函数中做类型检查。但是类型`Impl`在头文件中并不完整，所以就会导致编译错误。

正确的做法是显示的定义一个空的析构函数，该函数在 cpp 文件中的位置要位于`Widget::Impl`定义之后即可。

同样的，如果使用了移动构造函数，那也会遭遇同样的错误，所以也需要显示的定义。

## 拷贝构造与拷贝赋值函数

由于头文件中包含委托，默认的拷贝构造和拷贝赋值函数并不能满足要求，这就需要用户显示定义拷贝构造函数来完成正确的内存拷贝。

综上所述，代码应该如下：

```cpp
class Widget {                            //"widget.h"
public:
  Widget();
  ~Widget();
    
  Widget(Widget&& rhs);                   // declarations
  Widget& operator=(Widget&& rhs);        // only
    
  Widget(const Widget& rhs);              // declarations
  Widget& operator=(const Widget& rhs);   // only
    
private:                                  
  struct Impl;
  std::unique_ptr<Impl> pImpl;
};


#include "gadget.h"
#include <string>
#include <vector>
…                                    	// in "widget.cpp"
struct Widget::Impl {     
  std::string name;                  	// Widget::Impl
  std::vector<double> data;
  Gadget g1, g2, g3;
};
Widget::Widget()                     
: pImpl(std::make_unique<Impl>())
{}
Widget::~Widget() = default;

Widget::Widget(Widget&& rhs) = default;              // definitions
Widget& Widget::operator=(Widget&& rhs) = default;   

Widget::Widget(const Widget& rhs)              // copy ctor
: pImpl(std::make_unique<Impl>(*rhs.pImpl))
{}
Widget& Widget::operator=(const Widget& rhs)   // copy operator=
{
  *pImpl = *rhs.pImpl;
  return *this;
}
```

# 使用`shared_ptr`

如果将`unique_ptr`替换为`shared_ptr`便没有上述这些问题，也就是说代码可以非常简洁：

```cpp
class Widget {                      // in "widget.h"
public:
  Widget();
  …
private:
  struct Impl; 
  std::shared_ptr<Impl> pImpl;      // use smart pointer
};                                  // instead of raw pointer

#include "widget.h"                 // in "widget.cpp"
#include "gadget.h"
#include <string>
#include <vector>
struct Widget::Impl {               // as before
  std::string name;
  std::vector<double> data;
  Gadget g1, g2, g3;
};
Widget::Widget()                    // per Item 21, create
: pImpl(std::make_shared<Impl>())   // std::shared_ptr
{} 
```

这是由于二者所使用的删除器是不同的：

- `unique_ptr`使用的指向具体类型的删除器，好处是生成的数据结构小并且运行效率高。但在编译器生成特殊函数时，就需要知道完整的类型定义。
- `shared_ptr`却没有使用指向具体类型的删除器，虽然生成的数据结构大且运行效率相对低。但在编译器生成特殊函数时，不需要知道完整的类型定义，也就可以使用编译器的默认函数。


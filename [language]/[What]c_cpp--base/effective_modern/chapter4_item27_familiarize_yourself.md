---
title: '[What] Effective Modern C++ ：以自己熟悉的方式代替重载通用引用的方式'
tags: 
- c++
date:  2021/1/29
categories: 
- language
- c/c++
- Effective
layout: true
---
前面提到过，重载通用引用函数，得到的结果往往不是预期的，那么就应该以其它的方式来替代这种迷惑的方式。
<!--more-->
# 以其它的名字命名重载函数
既然对通用引用函数的重载会导致非预期的调用，那么就将那些重载函数以其它名字命名，就绕过了这个坑。
> 对于常年写 c 的人来说，这个方法是最自然而然地。

# 函数参数使用`const T&`

当重载函数不会改变实参内容时，可以使用`const T&`来做参数限定。

# 参数以值传递，并且辅以`std::move`

```cpp
class Person {
public:
  explicit Person(std::string n) // replaces T&& ctor
        : name(std::move(n)) {}        
  
  explicit Person(int idx)       
  : name(nameFromIdx(idx)) {}
private:
  std::string name;
};
```

这样既不会造成重载调用的非预期，还可以使用移动语义提高效率。

# 使用标记分发

简单的说就是在通用引用函数中使用标记分发，使得编译器在编译时就可以确定调用匹配：

```cpp
//当 std::false_type 满足后，此函数才会被调用
template<typename T>                             // non-integral
void logAndAddImpl(T&& name, std::false_type)    // argument:
{                                                // add it to
  auto now = std::chrono::system_clock::now();   // global data
  log(now, "logAndAdd");                         // structure
  names.emplace(std::forward<T>(name));
}
//当 std::true_type 满足后，此函数才会被调用
void logAndAddImpl(int idx, std::true_type)   // integral
{                                             // argument: look
  logAndAdd(nameFromIdx(idx));                // up name and
}                                             // call logAndAdd
                                              // with it

//在编译期使用 std::is_intergral 来判定应该调用哪个函数
//当传入的是 int 型时，调用 idx 参数的函数
//当传入的不是 int 型时，才调用函数模板
template<typename T>
void logAndAdd(T&& name)
{
  logAndAddImpl(
    std::forward<T>(name),
    std::is_integral<typename std::remove_reference<T>::type>()
  );
}
```

# 对通用引用进行限制

> 这部分还没有理解清楚，下次再来回看。
---
title: Effective C++ ：以自己熟悉的方式代替重载通用引用的方式
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/5/9
updated: 2022/5/11
layout: true
comments: true
---

前面提到过，重载通用引用函数，得到的结果往往不是预期的，那么就应该以其它的方式来替代这种迷惑的方式。

<!--more-->

# 以其它的名字命名重载函数

既然对通用引用函数的重载会导致非预期的调用，那么就将那些重载函数以其它名字命名，就绕过了这个坑。
> 对于常年写 c 的人来说，这个方法是最自然而然地。

# 函数参数使用`const T&`

当重载函数不会改变实参内容时，可以使用`const T&`来做参数限定，以替代通用引用。
> 这种方式在遇到右值时，也会以拷贝的方式进行创建新对象，虽然效率不高。但是很多时候可以让代码更易于理解。

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
    // 当实参是左值时，T 会被推导为左值引用，所以这里需要使用 std::remove_reference
    // 来去除引用
    std::is_integral<typename std::remove_reference<T>::type>()
  );
}
```

# 对通用引用进行限制

通过`std::enable_if`这种黑魔法，可以做到直接在通用引用函数上做限制，比如下面就限定，当实参类型不是`Person`时，才使用通用引用的构造函数。否则就使用拷贝构造、拷贝赋值这类构造函数。

```cpp
class Person {
public:
  template<
    typename T,
    typename = typename std::enable_if<
                 !std::is_same<Person,
                               typename std::decay<T>::type
                              >::value
               >::type
  >
  explicit Person(T&& n);
  //…
};
```

- `std::decay`用于将推导出的 T 中的引用、`const`、`volatile`限定给去除。以表示带引用、`const`、`volatile`的`Person`对象都是一样的。
  > `typename std::decay<T>::type` 之后得到的就是去除约束后的`T`。
- `std::is_same`是用于比较，传入的类型是否与`Person`一致
- `std::enable_if`则是当其条件为真时，才会使能该函数

以上的所有步骤都是在编译期完成的，这就是模板元编程的魅力所在。

对于有继承的情况下，情况还要复杂一点：
```cpp
class SpecialPerson: public Person {
public:
  SpecialPerson(const SpecialPerson& rhs)  // copy ctor; calls
  : Person(rhs)                            // base class
  {  }                                    // forwarding ctor!
  SpecialPerson(SpecialPerson&& rhs)       // move ctor; calls
  : Person(std::move(rhs))                 // base class
  {  }                                    // forwarding ctor!
  //…
};
```

上面这种情况下，基类`Person`被传入的是子类，所以原来的那种写法也会导致通用引用版本的构造函数被调用。

这个时候，需要使用`std::is_base_of`来替换`std::is_same`：
```cpp
class Person {
public:
  template<
    typename T,
    typename = typename std::enable_if<
                 !std::is_base_of<Person,
                                  typename std::decay<T>::type
                                 >::value
               >::type
  >
  explicit Person(T&& n);
  //…
};
```

使用`std::is_base_of`之后，无论`T`是基类还是子类，都得到结果为`true`，这样就可以避免上面的问题了。
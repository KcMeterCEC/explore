---
title: '[What] Effective Modern C++ ：lambda 与完美转发'
tags: 
- c++
date:  2021/10/6
categories: 
- language
- c/c++
- Effective
layout: true
---

c++14 中，lambda 的参数可以由`auto`推导，这就如同模板一样：
```cpp
auto f = [](auto x){ return func(normalize(x)); };

// 等同于
class SomeCompilerGeneratedClassName {
public:
  template<typename T>                   
  auto operator()(T x) const             
  { return func(normalize(x)); }
  …                                      
};                                       
```

<!--more-->

但需要注意的是，如果 lambda 中调用了其他对象，且具有左值及右值对应的版本那么就需要使用完美转发：

```cpp
auto f = [](auto&& x)
         { return func(normalize(std::forward<???>(x))); };
```

但问题是，`std::forward`中并无法确定参数类型。

这个时候就可以使用`decltype`来推导类型：

```cpp
auto f = [](auto&& x)
         { return func(normalize(std::forward<decltype(x)>(x))); };
```

除此之外，c++14 的 lambda 还支持变参数：

```cpp
auto f =
  [](auto&&... params)
  {
    return
    func(normalize(std::forward<decltype(params)>(params)...));
  };
```


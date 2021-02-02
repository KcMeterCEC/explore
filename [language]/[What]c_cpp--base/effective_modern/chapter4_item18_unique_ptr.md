---
title: '[What] Effective Modern C++ ：当指针独占资源时，应该使用 unique_ptr'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---
传统指针具有以下缺陷：
1. 单从一个指针的声明，无法判定它是指向一个对象还是指向一个包含该对象的数组
2. 单从一个指针的声明，无法判定当不使用该指针时，是否需要释放它所指向对象所占用的资源
3. 当需要释放指针所指向对象的资源时，并不能明确的知道是该使用`delete`，还是使用其它专有的释放函数
4. 当需要使用`delete`释放资源时，到底是使用`delete`还是`delete[]`，这需要小心使用
5. 当确定了释放机制时，也有可能写代码时一不小心，就造成了 double free
6. 当释放一个资源时，有可能还有其它指针指向该资源，从而导致很多很难查的 BUG

使用智能指针变能够最大化的避免以上问题。
<!--more-->

# `unique_ptr` 的特点

1. `unique_ptr` 和原始指针的大小一样大，并且执行效率也高，可以满足一些对内存和运行性能有要求的场合。
2. `unique_ptr`属于独占所指向的资源，因此不能将其赋值给另外的`unique_ptr`，而只能使用移动语义 

# `unique_ptr`的使用场合

## 在工厂函数中使用

一般工厂函数都会返回一个`unique_ptr`，使用者可以没有心理负担的正常使用。

当该`unique_ptr`退出代码块后，便会自动调用析构函数来释放其所指向的资源。而不用担心中途的异常发生而非正常的跳出该代码块。

当某些资源不能使用正常的`delete`释放时，用户可以定义自己的`delete function`：

```cpp
auto delInvmt = [](Investment* pInvestment)       // custom
                {                                 // deleter
                  makeLogEntry(pInvestment);      // (a lambda
                  delete pInvestment;             // expression)
                };
template<typename... Ts>                          // revised
std::unique_ptr<Investment, decltype(delInvmt)>   // return type
makeInvestment(Ts&&... params)
{
  std::unique_ptr<Investment, decltype(delInvmt)> // ptr to be
    pInv(nullptr, delInvmt);                      // returned
  if ( /* a Stock object should be created */ )
  {
    pInv.reset(new Stock(std::forward<Ts>(params)...));
  }
  else if ( /* a Bond object should be created */ )
  {
    pInv.reset(new Bond(std::forward<Ts>(params)...));
  }
  else if ( /* a RealEstate object should be created */ )
  {
    pInv.reset(new RealEstate(std::forward<Ts>(params)...));
  }
  return pInv;
}
```

在 c++14 中，则可以使用更加智能的推导方式：

```cpp
template<typename... Ts>
auto makeInvestment(Ts&&... params)              // C++14
{
  auto delInvmt = [](Investment* pInvestment)    // this is now
                  {                              // inside
                    makeLogEntry(pInvestment);   // make-
                    delete pInvestment;          // Investment
                  };
  std::unique_ptr<Investment, decltype(delInvmt)>   // as
    pInv(nullptr, delInvmt);                        // before
  if ( … )                                          // as before
  {
    pInv.reset(new Stock(std::forward<Ts>(params)...));
  }
  else if ( … )                                     // as before
  {
    pInv.reset(new Bond(std::forward<Ts>(params)...));
  }
  else if ( … )                                     // as before
  {
    pInv.reset(new RealEstate(std::forward<Ts>(params)...));
  }
  return pInv;                                      // as before
}
```

使用`lambda`来定义删除函数的好处是：使用该种方式不会使得`unique_ptr`的体积增加，而使用普通函数的定义方式则会使得`unique_ptr`的体积增加。



工厂函数之所以返回的是`unique_ptr`，是因为这种返回方式可以不用关心调用者使用的是`shared_ptr`还是`unique_ptr`，这样更能适用于更加广泛的场合。

## 对数组使用

对数组使用的方式是`std::unique_ptr<T[]>`，一般使用这种方式都是在使用该指针指向 c 代码所提供的从堆中申请的内存地址。


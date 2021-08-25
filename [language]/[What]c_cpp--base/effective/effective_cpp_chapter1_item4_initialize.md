---
title: '[What] Effective  C++ ：确定对象被使用前已被初始化'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---
要养成好的习惯：永远在使用对象之前先将它初始化。
- 对于内置类型，在定义时就初始化
- 对于类类型，在构造函数初始值列表中初始化
  + 类类型中的私有变量是内置类型时，也可以在声明时初始化，这样可以避免初始值列表过长。

<!--more-->
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


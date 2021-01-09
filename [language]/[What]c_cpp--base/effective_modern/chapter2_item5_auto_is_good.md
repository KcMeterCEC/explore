---
title: [What] Effective Modern C++ ：认识到使用 auto 的好处
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: false
---



理解了 `auto`的推导原则后，就需要认识到使用 `auto`所带来的便利性，才能优雅的使用它。

<!--more-->

# auto 与初始化

当我们定义一个局部变量时，如果该局部变量没有被初始化，那么它的值就是无法预知的。有的时候会由于未初始化的局部变量而导致程序 BUG。

由于 `auto`的推导是依赖于其右值的，也就是说如果没有右值，使用`auto`就会出错。基于此特性，我们可以使用 auto 来定义一个变量，以让编译器来帮助我们查看一个局部变量是否已经被初始化。

```cpp
#include <iostream>


int main(int argc, char** argv) {
	std::cout << "Hello world\n";
	
	int x;
	auto y;
	auto z = 1;
	
	
	return 0;
}
```

由于 `y`没有右值，这将导致编译失败：

> [Error] declaration of 'auto y' has no initializer

# auto 与函数指针

在不使用 `auto`的情况下，使用`std::function`方式来调用 lambda：

```cpp
#include <iostream>
#include <functional>


int main(int argc, char** argv) {
	std::cout << "Hello world\n";
	
	std::function<bool(int, int)>
	func = [](int a, int b){
		return a < b;
	};
	
	std::cout << func(1, 3) << "\n";
	
	
	return 0;
}
```

可以看到，使用`std::function`的方式，需要在模板参数里面填入指向函数的参数类型，当函数的参数类型改变后，模板里的参数也得改一次，很是麻烦。

使用`auto`来实现：

```cpp
#include <iostream>
#include <functional>


int main(int argc, char** argv) {
	std::cout << "Hello world\n";
	
	auto func = [](int a, int b){
		return a < b;
	};
	
	std::cout << func(1, 3) << "\n";
	
	
	return 0;
}
```

这样就优雅太多了。

**除此之外，`auto`实际上执行效率高于`std::function`，且不会占用额外内存。**

由于`auto`是在编译器推导的，并不会占用额外的内存，在执行时也是直接调用该函数体。

但`std::function`本身就是一个对象，对象本身就会占用更多的内存，在执行时代码也会先执行`std::function`中的代码然后最终才会跳转到函数体执行。

# auto 与可移植性

假设有变量 `v`其类似是`std::vector<int>`，那么获取其大小的类型就是`std::vector<int>::size_type`。

在 32 位系统中该值就是 32 位的`unsigned int`，在 64 位机中就是 64 位的`unsigned int`，为了保证移植性，正确的做法是：

```cpp
std::vector<int>::size_type sz = v.size();
```

但是上面这个写法，依然要确定模板元素的类型。假设以后需求的变动，使得`v`的元素类型为`float`。那么所有以上代码都需要将模板类型替换为`float`，烦人的体力劳动……

在使用`auto`后就是这样了：

```cpp
auto sz = v.size();
```

可以看到这样写的优点：

1. 不用关心模板元素的类型，代码更简洁
2. 后期需求变动，就算改变了`v`的元素类型，以上代码都不需要做任何变动

# auto 与歧义性

使用`auto`能在一些时候避免一些歧义性的坑。

比如使用范围`for`从容器中获取一个`const`引用可能会引起歧义：

```cpp
std::unorderd_map<std::string, int> m;

for(const std::pair<std::string, int>& p : m){
    
}
```

以上使用范围`for`的原意是从容器`m`中取出一个元素，并以`const`引用的方式访问里面的元素。

但是需要注意的是：**`std::unorderd_map`的`value_type`类型定义原型是`std::pair<const Key, T>`**。

也就是说，对于`m`来讲，它的元素类型是`std::pair<const std::string, int>`，那么`p`就和`m`的元素类型不匹配，这就很坑了。

这种情况下，编译器往往会拷贝`m`中元素的副本，由`p`来进行绑定，最终搞了半天，`p`操作的不过就是个副本而已！

使用`auto`就可以避免这种坑：

```cpp
for(const auto& p: m){
    
}
```


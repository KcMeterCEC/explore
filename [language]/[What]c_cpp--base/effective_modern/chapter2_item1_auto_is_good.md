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
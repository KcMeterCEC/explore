---
title: Effective C++ ：理解 auto
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/5/2
updated: 2022/5/2
layout: true
comments: true
---

理解了 `auto`的推导原则后，就需要认识到使用 `auto`所带来的便利性和缺陷，才能正确的使用它。

<!--more-->

# 认识到使用 auto 的好处'

## auto 与初始化

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

## auto 与函数指针

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

## auto 与可移植性

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

## auto 与歧义性

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
for(const auto& p: m) {
    
}
```

# auto 初始化可能会遇到的坑'

## 类型的隐式转换

假设要从一个`std::vector<bool>`类型容器中获取一个结果，可以像如下的编写方式：

```cpp
#include <iostream>
#include <vector>

std::vector<bool> GetResult(void) {
    std::vector<bool> ret = {0, 0, 1, 1, 1};

    return ret;
}

int main()
{
    bool ret = GetResult()[2];

    std::cout << "ret value is " << ret << "\n";

    return 0;
}
```

运行的结果是：

> ret value is 1

这个代码验证无误，但是为了在获取返回值时更为智能一点，我们将返回类型用`auto`进行推导：

```cpp
auto ret = GetResult()[2];
```

在 MSVC 环境下运行便会报错：

> Expression:cannot dereference value-initialized vector<bool> iterator.

接下来我们主动让编译器在编译时报错来查看该`auto`推导的类型：

```cpp
#include <iostream>
#include <vector>

template<typename T>
class TypeDisplay;

std::vector<bool> GetResult(void) {
    std::vector<bool> ret = {0, 0, 1, 1, 1};

    return ret;
}

int main() {
    auto ret = GetResult()[2];

    TypeDisplay<decltype(ret)> type;

    std::cout << "ret value is " << ret << "\n";

    return 0;
}
```

编译时报错如下：

> hello.cc:16:32: error: aggregate ‘TypeDisplay<std::_Bit_reference> type’ has incomplete type and cannot be defined

按照正常理解，`auto`应该推导出`bool`类型才是，结果却是`std::vector<bool>::reference`。

大部分情况下，`std::vector::operator[]`会返回该容器元素的引用，但是由于上面定义的容器元素类型为`bool`。

这在底层的表示为，一个`bool`占用一个`bit`，而**c++ 是禁止返回一个位的引用的**。

所以实际上`bool ret = GetResult()[2]`的操作顺序是：

1. 返回`std::vector<bool>::reference`类型
2. 取第 3 位的值，隐式转换为`bool`类型

而`auto ret = GetResult()[2]`得到的类型确是`std::vector<bool>::reference`，实际上这个步骤比想象的复杂：

1. `GetResult()`函数返回的是`std::vector<bool>`的副本，也就是一个临时对象`tmp`
2. 接下来`operator[]`由于不能返回位的引用，所以得到的是`std::vector<bool>::reference`对象
3. 这个对象实际上是指向`bool`的指针，接下来再索引到下标为 2 的地址处，也就指向了第 3 位
4. `ret`得到的就是第 3 位的地址（在上面正确的结果中，如果进行了隐式转换，是将第 3 位的值拷贝了一次，而此处并未拷贝）
5. `tmp`临时对象内存被释放，最终`std::cout`语句所获取的就是个野指针！

## 解决方案

解决办法就是明确的限定需要进行一次类型转换，使用`static_cast`：

```cpp
#include <iostream>
#include <vector>

std::vector<bool> GetResult(void) {
    std::vector<bool> ret = {0, 0, 1, 1, 1};

    return ret;
}

int main() {
    auto ret = static_cast<bool>(GetResult()[2]);

    std::cout << "ret value is " << ret << "\n";

    return 0;
}
```

其实在很多有隐式类型转换的位置，显示的使用 cast 是一个很好的习惯。
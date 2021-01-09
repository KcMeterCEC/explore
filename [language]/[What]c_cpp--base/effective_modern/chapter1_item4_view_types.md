---
title: '[What] Effective Modern C++ ：查看推导的类型'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---

在理解了基本的推导原则后，为了查看及验证推导的类型，使用**编译时获取**和**基于 boost 库获取**是最为靠谱的方案。

<!--more-->

# 在编辑器中获取

在大多数 IDE 中的编辑器，如果代码没有语法错误，那么将鼠标指向被推导的变量，就会出现该变量的提示。

**但是，在一些稍微复杂的场合，这些提示往往是不准确的。**

# 在编译过程中获取

通过故意使得编译出错，从而使编译展示该类型：

```cpp
#include <iostream>

template<typename T>
class TypeDisplay;

int main(int argc, char** argv) {
	std::cout << "Hello world\n";
	
	int x = 0;
	
	TypeDisplay<decltype(x)> type1;
	TypeDisplay<decltype((x))> type2;
	
	return 0;
}
```

编译过程中便会有如下类似错误：

> [Error] aggregate 'TypeDisplay<int> type1' has incomplete type and cannot be defined
>
> [Error] aggregate 'TypeDisplay<int&> type2' has incomplete type and cannot be defined

对于稍微复杂一点的场景也可以：

```c
#include <iostream>
#include <vector>

template<typename T>
class TypeDisplay;

template<typename T>
void f(const T& param){
	TypeDisplay<T> type1;
	TypeDisplay<decltype(param)> type2;
}


int main(int argc, char** argv) {
	std::cout << "Hello world\n";
	
	std::vector<float> createVec;
	
	createVec.push_back(2.0);
	
	const auto vw = createVec;
	
	if(!vw.empty()){
		f(&vw[0]);
	}
	
	
	return 0;
}
```

错误输出如下：

> [Error] 'TypeDisplay<const float*> type1' has incomplete type
>
> [Error] 'TypeDisplay<const float* const&> type2' has incomplete type

# 在运行过程中获取

使用 `typeid` 很多时候并不能准确的推导类型：

```c
#include <iostream>


int main(int argc, char** argv) {
	std::cout << "Hello world\n";
	
	int x = 0;
	
	std::cout << typeid(decltype(x)).name() << "\n";
	std::cout << typeid(decltype((x))).name() << "\n";
	
	
	return 0;
}
```

以上代码用 gcc 编译后的输出是：

> Hello world
>
> i
>
> i

i 代表 `int` 类型，但是第二种情况实际上应该是 `int &`。

在运行时的环境中，只有 `boost` 库提供的方法能够准确的显示被推导的类型。

```cpp
#include <boost/type_index.hpp>
template<typename T>
void f(const T& param)
{
  using std::cout;
  using boost::typeindex::type_id_with_cvr;
  // show T
  cout << "T =     "
       << type_id_with_cvr<T>().pretty_name()
       << '\n';
  // show param's type
  cout << "param = "
       << type_id_with_cvr<decltype(param)>().pretty_name()
       << '\n';
}
```


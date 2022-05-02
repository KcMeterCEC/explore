---
title: Effective C++ ：类型推导
tags: 
- cpp
categories:
- cpp
- effective
date: 2022/4/29
updated: 2022/5/2
layout: true
comments: true
---

理解 cpp 是如何进行类型推导的，这样在使用时才不会踩太多坑……

<!--more-->

# 模板类型推导

## 基础

一个普通的函数模板就像下面这样：

```cpp
#include <iostream>
#include <cstdint>

template<typename T>
T GetSum(const T* buf, int size) {
  T sum = 0;
  for (int i = 0; i < size; ++i) {
    sum += buf[i];
  }

  return sum;
}

int main(void) {
  uint16_t u16_buf[] = {0, 1, 2, 3, 4, 5};
  uint32_t u32_buf[] = {6, 7, 8, 9, 10};
  float float_buf[] = {1.123, 2.234, 3.345, 4.456};

  std::cout << "The sum of u16 buffer is " << GetSum(u16_buf, sizeof(u16_buf) / sizeof(u16_buf[0])) << std::endl;
  std::cout << "The sum of u32 buffer is " << GetSum(u32_buf, sizeof(u32_buf) / sizeof(u32_buf[0])) << std::endl;
  std::cout << "The sum of float buffer is " << GetSum(float_buf, sizeof(float_buf) / sizeof(float_buf[0])) << std::endl;

  return 0;
}
```

对应的输出为：

>  The sum of u16 buffer is 15
>  The sum of u32 buffer is 40
>  The sum of float buffer is 11.158

使用函数模板来代替函数重载，这是一种简单而优雅的做法。

从表面上来看，似乎编译器是自然而然的就可以根据实参的类型推导出类型`T`，然而实际上类型`T`和形参所使用的`T`是不同的。

 > 就拿上面的 GetSum 函数模板举例，被推导的类型实际上有：
 > 1. 模板类型 T
 > 2. 函数形参 const T*

最终，真正决定`T`的类型，是由实参和形参类型共同所决定的，具有以下 3 种情况：
1. 形参是一个指针或引用类型，但并不是通用引用
2. 形参是一个通用引用
3. 形参既不是指针也不是引用

## 形参是一个指针或引用类型，但并不是通用引用

这种情况下的推导步骤如下：
- 如果实参是一个引用（无论是左值还是右值引用）或指针，那么就忽略引用或指针的部分
- 然后再根据实参剩余部分和形参共同决定类型`T`
``` cpp
  /**
   * 第一种函数模板形参
   */
  template<typename T>
  void f(T& param);

  // 具有以下 3 种实参
  int x = 27;
  const int cx = x;
  const int & rx = x;
  //对应的推导结果就是
  f(x);   //T 类型为 int，形参类型为 int&
  f(cx);  //T 类型为 const int，形参类型为 const int&
  f(rx);  //T 类型为 const int，形参类型为 const int&
```

可以看到，实参`rx`的引用被去掉了，最终类型`T`和`cx`是一致的情况。
``` cpp
  /**
   * 第二种函数模板形参
   */
  template<typename T>
  void f(const T& param);

  // 具有以下 3 种实参
  int x = 27;
  const int cx = x;
  const int & rx = x;
  //对应的推导结果就是
  f(x);   //T 类型为 int，形参类型为 const int&
  f(cx);  //T 类型为 int，形参类型为 const int&
  f(rx);  //T 类型为 int，形参类型为 const int&
```

可以看到，这一次的类型`T`统一为`int`型。
- 由于第一种情况下，形参并没有使用`const`限定符，而实参使用了`const`限定符，那么用户的期望是希望`T`是无法被改变的类型，所以`T`被推导成了 const int。
- 但是第二种情况下，形参已经使用了`const`限定符，那么实参是否有`const`已经不重要了，这种情况下就可以使用更为宽松的`int`类型。
``` cpp
  /**
   * 第三种函数模板形参
   */
  template<typename T>
  void f(T* param);

  // 具有以下 2 种实参
  int x = 27;
  const int *px = &x;
  //对应的推导结果就是
  f(&x);   //T 类型为 int，形参类型为 int*
  f(px);  //T 类型为 const int，形参类型为 const int*

  /**
   * 第四种函数模板形参
   */
  template<typename T>
  void f(const T* param);

  // 具有以下 2 种实参
  int x = 27;
  const int *px = &x;
  //对应的推导结果就是
  f(&x);  //T 类型为 int，形参类型为 const int*
  f(px);  //T 类型为 int，形参类型为 const int*
```

可以看到，使用指针的情况也是和引用类似的。

## 形参是一个通用引用

- 如果实参是一个左值，那么类型 T 和形参都会被推导成左值引用
  - 即使形参是右值引用，也会被推导成左值引用
- 如果实参是一个右值，那么就会使用 1.2 节所述规则来进行推导
``` cpp
  //假设如下的函数模板
  template<typename T>
  void f(T&& param);

  //实参如下
  int x = 27;
  const int cx = x;
  const int &rx = x;
  //对应的推导结果就是
  f(x); //x 是左值，T 类型就是 int&，形参类型也是 int&
  f(cx);//cx 是左值，T 类型就是 const int&，形参类型也是 const int&
  f(rx);//rx 是左值，T 类型就是 const int&，形参类型也是 const int&
  f(27);//27 是右值，T 类型就是 int，形参类型是 int&&
```

## 形参既不是指针也不是引用

- 如果实参是一个引用，忽略掉引用部分
- 忽略掉引用后，如果实参部分是 `const` 或 `volatile`，也忽略掉 `const` 或`volatitle`。

> 其中的逻辑在于，函数模板此时的形参是 `passed by value`的形式。
> 那么即使实参是 `const`或`volatile`修饰，它的被拷贝副本就可以不用是`const`或`volatile`修饰了。

``` cpp
  //假如如下的函数模板
  template<typename T>
  void f(T param);

  //实参如下
  int x = 27;
  const int cx = x;
  const int &rx = x;
  const char *const ptr = "Fun with pointers";
  //对应的推导结果就是
  f(x); // 类型 T 和 形参均为 int 型
  f(cx); // 类型 T 和 形参均为 int 型
  f(rx); // 类型 T 和 形参均为 int 型
  f(ptr); //类型 T 和 形参均为 const char * 型
```
- 虽然`cx`和`rx`都是`const`类型，但由于函数模板是普通形参，无论实参如何，形参都是对实参的拷贝。所以形参都是`int`类型。
- 而`ptr`是指向`const char *`型的`const`指针，所以`ptr`本身的`const`被 passed by value，但该`ptr`所指向的对象依然应该是`const char *`。

## 数组参数
需要注意的是：对于模版参数而言，数组参数和指针参数不是一个东西
``` cpp
  //假如如下的函数模板
  template<typename T>
  void f(T param);

  //实参如下
  const char name[] = "J.P. Briggs";
  //对应的推导结果就是
  f(name); //类型 T 和 形参均为 const char * 型
```
上面这种情况下，name 和上一个情况的 ptr 是一样的，但如果函数模版形参是引用的话：
``` cpp
  //假如如下的函数模板
  template<typename T>
  void f(T& param);

  //实参如下
  const char name[] = "J. P. Briggs";//name 的长度是 13 字节
  //对应的推导结果就是
  f(name); //类型 T 为 const char [13], 形参为 const char(&)[13]
```
可以看到此时形参就被推导成为了对固定长度数组的引用

## 函数参数

另一个需要注意的就是函数指针：
``` cpp
  void someFunc(int, double);

  template<typename T>
  void f1(T param);

  template<typename T>
  void f2(T& param);

  f1(someFunc);// 类型 T 和形参均为 void(*)(int, double);

  f2(someFunc);// 类型 T 为 void()(int, double)，形参为 void(&)(int, double)
```

# 理解 auto 类型的推导

## auto 推导与模版推导的相同之处
有了前面的基础，就可以比较容易的理解 `auto` 推导的逻辑。

其实 `auto` 推导和模版推导几乎一致：
- 模版中使用实参和形参决定 `T` 和 形参
- 而 `auto` 就类似于 `T`，其他附加限定符就类似于形参，赋值号右边的就相当于实参

比如如下示例：
``` cpp
  //对 auto 的使用
  auto x = 27; //auto 为 int，x 为 int
  const auto cx = x;//auto 为 int，cx 为 const int
  const auto &rx = x;//auto 为 int，rx 为 const int &

  auto && uref1 = x;// auto 和 uref1 均为 int &
  auto && uref2 = cx;// auto 和 uref2 均为 const int &
  auto && uref3 = 27;//auto 为 int，uref3 为 int &&
  //分别对应于函数模版
  template<typename T>
  void func_for_x(T param);

  func_for_x(27);//T 和 param 均为 int

  template<typename T>
  void func_for_cx(const T param);

  func_for_cx(x);//T 为 int，param 为 const int

  template<typename T>
  void func_for_rx(const T& param);

  func_for_rx(x);// T 为 int，param 为 const int &
```

同样的，`auto` 推导也具有 3 种情况：
- 限定符是指针或引用，但不是通用引用
- 限定符是通用引用
- 限定符既不是指针也不是引用
  

同样的，对于数组和函数指针也有例外：
```cpp
  const char name[] = "R. N. Briggs";//name 的长度为 13 字节

  auto arr1 = name;//auto 和 arr1 均为 const char *
  auto &arr2 = name;//auto 为 const char()[13]，arr2 为 const char (&)[13]

  void someFunc(int, double);

  auto func1 = someFunc;//auto 和 func1 均为 void (*)(int, double)
  auto &func2 = someFunc;//auto 为 void()(int, double),fun1 为 void(&)(int, double)
```
## auto 的独特之处
c11 初始化一个变量有以下 4 种语法：
```cpp
  int x1 = 27;
  int x2(27);
  int x3 = {27};
  int x4{27};
```
以上 4 种语法得到的都是一个`int`型变量，其值为 27。但如果使用 `auto`，情况就有些不同：
``` cpp
  auto x1 = 27; // x1 是 int
  auto x2(27);// x2 是 int
  auto x3 = {27};//x3 是 std::initializer_list<int> 类型并包含一个元素，其值为 27
  auto x4{27};//x4 是 std::initializer_list<int> 类型并包含一个元素，其值为 27
```
可以看到，当使用初始值列表而推导得到的变量类型也是初始值列表。

实际上使用初始值列表推导有两个步骤：
- 因为右值是初始值列表，所以首次推导为 std::initializer_list<T> 类型
- 然后是根据初始值列表中的值，再次推导 T 的类型
  

基于以上认识，下面这些情况下推导就会出错：

``` cpp
  //错误！
  //虽然第一步推导出了 std::initializer_list<T>
  //但是第二步却由于列表中的值类型不同，而导致推导失败
  auto x5 = {1, 2, 3.0};

  auto x = {11, 23, 9};//x 为 std::initializer_list<int> 类型

  template<typename T>
  void f(T param);

  //错误！
  //函数模版却没有 auto 那么智能
  f({11, 23, 9});

  template<typename T>
  void f1(std::initializer_list<T> initList);

  //正确
  //f1 仅仅需要一步推导即可得出 T 为 int
  f1({11, 23, 9});
```

在 c++ 14 中，函数可以使用 auto 作为返回，但是这种情况下就无法正确的推导初始化列表了：
``` cpp
  auto createInitList() {
    //错误，无法推导
    return {1, 2, 3};
  }
```

# 理解 decltype

## `decltype` 规则

- `decltype` 对于变量和表达式的推导，总是忠实的反应其类型
- 对于**左值表达式**，由于其可被赋值，所以推导的类型总是 T&
- c++14 支持 `decltype(auto)`，使得 `auto` 以 `decltype` 的规则进行推导

## 使用 `decltype` 的场合

### c++ 11

在 c++11 中，`decltype` 经常使用的场景是用于模板函数：当输入的参数类型不一样，得到的函数返回类型也不一样。

``` cpp
template<typename Container, typename Index>
auto AuthAndAccess(Container& c, Index i)
-> decltype(c[i]) {
    AuthenticateUser();
    return c[i];
}
```

对于上面的模板函数，要返回 c[i] 类型，但是由于 c 和 i 的类型并无法提前知晓，那么这里使用 decltype 是合理的方式。

### c++ 14 

对于 c++14 而言，从语法上来讲是可以忽略上面的尾置返回类型的，使用 auto 来推导返回的类型，但是这可能会出错：当需要将函数的返回作为左值时：

```cpp
std::deque<int> d;
//由于 auto 推导规则是会省略引用，所以此函数的返回类型最终为 int，而不是 int &
AuthAndAccess(d, 5) = 10;
```

为了能够在 c++14 中返回引用，也需要使用 `decltype`：

```cpp
template<typename Container, typename Index>
decltype(auto) AuthAndAccess(Container& c, Index i) {
    AuthenticateUser();
    return c[i];
}
```

`decltype` 与 `auto` 合用，可以使得以 `decltype` 的形式进行推导：

```cpp
Widget w;
const Widget& cw = w;
//my_widget 的类型是 Widget
auto my_widget = cw;
//my_widget2 的类型是 const Widget&
decltype(auto) my_widget2 = cw;
```

## 使用 `decltype` 的注意事项

- 当直接推导变量名时，得到的是变量名对应的类型
- 当变量名由括号所包含时，得到的是变量名对应类型的引用

这种特性使得在函数返回时，很有趣：

``` cpp
decltype(auto) F1(){
    int x = 0;
    
    //decltype(x) 得到 int
    return x;
}
decltype(auto) F2(){
    int x = 0;
    
    //decltype(x) 得到 int&
    return (x);
}
```

# 查看推导的类型

在理解了基本的推导原则后，为了查看及验证推导的类型，使用**编译时获取**和**基于 boost 库获取**是最为靠谱的方案。


## 在编辑器中获取

在大多数 IDE 中的编辑器，如果代码没有语法错误，那么将鼠标指向被推导的变量，就会出现该变量的提示。

**但是，在一些稍微复杂的场合，这些提示往往是不准确的。**

## 在编译过程中获取

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
	
	if (!vw.empty()) {
		f(&vw[0]);
	}
	
	
	return 0;
}
```

错误输出如下：

> [Error] 'TypeDisplay<const float*> type1' has incomplete type
>
> [Error] 'TypeDisplay<const float* const&> type2' has incomplete type

## 在运行过程中获取

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
> i
> i

i 代表 `int` 类型，但是第二种情况实际上应该是 `int &`。

在运行时的环境中，只有 `boost` 库提供的方法能够准确的显示被推导的类型。

```cpp
#include <boost/type_index.hpp>
template<typename T>
void f(const T& param) {
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
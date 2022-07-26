---
title: C++ Core Guidelines：一些基本规则
tags: 
- cpp
categories:
- cpp
- CoreGuidelines
date: 2022/7/14
updated: 2022/7/26
layout: true
comments: true
---

通过阅读 [CppCoreGuidelines](https://github.com/isocpp/CppCoreGuidelines) 来理解现代 c++ 编码规范，同时也是对 [Effective C++](https://book.douban.com/subject/1842426/)，[Effective Modern C++](https://book.douban.com/subject/25923597/)，[C++ Concurrency in Action](https://book.douban.com/subject/27036085/) 的温习。

<!--more-->

# 准确清晰的表达代码意图

表达的代码意图越完整清晰，越有利于利用编译器来帮我们排除问题。

## 约束限定

```cpp
class Date {
public:
    Month month() const;  // do
    int month();          // don't
    // ...
};
```

上面代码中，第一个函数声明优于第二个函数声明：第一个函数明确表示了返回类型是 Month，且不会改变对象的成员变量。这不仅利于编译器检查，更让代码的可读性更好。

> 关于`const`的相关事项，在[这里有了详细的说明](http://kcmetercec.top/2022/04/10/effective_cpp_use_const/)。

## 充分利用标准库

要善于利用标准库提供的工具，不仅使得代码简短清晰，效率也非常高。

比如，要实现一个函数，比较用户输入的字符串与字符串容器是否有匹配：

```cpp
void f(vector<string>& v) {
    string val;
    cin >> val;
    // ...
    int index = -1;
    for (int i = 0; i < v.size(); ++i) {
        if (v[i] == val) {
            index = i;
            break;
        }
    }
    // ...
}
```

上面的这种方式就是便利的比较，以返回符合条件的索引，那么标准库的`std::find`则更加的简洁明了：

```cpp
void f(vector<string>& v) {
    string val;
    cin >> val;
    // ...
    auto p = find(begin(v), end(v), val);  // better
    // ...
}
```

以上一行代码，便清晰明确的表达了上面 7 行代码想要表达的意图。

再比如要将标准输入的值存入内存：

```cpp
int sz = 100;
int* p = (int*) malloc(sizeof(int) * sz);
int count = 0;
// ...
for (;;) {
    // ... read an int into x, exit loop if end of file is reached ...
    // ... check that x is valid ...
    if (count == sz)
        p = (int*) realloc(p, sizeof(int) * sz * 2);
    p[count++] = x;
    // ...
}
```

以上杂乱的代码，使用`std::vector`是个更好的选择：

```cpp
vector<int> v;
v.reserve(100);
// ...
for (int x; cin >> x; ) {
    // ... check that x is valid ...
    v.push_back(x);
}
```

## 参数的正确命名

为了更好的可读性，变量、函数参数的名称等都需要一个清晰的命名，必要时候需要为其自定义类型。

```cpp
change_speed(double s);   // bad: what does s signify?
// ...
change_speed(2.3);
```

上面这个代码，并没有明确标出 s 所对应的单位。

```cpp
change_speed(Speed s);    // better: the meaning of s is specified
// ...
change_speed(2.3);        // error: no unit
change_speed(23_m / 10s);  // meters per second
```

这里定义了新的类型，便可以带有单位。

# 编译时检查优于运行时检查

在编译时检查既能很好的表达意图，还能提高代码的运行性能。

比如，下面的代码想要检查`int`类型是否大于 32 位：

```cpp
int bits = 0;         
for (int i = 1; i; i <<= 1)
    ++bits;
if (bits < 32)
    std::cerr << "int too small\n";
```

上面代码可读性不好，且会占用运行时时间，而在编译时检查则一行代码就可以了：

```cpp
static_assert(sizeof(int) >= 4);    // do: compile-time check
```

在比如需要给函数传入数组地址，那么一般也会需要传入数组的大小：

```cpp
void read(int* p, int n);   // read max n integers into *p

int a[100];
read(a, 1000);    // bad, off the end
```

但是当数组大小值传入大于数组时，就会引发数组越界。这种情况下一个方法是使用`std::array<T>`替代传统数组，另一个方法是使用`std::span<T>`由编译器来获取数组的大小：

```cpp
#include <iostream>
#include <span>
 
void ReadArray(std::span<int> array) {
    std::cout << "The size of array is " << array.size();
}

int main(int argc, char* argv[]) {
    int array[100] = {};
    
    ReadArray(array);
    
    return 0;
}
```

# 编译时无法检查的运行时应尽量检查

很多错误无法在编译期完成检查，那么在运行期，需要尽可能的检查其余错误，避免程序漏洞。

比如下面的代码就忽略了运行期检查：

```cpp
// separately compiled, possibly dynamically loaded
extern void f(int* p);

void g(int n) {
    // bad: the number of elements is not passed to f()
    f(new int[n]);
}
```

上面直接在形参处申请了动态内存传给外部库函数`f`，那么当前代码都无法获取到动态内存的地址，就无法做任何错误检查（包括申请的地址，以及申请的大小）。

下面假设库函数加上了数组大小：

```cpp
// separately compiled, possibly dynamically loaded
extern void f2(int* p, int n);

void g2(int n) {
    f2(new int[n], m);  // bad: a wrong number of elements can be passed to f()
}
```

直接以`new`的形式传入参数也是不可取的，因为并不知道`f2`内部是否会`delete`这段内存，且传入数组的大小也会出错。

下面再改进使参数成为智能指针：

```cpp
// separately compiled, possibly dynamically loaded
// NB: this assumes the calling code is ABI-compatible, using a
// compatible C++ compiler and the same stdlib implementation
extern void f3(std::unique_ptr<int[]>, int n);

void g3(int n) {
    f3(std::make_unique<int[]>(n), m);    // bad: pass ownership and size separately
}
```

这种方式就不用担心指针释放的问题，但是智能指针不能传入申请内存的大小，所以还是可能出错。

所以最好的方式就是传入对象，该对象包含了内存的大小：

```cpp
extern void f4(vector<int>&);   // separately compiled, possibly dynamically loaded
extern void f4(span<int>);      // separately compiled, possibly dynamically loaded
                                // NB: this assumes the calling code is ABI-compatible, using a
                                // compatible C++ compiler and the same stdlib implementation

void g3(int n) {
    vector<int> v(n);
    f4(v);                     // pass a reference, retain ownership
    f4(span<int>{v});          // pass a view, retain ownership
}
```
# 尽早的捕获运行时错误

比如下面的代码，当 m > n 时，就会发生数组越界：

```cpp
void increment1(int* p, int n) {
    for (int i = 0; i < n; ++i) ++p[i];
}

void use1(int m) {
    const int n = 10;
    int a[n] = {};
    // ...
    increment1(a, m);   // maybe typo, maybe m <= n is supposed
                        // but assume that m == 20
    // ...
}
```

而通过使用`std::span`则可以捕获该问题：

```cpp
#include <iostream>
#include <span>
 
void increment2(std::span<int> p) {
    std::cout << "array size: " << p.size() << "\n";
    
    for (int& x : p) ++x;
}

void use2(void) {
    const int n = 10;
    int a[n] = {};
    // ...
    increment2(a);    // maybe typo, maybe m <= n is supposed
    // ...
    
    for (int i = 0; i < n; ++i) {
        std::cout << a[i] << ",";
    }
    std::cout << "\n";
}

int main(int argc, char* argv[]) {
    use2();
    
    return 0;
}
```

# 尽量避免资源泄露

这里的资源除了内存，还有文件句柄、socket、控制权等等。

就算是很小的几个字节泄露，对于需要长时间运行的程序而言都会最终造成灾难。

比如下面这个文件句柄泄露的例子：

```cpp
void f(char* name) {
    FILE* input = fopen(name, "r");
    // ...
    if (something) return;   // bad: if something == true, a file handle is leaked
    // ...
    fclose(input);
}
```
当`if`为真时，该文件句柄便泄露了，长时间运行该函数，会到达操作系统限制量而杀死该进程。

显然，这种情况使用 RAII 是最合适不过了：

```cpp
void f(char* name) {
    std::ifstream input {name};
    // ...
    if (something) return;   // OK: no leak
    // ...
}
```

当该函数退出后，`std::ifstream`的析构被调用，从而会释放该资源。

#  不要浪费时间和空间

```cpp
#include <iostream>
#include <string>
#include <exception>
#include <stdexcept>
#include <stdlib.h>
#include <cstring>

struct X {
    char ch;
    int i;
    std::string s;
    char ch2;

    X& operator=(const X& a) {

    }

    X(const X&) {

    }
    X() = default;
};

X waste(const char* p) {
    if (!p) throw std::invalid_argument("nullptr");
    int n = std::strlen(p);
    auto buf = new char[n];
    if (!buf) throw std::bad_alloc();
    for (int i = 0; i < n; ++i) buf[i] = p[i];
    // ... manipulate buffer ...
    X x;
    x.ch = 'a';
    x.s = std::string("", n);    // give x.s space for *p
    for (int i = 0; i < x.s.size(); ++i) x.s[i] = buf[i];  // copy buf into x.s
    delete[] buf;
    return x;
}

void driver() {
    X x = waste("Typical argument");

    std::cout << "contents of x : " << x.s << "\n";
}

int main() {
    driver();

    return 0;
}
```

以上这段代码，在时间和空间上都有所浪费：

1. 类`X`中的成员`i`和`ch2`都没有被使用，这造成了内存空间的浪费
2. 由于类`X`显示定义了拷贝构造和拷贝赋值函数，导致编译期没有默认生成移动构造函数，所以无法使用返回值优化（RVO），造成了运行时间的浪费（默认函数参考[此文章](http://kcmetercec.top/2022/04/13/effective_cpp_default_func/)）
3. 将形参`p`拷贝到`string`，并不需要再申请一段临时的空间来存储数据后再来拷贝，这造成了运行时间的浪费

修改后的高效代码应该如下：

```cpp
#include <iostream>
#include <string>
#include <exception>
#include <stdexcept>
#include <stdlib.h>
#include <cstring>

struct X {
    char ch;
    std::string s;
};

X waste(const char* p) {
    if (!p) throw std::invalid_argument("nullptr");

    X x;
    x.ch = 'a';
    x.s = std::string(p, std::strlen(p));

    return x;
}

void driver() {
    X x = waste("Typical argument");

    std::cout << "contents of x : " << x.s << "\n";
}

int main() {
    driver();

    return 0;
}
```

再比如下面的循环：

```cpp
void lower(zstring s) {
    for (int i = 0; i < strlen(s); ++i) s[i] = tolower(s[i]);
}
```

每执行一次，都要执行`std::strlen`，这浪费了很多时间。正确的做法是进入循环前首先获取一次长度存入变量，然后直接使用该变量即可。

---
title: '[What] Effective  C++ ：实现'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---

说明在实现一个类时，需要注意的要点。
<!--more-->

# 尽可能延后变量定义式的出现时间

当一个类实例化对象时，那么就会调用其构造函数，而在离开作用域时就会调用其析构函数。

那么要是这个对象在某些情况下未使用，就会白白的浪费时间。

```cpp
std::string EncryptPassword(const std::string& password){
    std::string encrypted(password);
    
    if(password.length() < MinimumPasswordLength){
        throw logic_error("Password is too short!");
    }
    // 对 encrypted 的使用
    
    return encrypted;
}
```

比如上面这个代码，如果抛出了异常，那么对象`encrypted`就不会被使用。这种情况下会由于其构造和析构函数而浪费时间。

如果延后定义`encrypted`，那么就不会出现这种情况：

```cpp
std::string EncryptPassword(const std::string& password){
    if(password.length() < MinimumPasswordLength){
        throw logic_error("Password is too short!");
    }
    std::string encrypted(password);
    
    // 对 encrypted 的使用
    
    return encrypted;
}
```

# 尽量少做转型动作

- `const_cast`：主要被用来将对象的常量性移除

- `dynamic_cast`：将基类安全的向下转型到其派生类

  > 动态转型的效率不高，需要谨慎使用。更多时候应该试着用无需转型的设计来替代。

- `reinterpret_cast`：对原始内存的重新解释，比如将整型转为指针类型，反之亦然

- `static_cast`：强制隐式转换，一般进行非指针类型的转换。比如将`int`转为`double`等

要尽量少的使用转型动作，用之前要深思熟虑。

# 避免返回 handles 指向对象内部成分

这里的`handles`指的是函数返回内部成员变量的引用、指针或迭代器。

这就会导致：

1. 降低对象的封装性：本来成员变量是`private`，这样返回以后反而相当于`public`

2. 对象被修改的风险：即使一个函数使用`const`修饰，只要返回`handles`，那它就有可能被外部所修改

   > 这种情况下，可以在返回类型上加上`const`限定

3. 如果对象是一个临时对象，对象返回内部成员的`handles`，然后**该临时对象的内存就被释放了，而获取到成员 handles 的外部对象，就处于`dangling`的状态！**

对于第三种情况，最为常见的就是使用临时的`std::string`获得其`c_str()`：

```cpp
#include <iostream>
#include <string>
int main()
{
    const char* str = std::string("hello world!").c_str();
    // 正确的做法应该像下面这样，将临时对象拷贝。
    // 否则最终的打印结果便是非预期的
    //std::string str = std::string("hello world!").c_str();

    std::cout << "The value of string are: " << str << "\n";

    return 0;
}
```

> 上面这段代码，在`g++`中可以获取到正常结果，但在`msvc`中就会运行出错。

# 为“异常安全”而努力是值得的

异常安全是指，当异常发生时，确保：

1. 不泄漏任何资源
2. 不允许数据被破坏

比如下面这段代码：

```cpp
void PrettyMenu::changeBackground(std::istream& imgSrc) {
    lock(&mutex);
    delete bgImage;
    ++imageChnages;
    bgImage = new Image(imgSrc);
    unlock(&mutex);
}
```

假设`new Image`抛出异常，那么：

1. 锁泄漏：互斥锁`mutex`没有被释放
2. 成员变量被破坏：`bgImage`指向一个已被删除的对象

对于锁泄漏的问题，可以使用`RAII`对象，只要函数返回便释放锁：

```cpp
void PrettyMenu::changeBackground(std::istream& imgSrc) {
    Lock m1(&mutex);
    delete bgImage;
    ++imageChnages;
    bgImage = new Image(imgSrc);
}
```

对于第二种情况，使用`copy and swap`策略：

```cpp
struct PMImpl {
	std::shared_ptr<Image> bgImage;
    int imageChanges;
};
class PrettyMenu {
	// ...
    private:
    Mutex mutex;
    std::shared_ptr<PMImpl> pImpl;
};

void PrettyMenu::changeBackground(std::istream& imgSrc) {
    Lock m1(&mutex);
    
    // 创建一个临时对象，使用指针指针来管理它
    // 临时对象的内容是成员变量的副本
    std::shared_ptr<PMImpl> pNew(new PMImpl(*pImpl));
    // 修改临时对象
    // 如果此处发生了异常，那么不会对当前对象有任何影响
    pNew->bgImage.reset(new Image(imgSrc));
    ++pNew->imageChanges;
    
    // 临时对象与当前对象置换
    std::swap(pImpl, pNew);
    
    // 最后临时对象资源会被自动释放
}
```

# 透彻了解`inline`

`inline`函数虽然可以提高运行效率，但是由于会对此函数的每一个调用都以函数的本体替换，所以可能会增加代码段的体积。

`inline`也只是对编译器的一个申请，可以以两种方式提出：

- 隐喻：将函数定义于`class`内
- 明确：在函数定义前加上`inline`关键字

很多时候，编译器都不会对一个`inline`函数进行真正的展开，比如：

- 函数过于复杂
- 函数内部调用了虚函数：有虚函数意味着需要运行时重载，所以无法在编译器就展开该函数
- 有函数指针指向了该函数
- 隐含编译出的代码会有函数指针指向该函数

`inline`函数还有一个很不好的影响：当函数的本地被改变时，所有使用该函数的文件都需要被重新编译！

# 将文件间的编译依存关系降至最低

有两个方法降低编译依赖：

1. 在类声明中，私有成员变量如果是类对象。那么前置声明该类，然后使用指针的方式指向该对象。然后在构造函数中申请指针对应的内存。

   > 这增加了构造函数的执行时间，也会多消耗多个指针占用的内存。
   >
   > 并且在编码使用时，也要解引用，略微麻烦。

2. 为多个类定义统一接口，该接口是一个纯虚类，这样继承类的实现修改并不会影响该接口。

   > 调用成员函数时，会有通过虚指针间接跳跃到具体实现函数的性能开销。

google 编码规范则是建议[尽量避免使用前置声明](https://zh-google-styleguide.readthedocs.io/en/latest/google-cpp-styleguide/headers/#forward-declarations)，因为还有其他的坑等着你跳……

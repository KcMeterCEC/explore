---
title: '[What] Effective Modern C++ ：使用 weak_ptr 来检查 shared_ptr 资源是否已经释放'
tags: 
- c++
categories: 
- language
- c/c++
- Effective
layout: true
---
`std::weak_ptr`附属于`shared_ptr`，`weak_ptr`并不会影响资源引用计数的增加和减小，当最后一个`shared_ptr`被销毁时，资源便会被释放，就算现在依然存在`weak_ptr`。
<!--more-->

`weak_ptr`并不能够被解引用，它的目的主要是为了探测`shared_ptr`之间所指向的资源是否已经释放。

其应用场景一般是在当需要新建一个`shared_ptr`时或需要操作该资源时，首先使用`weak_ptr`来查看该资源是否已经释放，以避免未定义的行为。

要理解其使用场景，首先查看下面的代码：

```cpp
#include <vector>
#include <iostream>
#include <array>
#include <memory>

int main(void){
    auto spi = std::make_shared<int>(10);
    std::weak_ptr<int> wpi(spi);

    std::cout << "The value of spi is " << *spi << "\n";
    std::cout << "Is wpi expired: " << wpi.expired() << "\n";

    //资源已被释放
    spi = nullptr;

    std::cout << "Is wpi expired: " << wpi.expired() << "\n";

    return 0;
}
```

当`shared_ptr`所指向的资源被释放时，`weak_ptr`的`expired()`方法将返回`true`。

但如果是在多线程的应用场景，就有可能出现临界区问题：

- 线程 T1 通过`expired()`返回`false`判定资源还没有被释放，于是决定新建一个`shared_ptr`
- 在线程 T1 执行完`expired()`后，线程 T2 抢占了 T1 运行，T2 中指向同一资源的最后一个`shared_ptr`被销毁，该资源被释放
- T1 重新运行，该`shared_ptr`指向一段未知的堆区域，接下来对该`shared_ptr`操作结果都是未知的

所以，加锁是必须的：

```cpp
#include <vector>
#include <iostream>
#include <array>
#include <memory>

int main(void){
    auto spi = std::make_shared<int>(10);
    std::weak_ptr<int> wpi(spi);

    std::cout << "The value of spi is " << *spi << "\n";

    auto spi2 = wpi.lock();
    if(spi2 != nullptr){
        std::cout << "The value of spi2 is " << *spi2 << "\n";
    }

    //资源已被释放
    spi = nullptr;
    spi2 = nullptr;

    auto spi3 = wpi.lock();
    if(spi3 != nullptr){
        std::cout << "The value of spi3 is " << *spi3 << "\n";
    }else{
        std::cout << "The resource is not existent!\n";
    }

    return 0;
}
```









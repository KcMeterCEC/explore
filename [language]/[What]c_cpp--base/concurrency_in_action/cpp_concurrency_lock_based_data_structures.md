---
title: C++ concurrency：设计基于锁的可以并发操作的数据结构
tags: 
- cpp
categories:
- cpp
- concurrency
date: 2022/5/22
updated: 2022/5/26
layout: true
comments: true
---

除了用户主动使用互斥锁来保护共享数据，也可以在设计共享数据结构的时候让其可以被并发的访问。

这样子的数据结构对用户就相对更加的友好，对于用户来说它就是多线程安全的。

但不管怎么说，这种数据结构在被并发访问的时候，其实是将多个线程的访问进行了串行化。那么就需要将互斥的区间设计的越小越好，以达到尽量高的并发性。

<!--more-->

# 设计可并发访问数据结构的基本原则

设计可以并发访问的数据结构时，需要考虑这个数据结构可以安全的被多线程访问，且尽量的做到真正的并发。

那么就需要注意：
1. 操作数据结构一定要是互斥的
2. 如果是基于其他数据结构的适配器，那么需要注意保证多个操作动作的完整性。避免在几个操作步骤中，可以被其他线程打断（比如基于`stack`的适配器[threadsafe_stack](http://kcmetercec.top/2022/05/17/cpp_concurrency_share_data/#%E6%9C%80%E7%BB%88%E7%89%88%E6%9C%AC) ）
3. 注意操作数据过程中可能会抛出异常而破坏了操作的完整性
4. 尽量使得互斥区间小，且要避免死锁

除此之外，还需要考虑：
1. 对于 c++ 而言，这里指的数据结构其实都是用类来表示的，那么当类支持赋值构造、swap、拷贝构造等这类函数时。它们是否与类的其他成员函数可以并发的访问，还是需要用户来主动的保证互斥？
2. 当需要使得互斥区间尽量小时，需要考虑：
  - 这段被锁保护的区间中的一部分，是否可以移除到锁的外面？
  - 这个数据结构的不同部分，可以被不同的互斥量所保护吗？
  - 所有的操作方法都需要同一等级的保护吗？
  - 可以修改一下数据结构来提高并发度而不影响代码语义吗？

总之来讲，一切的目的都是为了让临界区尽量的小，以达到较高的并发度。

# 简易的方式

比较简单的方式，就是使用互斥锁来保护共享数据。使用多个互斥锁往往比使用 1 个互斥锁更加复杂，这可能会造成：
1. 多个临界区之间的抢占导致数据一致性出问题
2. 多个锁的获取和释放会容易导致死锁

## 多线程安全`stack`

多线程安全的栈在[之前](http://kcmetercec.top/2022/05/17/cpp_concurrency_share_data/#%E6%B3%A8%E6%84%8F%E6%8E%A5%E5%8F%A3%E8%B0%83%E7%94%A8%E6%89%80%E9%80%A0%E6%88%90%E7%9A%84%E5%86%85%E9%83%A8%E7%AB%9E%E6%80%81)就已经完成过了，但是有几点是需要注意的：
1. 该结构的构造及析构函数并不是多线程安全的，所以用户需要保证构造和析构时不能被多线程访问。这相对比较好实现。
2. 该结构并没有同步机制，所以其他线程在想读取栈数据时，需要注意捕获当栈为空时会抛出的异常。

所以，在多线程中需要使用容易进行通信时，同步机制是需要的。

## 带同步机制的多线程安全`queue`

与多线程安全的`stack`相仿，多线程安全的`queue`相当于是`std::queue`的适配器，并且在次基础上使用了条件变量以同步。

```cpp
template<typename T>
class threadsafe_queue {
private:
	// 在 const 成员函数中需要获取互斥锁，所以需要修饰为 mutable
    mutable std::mutex mut;
    std::queue<T> data_queue;
    std::condition_variable data_cond;
public:
    threadsafe_queue() {
    }
    void push(T new_value) {
        std::lock_guard<std::mutex> lk(mut);
        data_queue.push(std::move(new_value));
        // 通知等待线程
        data_cond.notify_one();         
    }
    void wait_and_pop(T& value) {
        std::unique_lock<std::mutex> lk(mut);
        // 等待消息唤醒
        data_cond.wait(lk, [this]{return !data_queue.empty();});
        value = std::move(data_queue.front());
        data_queue.pop();
    }
    std::shared_ptr<T> wait_and_pop() {
        std::unique_lock<std::mutex> lk(mut);
        // 等待消息唤醒
        data_cond.wait(lk, [this]{return !data_queue.empty();});    
        std::shared_ptr<T> res(
            std::make_shared<T>(std::move(data_queue.front())));
        data_queue.pop();
        return res;
    }
    bool try_pop(T& value) {
        std::lock_guard<std::mutex> lk(mut);
        if(data_queue.empty())
            return false;
        // 这里已经确认队列不为空了，就可以直接获取数据了
        value = std::move(data_queue.front());
        data_queue.pop();
        return true;
    }
    std::shared_ptr<T> try_pop() {
        std::lock_guard<std::mutex> lk(mut);
        if(data_queue.empty())
            return std::shared_ptr<T>();    
        std::shared_ptr<T> res(
            std::make_shared<T>(std::move(data_queue.front())));
        data_queue.pop();
        return res;
    }
    bool empty() const {
        std::lock_guard<std::mutex> lk(mut);
        return data_queue.empty();
    }
};
```
可以看到，这种加上同步的方式比起轮询检查队列是否有数据的方式更加的高效，这避免了 CPU 做的一些无用功。

对于上面的类还可以再改进一下，在智能指针重载版本的`wait_and_pop()`函数中，由于要创建智能指针，则有可能会在创建时抛出异常。

> 其实这种情况下抛出异常不会对数据结构有损坏，因为`pop`是在创建智能指针之后才调用的。

为了避免这种情况，可以将`queue`的每个元素用智能指针来表示，这样指针的拷贝就不会抛出异常了：
```cpp
template<typename T>
class threadsafe_queue {
private:
	// 在 const 成员函数中需要获取互斥锁，所以需要修饰为 mutable
    mutable std::mutex mut;
    // 使用智能指针作为元素来存储
    std::queue<std::shared_ptr<T> > data_queue;
    std::condition_variable data_cond;
public:
    threadsafe_queue() {
    }
    void push(T new_value) {
		// 先创建对象再获取锁，以减少临界区
        std::shared_ptr<T> data(
            std::make_shared<T>(std::move(new_value)));    
        std::lock_guard<std::mutex> lk(mut);
        data_queue.push(data);
        // 通知等待线程
        data_cond.notify_one();
    }
    void wait_and_pop(T& value) {
        std::unique_lock<std::mutex> lk(mut);
        // 等待消息唤醒
        data_cond.wait(lk,[this]{return !data_queue.empty();});
        // 这里要解引用得到对象内容
        value = std::move(*data_queue.front());     
        data_queue.pop();
    }
    std::shared_ptr<T> wait_and_pop() {
        std::unique_lock<std::mutex> lk(mut);
        // 等待消息唤醒
        data_cond.wait(lk, [this]{return !data_queue.empty();});
        // 这里就直接是智能指针的拷贝了
        std::shared_ptr<T> res = data_queue.front();
        data_queue.pop();
        return res;
    }    
    bool try_pop(T& value) {
        std::lock_guard<std::mutex> lk(mut);
        if(data_queue.empty())
            return false;
        // 这里要解引用得到对象内容    
        value = std::move(*data_queue.front());     
        data_queue.pop();
        return true;
    }
    std::shared_ptr<T> try_pop() {
        std::lock_guard<std::mutex> lk(mut);
        if(data_queue.empty())
            return std::shared_ptr<T>();
        // 这里就直接是智能指针的拷贝了    
        std::shared_ptr<T> res = data_queue.front();    
        data_queue.pop();
        return res;
    }
    bool empty() const {
        std::lock_guard<std::mutex> lk(mut);
        return data_queue.empty();
    }
};
```
这样子改动以后，还有一个好处是提高了并发度：在`push()`函数中，智能指针的创建是在临界区之外了。

如果为了更高的并发度，那就不能简单的使用标准库所提供的容器，而是要自己设计底层容器。只有这样子才能够做到更加细粒度的临界区。


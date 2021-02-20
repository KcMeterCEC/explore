---
title: '[What] C++ Concurrency in Action 2nd ：线程间共享数据'
tags: 
- c++
date:  2021/2/6
categories: 
- language
- c/c++
- Concurrency
layout: true
---
这一章主要熟悉用 c++ 来编写可以跨平台的数据共享操作。
<!--more-->

# 使用互斥量保护临界区

## 基本使用

c++ 提供了`std::mutex`来表示一个互斥量，其对应的`lock()`和`unlock()`则分别代表获取和释放锁。

但如果直接这样使用，容易造成获取的锁忘了释放的情况（比如线程异常退出，还来不及释放锁）。那么下次再来获取锁就会造成死锁。

所以，c++ 提供了` std::lock_guard`，在构造函数中获取锁，在析构函数中释放锁。这种 RAII 操作大大的降低了程序员的心智负担。

```cpp
#include <iostream>
#include <mutex>
#include <vector>
#include <thread>

static int val = 0;
static std::mutex val_mtx;
static void Task(void){
    //有了 RAII ，生活变得真美好
    std::lock_guard<std::mutex> mtx_guard(val_mtx);
    //c++ 17 中，有模板参数推导，所以可以更加简洁(为了兼容性，建议使用上面的写法)
//    std::lock_guard mtx_guard(val_mtx);
    for(int i = 0; i < 1000; ++i){
        val += 1;
    }
}

int main(void){
    std::vector<std::thread> threads;
    for(int i = 0; i < 10; ++i){
        threads.emplace_back(Task);
    }
    for(auto &v : threads){
        v.join();
    }

    std::cout << "The value of val is " << val << "\n";

    return 0;
}
```

实际使用中，一般将临界区数据和互斥量放在类的私有权限中，通过成员函数的方式来进行互斥的操作。

## 结构化共享数据

结构化共享数据需要注意的是要**避免将共享数据的指针或引用传递出去，因为这样会绕过互斥量而造成未定义行为**：

```cpp
class some_data
{
    int a;
    std::string b;
public:
    void do_something();
};
class data_wrapper
{
private:
    some_data data;
    std::mutex m;
public:
    template<typename Function>
    void process_data(Function func)
    {
		//这里虽然使用了互斥量保护了 data，
		//但是却将 data 传递给了外部函数 func 
        std::lock_guard<std::mutex> l(m);
        func(data);                      
    }
};
some_data* unprotected;
//将被保护数据的地址赋值给了 unprotected
void malicious_function(some_data& protected_data)
{
    unprotected=&protected_data;
}
data_wrapper x;
void foo()
{
    x.process_data(malicious_function);
    //最后 unprotected 就可以绕过互斥量 m 而随意的操作 data   
    unprotected->do_something();         
}
```

## 注意接口调用所造成的内部竞态

以`std::stack`为例，虽然它的每个接口都保证是多线程的安全的。但是对其接口的应用却需要特别注意：

```cpp
std::stack<int> s;
if(!s.empty())   
{
	//假设目前 s 中只有一个元素了
	//如果在这之间，有另外一个线程抢占并执行了 s.pop()
	//那么下面这两行代码的访问行为便是未知的
    int const value=s.top();
    //同样的，假设是在下面这行之间发生了抢占并执行了 s.pop()，下面这段代码也会出问题
    s.pop();               
    do_something(value);
}
```

要解决这个问题，最简单粗暴的方式就是使用互斥量将这整个步骤原子化。但如果 stack 元素所占内存太大时，进行元素拷贝的时间过长，有些类型将会抛出`std::bad_alloc`异常。那么这种解决方案在元素占用内存大的情况下就不适用了。

### 元素使用引用

既然进行大内存拷贝会抛出异常，那么就将栈中的元素使用引用来代替就可以了。但这就需要在创建引用的同时就要提前创建对应绑定的对象，这在很多场合就会比较麻烦。

### 使用不会抛出异常的元素

有些类型进行拷贝或移动时并不会抛出异常，那么就可以限制`stack`只使用这些类型。

### 返回元素的地址

另外一个避免拷贝的方式就是返回元素的地址，然后使用`std::shared_ptr`来管理元素的内存。

### 最终版本

上面解决方案的 1 和 3 是比较合理的，最终对`std::stack`的封装如下：

```cpp
#include <exception>
#include <stack>
#include <mutex>
#include <memory>
#include <iostream>

struct empty_stack: std::exception
{
    const char* what() const throw()
    {
        return "empty stack";
    }

};

template<typename T>
class threadsafe_stack
{
private:
    std::stack<T> data;
    mutable std::mutex m;
public:
    threadsafe_stack(){}
    threadsafe_stack(const threadsafe_stack& other)
    {
        std::lock_guard<std::mutex> lock(other.m);
        data=other.data;
    }
    threadsafe_stack& operator=(const threadsafe_stack&) = delete;

    void push(T new_value)
    {
        std::lock_guard<std::mutex> lock(m);
        data.push(new_value);
    }
    std::shared_ptr<T> pop()
    {
        std::lock_guard<std::mutex> lock(m);
        if(data.empty()) throw empty_stack();
        std::shared_ptr<T> const res(std::make_shared<T>(data.top()));
        data.pop();
        return res;
    }
    void pop(T& value)
    {
        std::lock_guard<std::mutex> lock(m);
        if(data.empty()) throw empty_stack();
        value=data.top();
        data.pop();
    }
    bool empty() const
    {
        std::lock_guard<std::mutex> lock(m);
        return data.empty();
    }
};

int main()
{
    threadsafe_stack<int> si;
    si.push(5);
    if(!si.empty())
    {
        int x;
        si.pop(x);

        std::cout << "The value of x is " << x << "\n";
    }

}
```

可以看到：

1. 使用互斥量将原始的`top()`和`pop()`进行原子化以避免竞态
2. 返回元素使用引用或地址，以避免大量的拷贝
3. 当元素为空时，抛出异常以提醒用户代码

## 死锁问题及其解决

死锁问题在编码中经常遇到，其中一个比较简单的解决办法就是：保持获取和释放互斥量的顺序一致。

> 但是这在实际的操作中并不是那么的容易。

c++ 提供了`std::lock`用于一次性获取多个锁，以避免死锁：

```cpp
class some_big_object;
void swap(some_big_object& lhs,some_big_object& rhs);
class X
{
private:
    some_big_object some_detail;
    std::mutex m;
public:
    X(some_big_object const& sd):some_detail(sd){}
    friend void swap(X& lhs, X& rhs)
    {
        if(&lhs==&rhs)
            return;
        //std::lock 尝试同时获取两个互斥量，如果只能获取到其中一个，那么会自动释放获取到的互斥量
        std::lock(lhs.m,rhs.m);
        //使用 std::adopt_lock 以让 lock_guard 析构时释放锁，但不会在构造时获取锁    
        std::lock_guard<std::mutex> lock_a(lhs.m,std::adopt_lock);  
        std::lock_guard<std::mutex> lock_b(rhs.m,std::adopt_lock);
        //在 c++17 中，可以使用 scoped_lock 来替换上面 3 行代码
        //std::scoped_lock guard(lhs.m,rhs.m);
        swap(lhs.some_detail,rhs.some_detail);
    }
};
```

使用`std::lock`加上`std::lock_guard`的 RAII 机制，就能避免很多场合的死锁情况。

当然，实际编码场景中也会有散步在各处的获取互斥量的操作，这就需要程序员有良好的习惯来避免死锁了。

## 避免死锁的一些编码准则

除了获取锁会导致死锁以外，两个线程的相互`join()`也会导致死锁，这些都是需要在编码过程中尽量避免的。

### 避免嵌套获取锁

当一个线程已经获取了一个锁并且还未释放的时候，就不要再获取其它的锁了。

如果每个线程都遵守这个规则，那么就不会那么容易造成死锁。因为每个线程都管理自己所获取的那个锁而不会获取到其它线程的锁。

如果确实需要同时获取到多个锁，那么使用`std::lock`和`std::lock_guard`来管理这些锁以避免死锁。

### 获取锁时避免调用用户提供的代码

当获取到一个锁时，要避免调用用户提供的代码。因为并不知道用户提供的代码是否也获取了其它的锁。

### 按确定的顺序获取锁

有的时候获取锁的代码散步在多处，获取多个锁时不能使用`std::lock`这种简单的写法。

这种情况下就需要所有相关线程按照统一的顺序进行锁的获取。

### 使用一个获取锁的层级

简单的说就是：为各个锁分一个高低层级，并且获取锁的顺序必须是由高向低层级的方向获取。

那么这里的重点就是要设计一个可以识别出层级高低的锁，核心就在于使用`thread_local`变量以共享同一个线程中的层级：

```cpp
class hierarchical_mutex
{
    std::mutex internal_mutex;
    //保存当前锁代表的层级
    unsigned long const hierarchy_value;
    //存储上一级锁的层级值
    unsigned long previous_hierarchy_value;
    //使用线程生命周期变量 this_thread_hierarchy_value 保存当前线程的层级
    static thread_local unsigned long this_thread_hierarchy_value;    
    void check_for_hierarchy_violation()
    {
		//新获取的锁层级必须要低于当前的层级，否则就抛出异常
        if(this_thread_hierarchy_value <= hierarchy_value)    
        {
            throw std::logic_error(“mutex hierarchy violated”);
        }
    }
    void update_hierarchy_value()
    {
        //将当前层级进行存储，类似于压栈的操作
        previous_hierarchy_value=this_thread_hierarchy_value;
        //更新当前线程所处于的层级
        this_thread_hierarchy_value=hierarchy_value;
    }
public:
    explicit hierarchical_mutex(unsigned long value):
    	//创建锁的时候，就规定好了它的层级，以后就不能改了
        hierarchy_value(value),
        previous_hierarchy_value(0)
    {}
    void lock()
    {
        check_for_hierarchy_violation();
        //这里需要先获取锁，然后再修改变量以保证原子性 
        internal_mutex.lock();          
        update_hierarchy_value();      
    }
    void unlock()
    {
		//保证释放的时候也必须是由低到高释放
        if(this_thread_hierarchy_value!=hierarchy_value)
            throw std::logic_error(“mutex hierarchy violated”);  
        //将存储的上一级的值取出来，相当于出栈
        this_thread_hierarchy_value=previous_hierarchy_value;    
        internal_mutex.unlock();
    }
    bool try_lock()
    {
        check_for_hierarchy_violation();
        if(!internal_mutex.try_lock())     
            return false;
        update_hierarchy_value();
        return true;
    }
};
//最开始使用最大值，以保证互斥量是可以被获取的
thread_local unsigned long
    hierarchical_mutex::this_thread_hierarchy_value(ULONG_MAX);
```

那么在使用的时候，只要是按照层级顺序进行获取就可以正常工作，否则就会抛出异常：

```cpp
hierarchical_mutex high_level_mutex(10000);    
hierarchical_mutex low_level_mutex(5000);    
hierarchical_mutex other_mutex(6000);   
int do_low_level_stuff();
int low_level_func()
{
    std::lock_guard<hierarchical_mutex> lk(low_level_mutex);   
    return do_low_level_stuff();
}
void high_level_stuff(int some_param);
void high_level_func()
{
	//先获取的高层级，再获取低层级，这个顺序是没有问题的
    std::lock_guard<hierarchical_mutex> lk(high_level_mutex);  
    high_level_stuff(low_level_func());         
}
void thread_a()      
{
    high_level_func();
}
void do_other_stuff();
void other_stuff()
{
    high_level_func();     
    do_other_stuff();
}
void thread_b()     
{
	//先获取低层级，然后又获取高层级，就会抛出异常
    std::lock_guard<hierarchical_mutex> lk(other_mutex);    
    other_stuff();
}
```

hierarchical_mutex 既然可以被`std::lock_guard`所使用，是因为它提供了`lock`,`unlock`,`try_lock`标准处理函数。


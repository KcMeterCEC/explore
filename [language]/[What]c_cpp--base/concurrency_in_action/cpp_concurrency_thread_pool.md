---
title: C++ concurrency：进一步的线程管理
tags: 
- cpp
categories:
- cpp
- concurrency
date: 2022/5/28
updated: 2022/5/30
layout: true
comments: true
---

线程除了创建和销毁外，还需要控制其暂停、继续运行等状态。

<!--more-->

# 线程池

线程池就相当于提前创建好的多个工作线程，从任务队列上获取任务并执行。这种方式可以避免系统中的线程过多，因为很多任务都是隔较长时间才会执行一次，如果为每个任务都单独分配一个线程则会消耗过多的系统资源。

## 简易的线程池

根据当前硬件核心数确定线程数，当有任务需要处理时，便将任务放入队列，工作线程依次从队列中取出任务执行。

```cpp
class join_threads {
    std::vector<std::thread>& threads;
public:
    explicit join_threads(std::vector<std::thread>& threads_):
        threads(threads_)
    {}
    ~join_threads() {
        for (unsigned long i = 0; i < threads.size(); ++i) {
            if (threads[i].joinable())
                threads[i].join();
        }
    }
};
```

```cpp
class thread_pool {
    std::atomic_bool done;
    // 线程安全队列，包含互斥及同步机制
    threadsafe_queue<std::function<void()> > work_queue;
    // 线程池，使用 vector 来存放     
    std::vector<std::thread> threads;             
    join_threads joiner; 
               
    void worker_thread() {
        while (!done) {
            std::function<void()> task;
            // 从队列中取出一个任务并执行
            if (work_queue.try_pop(task)) {
                task();    
            } else {
				// 如果队列中没有任务了，便主动让出 CPU
                std::this_thread::yield();    
            }
        }
    }
public:
    thread_pool():
        done(false),joiner(threads) {
        // 创建与硬件核心数相同的工作线程池
        unsigned const thread_count = std::thread::hardware_concurrency(); 
        try {
            for (unsigned i = 0; i< thread_count; ++i) {
            // 创建后，这些线程就在运行了
                threads.push_back(
                    std::thread(&thread_pool::worker_thread, this));   
            }
        } catch(...) {
            done = true;    
            throw;
        }
    }
    // 析构时，done 标志为 true，所有的工作线程便退出了
    ~thread_pool() {
        done = true;   
    }
    // 加入一个任务到队列
    template<typename FunctionType>
    void submit(FunctionType f) {
        work_queue.push(std::function<void()>(f));    
    }
};
```

当该线程池对象被销毁时，`joiner`在析构中会等待所有的线程完成并回收它们的资源。

## 等待任务处理的结果

简易方式的线程池适合处理无返回的简单任务，但如果需要获取到任务处理后的结果，则还需要调整。

最符合直觉的便是使用`std::packaged_task`将要执行函数以及`future`绑定，用户通过获取到的`future`来获取执行的结果。

但由于`std::packaged_task`是不能拷贝，只能移动的，所以需要构建一个支持移动语义的可执行类：
```cpp
class function_wrapper {
    struct impl_base {
        virtual void call() = 0;
        virtual ~impl_base() {}
    };
    std::unique_ptr<impl_base> impl;
    template<typename F>
    struct impl_type: impl_base {
        F f;
        impl_type(F&& f_): f(std::move(f_)) {}
        // 虽然 call 的形式固定了，但是 f 的形式却没有固定
        void call() { f(); }
    };
public:
    template<typename F>
    function_wrapper(F&& f):
        impl(new impl_type<F>(std::move(f)))
    {}
    void operator()() { impl->call(); }
    function_wrapper() = default;
    function_wrapper(function_wrapper&& other):
        impl(std::move(other.impl))
    {}    
    function_wrapper& operator = (function_wrapper&& other) {
        impl = std::move(other.impl);
        return *this;
    }
    // 禁用拷贝构造和拷贝赋值
    function_wrapper(const function_wrapper&) = delete;
    function_wrapper(function_wrapper&) = delete;
    function_wrapper& operator=(const function_wrapper&) = delete;
};
```

然后优化`submit`函数，可以获取到`future`：
```cpp
class thread_pool {
    std::atomic_bool done;
    thread_safe_queue<function_wrapper> work_queue; 
    // 线程池，使用 vector 来存放     
    std::vector<std::thread> threads;             
    join_threads joiner;
       
    void worker_thread() {
        while(!done) {
            function_wrapper task;                    
            if (work_queue.try_pop(task)) {
                task();
            } else {
                std::this_thread::yield();
            }
        }
    }
public:
    thread_pool():
        done(false),joiner(threads) {
        // 创建与硬件核心数相同的工作线程池
        unsigned const thread_count = std::thread::hardware_concurrency(); 
        try {
            for (unsigned i = 0; i< thread_count; ++i) {
            // 创建后，这些线程就在运行了
                threads.push_back(
                    std::thread(&thread_pool::worker_thread, this));   
            }
        } catch(...) {
            done = true;    
            throw;
        }
    }
    // 析构时，done 标志为 true，所有的工作线程便退出了
    ~thread_pool() {
        done = true;   
    }
    template<typename FunctionType>
    std::future<typename std::result_of<FunctionType()>::type>   
        submit(FunctionType f) {
        // std::result_of 用于获取执行任务的返回类型
        typedef typename std::result_of<FunctionType()>::type
            result_type;
        //  使用 package_task 将任务与 future 联系起来                                 
        std::packaged_task<result_type()> task(std::move(f));    
        std::future<result_type> res(task.get_future());     
        work_queue.push(std::move(task));
        
        // 返回 future 以让用户可以获取到结果    
        return res;   
    }
};
```

有了这种线程池，来处理并行计算就更加简单了：
```cpp
template<typename Iterator,typename T>
T parallel_accumulate(Iterator first,Iterator last,T init) {
    unsigned long const length = std::distance(first,last);
    if(!length)
        return init;
    unsigned long const block_size = 25;
    unsigned long const num_blocks = (length + block_size - 1) / block_size;   
    std::vector<std::future<T> > futures(num_blocks - 1);
    thread_pool pool;
    Iterator block_start = first;
    for (unsigned long i = 0;i < (num_blocks - 1); ++i) {
        Iterator block_end = block_start;
        std::advance(block_end, block_size);
        // 将一段要运算的输入放入到工作队列，并返回 future
        futures[i] = pool.submit([=]{
            accumulate_block<Iterator,T>()(block_start,block_end);
        });   
        block_start = block_end;
    }
    T last_result = accumulate_block<Iterator,T>()(block_start,last);
    T result = init;
    // 依次与运算的结果累加
    for (unsigned long i = 0;i < (num_blocks - 1); ++i) {
        result += futures[i].get();
    }
    result += last_result;
    return result;
}
```
这种线程池适合用于主线程在等待工作线程的结果。

# 线程控制

下面是一个简易的控制线程暂停、继续、停止的示例：
```cpp
#include <atomic>
#include <complex>
#include <utility>


class ControlThread {
public:
    ControlThread() {

    }

    ~ControlThread() {

    }

    ControlThread(const ControlThread& rhs) {

    }

    ControlThread& operator = (const ControlThread& rhs) {
        return *this;
    }

    void Start(void) {
        if (!running_.load()) {
            running_.store(true);
            std::thread t(&ControlThread::ExecThread, this);

            t.detach();
        }
    }

    void Pause(void) {
        pause_.store(true);
    }

    void Continue(void) {
        pause_.store(false);
    }
    
    void Stop(void) {
        running_.store(false);
    }

    void ExecThread(void) {
        while (running_.load()) {
            if (pause_.load()) {
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
                continue;
            }

            // do something
        }
    }    

private:
    std::atomic_bool running_;
    std::atomic_bool pause_;
};
```

需要考虑的是：如果在执行线程中有阻塞的操作，该如何控制该线程？

一般的思路就是，创造条件来主动的唤醒该线程继续执行到控制点。


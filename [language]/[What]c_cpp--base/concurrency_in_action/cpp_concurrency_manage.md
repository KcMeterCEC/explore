---
title: C++ concurrency：线程管理
tags: 
- cpp
categories:
- cpp
- concurrency
date: 2022/5/16
updated: 2022/5/16
layout: true
comments: true
---

理解 c++ 对线程的管理。

<!--more-->

# 基本的线程管理

## 启动线程

在 c++ 中，线程也是一个对象，该对象与对应的执行函数、对象相关联而执行对应的操作。

当创建该对象后，与其相关联的可执行对象就会被并发执行。

> 这就和使用 pthread_create 一样，创建一个 pthread 与之关联的函数便会并发执行。

### 与普通函数关联

最简单的创建线程的方式便是将一个普通函数与线程对象关联，线程启动后便会执行该函数。

```cpp
#include <iostream>
//多线程管理的头文件
#include <thread>

void hello(void) {
    std::cout << "Hello world!\n";
}

int main(void) {

    std::thread t1(hello);

    //等待线程 t1 运行完毕
    t1.join();

    return 0;
}
```

### 与可调用类关联

类中使用运算符重载 () 时，该类的实例也可以被调用：

```cpp
#include <iostream>
//多线程管理的头文件
#include <thread>

class BackGroundTask {
  public:
    void operator()() const {
        std::cout << "Hello world!\n";
    }
};

int main(void) {

    /**
      @brief : 方法1，创建实例，将实例传给对象
      */
//    BackGroundTask bk;

//    std::thread t1(bk);
    /**
      @brief : 方法2，创建匿名实例，将实例传给对象
      @note: 注意这里需要用括号包含 BackGroundTask() 包含，以表示要创建对象
      */
//    std::thread t1((BackGroundTask()));
    /**
      @brief : 方法3，使用列表初始化创建匿名实例，将实例传给对象
      */
    std::thread t1{BackGroundTask()};

    //等待线程 t1 运行完毕
    t1.join();

    return 0;
}
```

特别要注意括号初始化，如果是以`std::thread t1(BackGroundTask());`形式，则是代表声明了一个函数。其参数是函数指针，返回类型是`std::thread`。关于初始化的坑，在[这篇文章](http://kcmetercec.top/2022/04/12/effective_cpp_obj_initialize/)有详细说明。

### 与 Lambda 表达式关联

```cpp
#include <iostream>
//多线程管理的头文件
#include <thread>

int main(void) {

    auto task = []() {
        std::cout << "Hello world!\n";
    };

    std::thread t1(task);

    //等待线程 t1 运行完毕
    t1.join();

    return 0;
}
```

### 与类内的静态函数关联

```cpp
#include <iostream>
//多线程管理的头文件
#include <thread>

class TaskObj {
public:
    TaskObj(int i):i_(i) {

    }
    static void Task(TaskObj *obj);
private:
    int i_ = 0;
};

void TaskObj::Task(TaskObj *obj) {
    std::cout << "The value of obj is " << obj->i_ << "\n";
}

int main(void) {

    TaskObj obj(10);

    std::thread t1(TaskObj::Task, &obj);

    //等待线程 t1 运行完毕
    t1.join();

    return 0;
}
```

### 与类普通成员函数关联

```cpp
#include <iostream>
#include <thread>
#include <string>
#include <functional>

class Obj {
public:
    Obj(int val):val_(val) {

    }
    void Exec(void) {
        std::cout << "Value is " << val_ << "\n";
    }
private:
    int val_{0};
};

int main(void) {

    Obj obj(89);

    std::thread t1(&Obj::Exec, &obj);

    t1.join();

    return 0;
}
```

这样实际上是将对象`obj`与其成员函数进行了绑定，实际上是以线程的形式调用了`obj.Exec()`。

## 等待线程的完成

必须要为线程指定是使用`join()`（等待线程完成）还是`detach()`（分离方式运行，当前线程继续执行后面的任务）方式，否则线程对象退出后会调用`std::terminate()`，而使得整个进程退出。
> 使用`detach()`以后，即使`std::thread`被析构，其关联的线程仍然会处于执行状态。
> 当该线程退出后，会自动释放其线程资源。

> `std::terminate()`是一个好的约束方式，以保证线程资源能够被完整的释放掉，若代码没有使用`join()`或`detach()`，则会抛出该异常来提醒。

有的时候，并不能明确一个线程是否可以被`join()`，这个时候可以使用`joinable()`方法先确定一下。

## 在异常的环境下等待

当以分离方式运行线程时，在创建线程后便可以调用`detach()`，这不会有什么问题。

但如果要等待线程完成时，需要注意在调用`join()`之前，抛出了异常的情况。

也就是说，不能因为抛出了异常，而忽略了使用`join()`。

### 使用`try...catch()`

```cpp
struct func;         
void f() {
    int some_local_state = 0;
    func my_func(some_local_state);
    std::thread t(my_func);
    try {
        do_something_in_current_thread();
    } catch(...) {
        t.join();
        throw;
    }
    t.join();
}
```

如上所示，使用`try...catch()`以保证是否发生异常，都可以`join`到线程。

但是这个方式太繁琐，一不小心就会出错。

### 使用 RAII 编码方式

使用 RAII 编码方式，可以说时借助了编译器来保证能正常的调用`join()`。

```cpp
#include <iostream>
//多线程管理的头文件
#include <thread>

class TaskGuard {
public:
    TaskGuard(std::thread &t):t_(t) {

    }
    ~TaskGuard() {
        //保证一个线程是可以 join 的，并且目前没有其它代码使用该 join
        if(t_.joinable()) {
            t_.join();
            std::cout << "Waiting for thread completely\n";
        }
    }

    //对象只能与一个线程对象绑定，不能被拷贝构造和拷贝赋值
    TaskGuard(const TaskGuard& obj) = delete;
    TaskGuard& operator=(const TaskGuard &obj) = delete;
private:
    std::thread &t_;
};

void Task(void) {
    std::cout << "Hello world!\n";
}


int main(void) {

    std::thread t1(Task);

    TaskGuard guard(t1);
// 即使下面这个函数抛出了异常，也不用担心 join 不到 t1
//    dosomethingelse();

    return 0;
}
```

## 在后台运行线程

当对线程对象使用`detach()`后，这个线程就无法被`join()`了，它以后台的方式运行，其资源也由 c++ 运行时库进行释放。

在调用`detach()`之前，如果不确定是否已经被 detach，或被其它代码 join。那么先使用`joinable()`是个好习惯，当`joinable()`返回`true`则代表当前线程对象并没有被 detach，并且也没有其它代码使用 join，那么就可以安全的调用`detach()`了。

# 给线程传递参数

参数的传递是直接在线程对象的构造函数中依次传入参数即可，比如`std::thread t1(TaskObj::Task, &obj);`。

但是需要特别注意的是：**`std::thread`会根据传入的参数进行一次拷贝，然后在线程函数执行时，默认会将此参数转换为右值引用类型传递给函数**。

> 比如传入的是一段字符串 "Hello"，那么`std::thread`就会以`const char*`形式在内部保存其地址，然后在对应的线程运行时，根据线程所需求的参数类型进行转换。

> 传递右值引用是为了：
> 1. 充分利用移动语义以提高参数传递的效率。
> 2. 有些对象仅支持移动操作而不支持拷贝操作（比如`std::unique_ptr`）

比如下面这段代码：

```cpp
#include <iostream>
#include <thread>
#include <chrono>
#include <string>

class Hello {
public:
    Hello() {
        std::cout << "default constructor!\n";
    }
    Hello(const Hello& rhs) {
        std::cout << "copy constructor!\n";
    }
    Hello(Hello&& rhs) {
        std::cout << "move constructor!\n";
    }
    void Put(void) const{
        std::cout << "Hello world!\n";
    }
};

void PrintStr(const Hello &obj) {
    obj.Put();
}

int main(void) {

    Hello obj;
    std::thread t1(PrintStr, obj);
    t1.detach();

    using namespace std::chrono_literals;
    std::this_thread::sleep_for(2000ms);

    return 0;
}
```

其输出为：
```bash
default constructor!
copy constructor!
move constructor!
Hello world!
```
1. 实例化对象，会调用默认构造函数
2. 将 obj 传递给 `std::thread`，`std::thread`会将对象拷贝到内部私有成员中，所以会调用拷贝构造函数
3. 当线程运气起来时，`std::thread`会将私有成员以右值的方式传递给线程，而该类具有移动构造函数，所以就可以调用其移动构造函数来提高效率。

## 注意栈上的参数

比如下面这个例子：

```cpp
#include <iostream>
#include <thread>
#include <chrono>
#include <string>

void PrintStr(const std::string &str) {
    std::cout << "The str is : " << str << "\n";
}

void Oops(void) {
    char str[100] = "Hello world!";

    std::thread t1(PrintStr, str);

    t1.detach();
}


int main(void) {

    Oops();

    using namespace std::chrono_literals;
    std::this_thread::sleep_for(2000ms);

    return 0;
}
```

运行时的输出内容是无法预知的，因为给线程对象`t1`传入的参数实际上是`char *`类型，**而此时仅仅是拷贝了这个地址而已**。

在线程函数启动时，`str`的栈内存已经被释放掉了，此时线程函数获取的内存内容便是无法预知的。
> 虽然说这个时候也会给其转递`std::string`临时对象，但对象的内容就是非预期的。

解决方法是：将`std::sting`为参数传递给`t1`，这样`t1`就拷贝了`std::string`，在运行时将`std::string`传递给`PrintStr`函数：

```cpp
#include <iostream>
#include <thread>
#include <chrono>
#include <string>

void PrintStr(const std::string &str) {
    std::cout << "The str is : " << str << "\n";
}

void Oops(void) {
    char str[100] = "Hello world!";

    // 创建一个 std::string 类型的临时对象，str 作为构造参数参数 
    std::thread t1(PrintStr, std::string(str));

    t1.detach();
}


int main(void) {

    Oops();

    using namespace std::chrono_literals;
    std::this_thread::sleep_for(2000ms);

    return 0;
}
```

## 注意类型传递

前面讲过，`std::thread`传递给线程函数的是右值引用，这需要注意：

```cpp
#include <iostream>
#include <thread>
#include <string>
#include <functional>

void PrintStr(int& i) {
    std::cout << "The value is : " << i << "\n";
}

int main(void) {

    int val = 10;

    std::thread t1(PrintStr, val);

    t1.join();

    return 0;
}
```

`PrintStr`接受的参数是`non const int&`，而无法接受右值引用，此时便会编译出错。
> `std::thread`会先拷贝 val 到内部，然后再传递右值引用到线程

解决方法是：显示的使用`std::ref`以让`std::thread`传递引用：

```cpp
#include <iostream>
#include <thread>
#include <string>
#include <functional>

void PrintStr(int& i) {
    std::cout << "The value is : " << i << "\n";
}

int main(void) {

    int val = 10;

    std::thread t1(PrintStr, std::ref(val));

    t1.join();

    return 0;
}
```

这相当于显示告诉了`std::thread`需要获取的是引用，而不是对象的拷贝。

## 当形参是只移动对象时

当线程可执行函数的形参是只能移动不能拷贝时（比如`std::unique_ptr`），那就需要显示的使用移动语义：

```cpp
#include <iostream>
#include <thread>
#include <string>
#include <functional>
#include <memory>

static void Thread(std::unique_ptr<int> par) {
    std::cout << "The value of par is " << *par << "\n";
}

int main(void) {

    std::unique_ptr<int> val = std::make_unique<int>(10);

    std::thread t1(Thread, std::move(val));

    t1.join();

    return 0;
}
```

由于`std::unique_ptr`限制了同时只能有一个能关联资源，所以它是不可被复制的。

这个时候就需要显示的使用移动语义，也就是说将当前实参`std::unique_ptr`移动到内部私有的一个`std::unique_ptr`。

在线程函数执行时，私有的`std::unique_ptr`又移动给函数的形参。

> 当对象是临时对象时，移动的操作不需要显示的指明（比如函数返回一个`std::unique_ptr`，则不需要显示使用`std::move`）。

# 传递线程的所有者

## 移动语义

`std::thread`也是只能移动而不能拷贝的，也就意味着一个线程函数只能关联一个线程对象，这在逻辑上也是说得通的。不然多个线程对象关联同一个线程函数，那么就会在控制线程上乱套。

```cpp
#include <iostream>
#include <thread>
#include <string>
#include <functional>
#include <memory>

static void Thread(int par) {
    std::cout << "The value of par is " << par << "\n";
}

int main(void) {
    std::thread t1(Thread, 1);
    //由于 t1 不是一个匿名的临时对象，所以需要显示的使用 std::move
    //t1 目前没有关联任何线程函数
    std::thread t2 = std::move(t1);
    //这里使用了 std::thread 创建了匿名临时对象，可以不用显示使用 std::move 就可以传递给 t3
    std::thread t3 = std::thread(Thread, 3);

    //由于 t2 也关联了线程函数，t3 转移给 t2 时，t2 关联的线程函数就会调用 std::terminal()
    //所以在这之前必须等待 t2 关联的函数执行完毕(join)，或将其分离(detach)
    t2.join();
    t2 = std::move(t3);

    t2.join();

    return 0;
}
```

当然也可以在函数返回或形参中使用`std::thread`，并且由于返回的是匿名临时对象，可以不用显示使用`std::move`：

```cpp
std::thread f() {
    void some_function();
    return std::thread(some_function);
}
std::thread g() {
    void some_other_function(int);
    std::thread t(some_other_function,42);
    // 返回值优化，编译器会使用移动版本
    return t;
}
void f(std::thread t);
void g() {
    void some_function();
    f(std::thread(some_function));
    std::thread t(some_function);
    f(std::move(t));
}
```

## 改进`TaskGuard`

前面使用`TaskGuard`以保证函数无论以何种方式退出，线程资源可以被正常释放。但是由于`TaskGuard`中使用的是引用，那么就无法避免被移动的`std::thread`实例也会控制线程，这引入了不安全因素。

由于`std::thread`只能被移动，所以我们可以直接使用移动的方式获取实例，以保证只有一个实例可以操作线程。

```cpp
#include <iostream>
//多线程管理的头文件
#include <thread>
#include <stdexcept>

class TaskGuard {
public:
    TaskGuard(std::thread t):t_(std::move(t)) {
        //由于可以保证当前只有 t_ 与线程关联，所以可以来判定是否有线程
        if(!t_.joinable())
            throw std::logic_error("No thread");
    }
    ~TaskGuard() {
        t_.join();
    }

    //对象只能与一个线程对象绑定，不能被拷贝构造和拷贝赋值
    TaskGuard(const TaskGuard& obj) = delete;
    TaskGuard& operator=(const TaskGuard &obj) = delete;
private:
    std::thread t_;
};

void Task(void) {
    std::cout << "Hello world!\n";
}


int main(void) {

    std::thread t1(Task);

    TaskGuard guard(std::move(t1));
// 即使下面这个函数抛出了异常，也不用担心 join 不到 t1
//    dosomethingelse();

    return 0;
}
```

## 线程对象与容器

既然线程对象是只可移动的，那么就可以批量创建线程，而后进行批量操作。

```cpp
#include <iostream>
#include <thread>
#include <string>
#include <functional>
#include <memory>
#include <vector>

static void Thread(int par) {
    std::cout << "The value of par is " << par << "\n";
}

int main(void) {
    std::vector<std::thread> vt;
    for(int i = 0; i < 20; ++i) {
        vt.emplace_back(Thread, i);
    }
    for(auto& v : vt) {
        v.join();
    }

    return 0;
}
```

当需要短暂的对一个复杂的数据结构进行并发操作时，可以使用这种简易的方式。

当所有线程都完成后，意味着这个并发操作就完成了。

#  选择运行时线程的个数

c++ 提供了函数`std::thread::hardware_concurrency()`来返回硬件所支持的并行线程个数，这有助于我们作为参考来创建线程的个数。

比如下面的并行求和：
```cpp
// 编写一个类以封装 std::accumulate
template<typename Iterator,typename T>
struct accumulate_block {
    void operator()(Iterator first,Iterator last,T& result) {
        result=std::accumulate(first,last,result);
    }
};
template<typename Iterator,typename T>
T parallel_accumulate(Iterator first,Iterator last,T init) {
	// 计算需要处理多少个元素
    unsigned long const length = std::distance(first, last);
    // 如果没有元素要处理，那就直接返回初值
    if(!length)                                            
        return init;
    // 每个线程至少处理 25 个元素
    unsigned long const min_per_thread = 25;
    // 计算需要的最大线程数，确保其最小值为 1
    unsigned long const max_threads=
        (length + min_per_thread-1) / min_per_thread;
    // 获取当前 CPU 可以硬件并发核心    
    unsigned long const hardware_threads=
        std::thread::hardware_concurrency();
    // 取最小线程数，最为最终要运行的线程数
    unsigned long const num_threads=            
        std::min(hardware_threads !=0 ? hardware_threads : 2 , max_threads);
    // 再来计算每个线程需要处理的元素个数
    unsigned long const block_size= length / num_threads;  
    // 创建临时缓存存放每个线程的处理结果    
    std::vector<T> results(num_threads);
    std::vector<std::thread>  threads(num_threads-1);       
    Iterator block_start = first;
    // 除了本线程以外，还要创建 num_threads - 1 个线程来处理数据
    for(unsigned long i = 0;i < (num_threads - 1); ++i) {
        Iterator block_end = block_start;
        std::advance(block_end , block_size);                 
        threads[i] = std::thread(                             
            accumulate_block<Iterator, T>(),
            // 这里以引用的形式传入 results[i]，这样才能保存结果
            block_start, block_end, std::ref(results[i]));
        block_start = block_end;                              
    }
    // 本线程处理最后剩下的数据
    accumulate_block<Iterator, T>()(
        block_start, last, results[num_threads - 1]);    
    // 等待其他的线程完成计算
    for(auto& entry: threads)
           entry.join();
    // 将临时结果再进行一次求和，就可以得到最终的结果了                             
    return std::accumulate(results.begin(), results.end(), init);   
}
```

# 识别线程

## 获取线程 id

获取线程 id 有两种方法：

1. 线程对象使用`get_id()`成员函数，返回关联线程的 id 或是`0`以代表没有关联线程。
2. 在线程函数中使用`std::this_thread::get_id()`来获取当前线程的 id

```cpp
#include <iostream>
#include <thread>
#include <string>
#include <functional>
#include <memory>
#include <vector>

static void Thread(int par) {
    std::cout << "The value of par is " << par << "\n";
    std::cout << "The id of mine is " << std::this_thread::get_id() << "\n\n";
}

int main(void) {

    auto number = std::thread::hardware_concurrency();

    std::cout << "hardware concurrency " << number << "\n";

    std::vector<std::thread> vt;
    for (int i = 0; i < number - 1; ++i) {
        vt.emplace_back(Thread, i);
    }
    for (auto& v : vt) {
        std::cout << "join thread: " << v.get_id() << "\n";
        v.join();
    }

    return 0;
}
```

## 使用线程 id

### 线程之间的比较

有的时候需要判定两个函数是否在同一个线程中执行，可以判断 id 是否相等来实现。

当二者相等时，则代表二者处于同一个线程（或都是无效线程），否则不是同一个线程。

### 线程 id 与查表

线程 id 可以与哈希表这种数据结构绑定，将其作为一个 Key，以实现对应数据与线程的一一对应关系。

### 线程 id 与功能对应

通过与线程 id 进行比较，以执行对应不同的功能：

```cpp
std::thread::id master_thread;
void some_core_part_of_algorithm() {
    if (std::this_thread::get_id() == master_thread) {
        do_master_thread_work();
    }
    do_common_work();
}
```
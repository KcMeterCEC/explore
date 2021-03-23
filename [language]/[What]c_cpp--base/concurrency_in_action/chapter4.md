---
title: '[What] C++ Concurrency in Action 2nd ：线程间同步操作'
tags: 
- c++
date:  2021/3/8
categories: 
- language
- c/c++
- Concurrency
layout: true
---
这一章主要熟悉用 c++ 来编写可以跨平台的数据同步操作。
<!--more-->

# 等待事件或条件

## 使用条件变量

之前在看[ostep](http://kcmetercec.top/2020/05/26/book_ostep_concurrency_condition_variables/)的时候熟悉过条件变量，但只是 Linux 平台下的。现在看看 c++ 标准库是如何使用的。

c++ 标准库在` <condition_variable>`头文件中提供了` std::condition_variable`和`std::condition_variable_any`两种条件变量。

其中` std::condition_variable`只能与`std::mutex`结合使用，而`std::condition_variable_any`可以与任何具有互斥作用的对象结合使用。但是后者的效率比不上前者，所以大部分时候还是使用的` std::condition_variable`。

最基本的使用如下：

```cpp
std::mutex mut;
std::condition_variable data_cond;
//用于存放数据的队列
std::queue<data_chunk> data_queue;      

//生产者
void data_preparation_thread()
{
    while(more_data_to_prepare())
    {
        const data_chunk data = prepare_data();
        {
			//将数据写入队列
            std::lock_guard<std::mutex> lk(mut);
            data_queue.push(data);
            //在退出这个局部区以后，互斥量就释放掉了              
        }
        //唤醒一个消费者
        //在互斥量释放之后再来唤醒消费者
        //如果在互斥量释放前唤醒消费者，那么此时很可能互斥量还没有释放完毕，那么消费者又需要进入一次等待，执行效率没有那么高
        data_cond.notify_one();
    }
}
void data_processing_thread()
{
    while(true)
    {
        std::unique_lock<std::mutex> lk(mut);
        //等待数据，当 lambda 中的返回为真时，则会继续处理后面的数据，否则会释放互斥量然后继续睡眠    
        data_cond.wait(
            lk,[]{return !data_queue.empty();});
        //拷贝一个数据的副本，这样可以让临界区的执行时间尽量的短     
        data_chunk data=data_queue.front();
        data_queue.pop();
        //操作完数据需要释放互斥量
        lk.unlock();
        //到这里才是处理刚刚收到的数据          
        process(data);
        if(is_last_chunk(data))
            break;
    }
}
```

在消费者线程中，使用的是`std::unique_lock`。这是因为当条件变量不满足的时候，需要主动释放互斥量然后进入睡眠。而`std::lock_guard`并没有提供这些灵活操作的接口（并且在获取数据的副本后，也会主动释放互斥量以提高系统的并发度）。`wait`方法的执行逻辑就如同下面这段代码一样：

```cpp
template<typename Predicate>
void minimal_wait(std::unique_lock<std::mutex>& lk,Predicate pred){
    while(!pred()){
        lk.unlock();
        lk.lock();
    }
}
```

## 创建一个多线程安全的队列

我们可以基于前面的代码，将`std::queue`封装为一个多线程安全的队列：

```cpp
#include <queue>
#include <memory>
#include <mutex>
#include <condition_variable>
template<typename T>
class threadsafe_queue
{
private:
	//在多线程环境下，互斥量是易变的，需要加上 mutable 修饰
    mutable std::mutex mut;    
    std::queue<T> data_queue;
    std::condition_variable data_cond;
public:
    threadsafe_queue()
    {}
    threadsafe_queue(threadsafe_queue const& other)
    {
		//使用拷贝构造函数也需要做到互斥
        std::lock_guard<std::mutex> lk(other.mut);
        data_queue=other.data_queue;
    }
    void push(T new_value)
    {
        std::lock_guard<std::mutex> lk(mut);
        data_queue.push(new_value);
        data_cond.notify_one();
    }
    void wait_and_pop(T& value)
    {
        std::unique_lock<std::mutex> lk(mut);
        data_cond.wait(lk,[this]{return !data_queue.empty();});
        value=data_queue.front();
        data_queue.pop();
    }
    std::shared_ptr<T> wait_and_pop()
    {
        std::unique_lock<std::mutex> lk(mut);
        data_cond.wait(lk,[this]{return !data_queue.empty();});
        std::shared_ptr<T> res(std::make_shared<T>(data_queue.front()));
        data_queue.pop();
        return res;
    }
    bool try_pop(T& value)
    {
		//既然是试探性的获取数据，就不需要用到条件变量了
        std::lock_guard<std::mutex> lk(mut);
        if(data_queue.empty())
            return false;
        value=data_queue.front();
        data_queue.pop();
        return true;
    }
    std::shared_ptr<T> try_pop()
    {
        std::lock_guard<std::mutex> lk(mut);
        if(data_queue.empty())
            return std::shared_ptr<T>();
        std::shared_ptr<T> res(std::make_shared<T>(data_queue.front()));
        data_queue.pop();
        return res;
    }
    bool empty() const
    {
        std::lock_guard<std::mutex> lk(mut);
        return data_queue.empty();
    }
};
```

在使用的时候就更加简洁了：

```cpp
threadsafe_queue<data_chunk> data_queue;    
void data_preparation_thread()
{
    while(more_data_to_prepare())
    {
        const data_chunk data=prepare_data();
        data_queue.push(data);        
    }
}
void data_processing_thread()
{
    while(true)
    {
        data_chunk data;
        data_queue.wait_and_pop(data);    
        process(data);
        if(is_last_chunk(data))
            break;
    }
}
```

# 使用`future`等待一次性事件

future 用于标识等待一个一次性事件的发生，一旦该事件发生了，其`ready`标记为真且无法被清除。

在` <future>`头文件中提供了`std::future<>`和`std::shared_future<>`分别对应于独立和共享，就如同`std::unique_ptr`和`std::shared_ptr`一样。一个事件，只能有一个`std::future<>`与之关联。而多个`std::shared_future<>`可以关联同一个事件。

多个线程如果要并发的访问`std::future<>`则需要使用互斥量这些来保证互斥，而`std::shared_future<>`则没有这个限制。

## 获取线程的返回参数

假设需要一个线程来进行一个比较耗时的计算，如果使用`std::thread`来关联一个函数，那么获取其计算的结果还比较麻烦。这种情况下使用`std::async`与执行函数相关联，它会返回一个`std::future`以让使用者比较优雅的就可以获取到执行的返回值。

一个简单而优雅的示例如下：

```cpp
#include <iostream>
#include <future>

static int find_the_answer_to_ltuae(){
	return 1 + 1;
}

int main(){
	std::future<int> the_answer = std::async(find_the_answer_to_ltuae);

	//如果在使用 get() 时线程还没有运行完成，那么在此处则会阻塞等待线程运行完毕
	std::cout << "The answer is " << the_answer.get() << std::endl;

	return 0;
}
```

`std::async`的也可以给执行函数传递参数，和`std::thread`的使用方式是一样的：

```cpp
#include <string>
#include <future>
struct X
{
    void foo(int,std::string const&);
    std::string bar(std::string const&);
};
X x;
//这里拷贝的是对象 x 的地址，所以其调用方式是： (&x)->foo(42, "hello")
auto f1=std::async(&X::foo,&x,42,"hello");
//这里拷贝的是对象 x，所以其调用方式是：x.bar("goodbye")      
auto f2=std::async(&X::bar,x,"goodbye");    
struct Y
{
    double operator()(double);
};
Y y;
//这里通过类 Y 创建了一个临时对象，然后在内部以右值引用的方式传递给其 operator()
auto f3=std::async(Y(),3.141);
//这里拷贝的是引用，所以其调用方式是y(2.718)       
auto f4=std::async(std::ref(y),2.718);     
X baz(X&);
//由于 baz 这个函数需求的是左值引用，所以传递参数必须要使用 std::ref 
std::async(baz,std::ref(x));     
class move_only
{
public:
    move_only();
    move_only(move_only&&)
    move_only(move_only const&) = delete;
    move_only& operator=(move_only&&);
    move_only& operator=(move_only const&) = delete;
    void operator()();
};
//创建临时对象，内部以右值引用的方式移动给 operator()
auto f5=std::async(move_only());
```

可以对`std::async`配置策略，以显示的指定其执行策略是同步还是异步：

```cpp
//以异步的方式执行，也就是会在另外一个线程中执行
auto f6=std::async(std::launch::async,Y(),1.2);
//推迟执行，在使用 wait() 或 get() 时才执行，相当于同步执行     
auto f7=std::async(std::launch::deferred,baz,std::ref(x));
//下面这两种方式会根据代码的具体实现方式来选择是同步还是异步执行    
auto f8=std::async(                           
   std::launch::deferred | std::launch::async,
   baz,std::ref(x));                          
auto f9=std::async(baz,std::ref(x));

//比如 f7 使用 wait() 的时候， baz(x) 才执行          
f7.wait();
```

## 将 future 与一个任务关联

`std::packaged_task`提供了更为灵活的方式，它可以将一个可执行函数、对象等内部与一个`std::future`绑定在一起，然后这个可执行函数、对象可以被同步或异步的被执行。执行的时候其返回值便会自动存储，而后可以通过关联的`std::future`来获取。

这个与前面单独的使用`std::future`不同，`std::future`是主动控制可执行函数、对象的执行，而`std::package_task`是函数被其它代码执行，而后返回值主动关联到`std::future`:

```cpp
#include <iostream>
#include <cmath>
#include <thread>
#include <future>
#include <functional>
 
// unique function to avoid disambiguating the std::pow overload set
int f(int x, int y) { return std::pow(x,y); }
 
void task_lambda()
{
    std::packaged_task<int(int,int)> task([](int a, int b) {
        return std::pow(a, b); 
    });
    std::future<int> result = task.get_future();
 
    task(2, 9);
 
    std::cout << "task_lambda:\t" << result.get() << '\n';
}
 
void task_bind()
{
    std::packaged_task<int()> task(std::bind(f, 2, 11));
    std::future<int> result = task.get_future();
 
    task();
 
    std::cout << "task_bind:\t" << result.get() << '\n';
}
 
void task_thread()
{
    std::packaged_task<int(int,int)> task(f);
    std::future<int> result = task.get_future();
 
    std::thread task_td(std::move(task), 2, 10);
    task_td.join();
 
    std::cout << "task_thread:\t" << result.get() << '\n';
}
 
int main()
{
    task_lambda();
    task_bind();
    task_thread();
}
```



比如，GUI 有个独立的线程执行刷新任务，其它的任务要刷新线程必须要给这个 GUI 任务发送消息，这些线程或许还需要得到 GUI 线程执行该消息后的返回值。那么使用`std::package_task`就是合理的：

```cpp
#include <deque>
#include <mutex>
#include <future>
#include <thread>
#include <utility>
std::mutex m;
//存放消息的队列，每个元素都是一个 std::packaged_task
std::deque<std::packaged_task<void()> > tasks;
bool gui_shutdown_message_received();
void get_and_process_gui_message();
void gui_thread()                   
{
	//事件循环，获取消息
    while(!gui_shutdown_message_received())   
    {
        get_and_process_gui_message();    
        std::packaged_task<void()> task;
        {
            std::lock_guard<std::mutex> lk(m);
            if(tasks.empty())                 
                continue;
            //从消息队列中取出一个消息
            task=std::move(tasks.front());   
            tasks.pop_front();
        }
        //执行该消息，同时与之关联的 std::future 也 reday 了
        task();    
    }
}
std::thread gui_bg_thread(gui_thread);
template<typename Func>
std::future<void> post_task_for_gui_thread(Func f)
{
	//将一个消息任务与 future 绑定
    std::packaged_task<void()> task(f);       
    std::future<void> res=task.get_future();
    //消息存入消息队列     
    std::lock_guard<std::mutex> lk(m);
    tasks.push_back(std::move(task));
    //返回与该消息绑定的 future，用户可以在需要的时候获取这个消息的执行返回结果     
    return res;                      
}
```

## 使用 std::promises

`std::promises`和`std::packaged_task`很类似，也是可以通过其` get_future()`方法获取一个`std::future`，然后它就可以组合使用。

`std::packaged_task`是用于执行一个函数，其返回值与`std::future`绑定。而`std::promises`是当其使用`set_value()`方法后，与其绑定的`std::future`便会是 ready 状态，如果`std::future`在其 ready 之前使用了 `get()`方法，那么将会阻塞的等待。

所以既可以使用`std::promises`实现线程间同步，也可以实现线程间的同步通信。

```cpp
#include <vector>
#include <thread>
#include <future>
#include <numeric>
#include <iostream>
#include <chrono>
 
void accumulate(std::vector<int>::iterator first,
                std::vector<int>::iterator last,
                std::promise<int> accumulate_promise)
{
    int sum = std::accumulate(first, last, 0);
    accumulate_promise.set_value(sum);  // Notify future
}
 
void do_work(std::promise<void> barrier)
{
    std::this_thread::sleep_for(std::chrono::seconds(3));
    barrier.set_value();
}
 
int main()
{
    // Demonstrate using promise<int> to transmit a result between threads.
    std::vector<int> numbers = { 1, 2, 3, 4, 5, 6 };
    std::promise<int> accumulate_promise;
    std::future<int> accumulate_future = accumulate_promise.get_future();
    std::thread work_thread(accumulate, numbers.begin(), numbers.end(),
                            std::move(accumulate_promise));
 
    // future::get() will wait until the future has a valid result and retrieves it.
    // Calling wait() before get() is not needed
    //accumulate_future.wait();  // wait for result
    std::cout << "result=" << accumulate_future.get() << '\n';
    work_thread.join();  // wait for thread completion
 
    // Demonstrate using promise<void> to signal state between threads.
    std::promise<void> barrier;
    std::future<void> barrier_future = barrier.get_future();
    std::thread new_work_thread(do_work, std::move(barrier));
    std::cout << "wait result\n";
    barrier_future.wait();
    std::cout << "wait result done\n";
    new_work_thread.join();
}
```

## 将异常存入 future

正常情况下，当一个函数抛出异常时，会层层向上传递，如果没有用户代码 catch 它，那么将会由标准库处理并退出用户进程。但是当使用了`std::future`，`std::promises`，`std::packaged_task`时，如果其关联函数抛出了异常，这个异常的值会被存储在 future 中：

```cpp
#include <iostream>
#include <stdexcept>
#include <future>

int func_div(int a, int b){
    std::cout << "a = " << a << " b " << b << "\n";
    if(b == 0){
        throw std::out_of_range("input out of range!\n");
    }

    return a / b;
}

int main(void){

    std::future<int> f = std::async(func_div, 10, 0);

	//如果使用了 while(1) ，那么虽然 func_div 抛出了异常，这个应用代码并不会被杀死
    while(1);
    //当使用 get 时，才会重新抛出异常
    int ret = f.get();
    std::cout << "get result: " << ret << "\n";

    return 0;
}
```

## 多个线程等待同一个事件

当有多个线程在使用同一个`std::future`时，便会造成竞态。这种情况下应该使用`std::shared_future`。

这并不是说多个线程使用同一个`std::shared_future`，而是说每个线程都有一份对`std::shared_future`的拷贝，它们都访问自己的`std::shared_future`：

![](./pic/c4_shared_future.jpg)



`std::shared_future`是通过`std::future`来获取，又由于`std::future`是不能被拷贝的，只能被移动，所以需要使用`std::move`：

```cpp
std::promise<int> p;
std::future<int> f(p.get_future());                      
std::shared_future<int> sf(std::move(f));
```

当然，对于创建的临时对象，也可以更加简单粗暴：

```cpp
std::promise<std::string> p;
std::shared_future<std::string> sf(p.get_future());
```

除此之外，`std::future`也具有一个`share()`方法来创建`std::shared_future`：

```cpp
std::promise< std::map< SomeIndexType, SomeDataType, SomeComparator,
    SomeAllocator>::iterator> p;
//sf 推导为  std::shared_future< std::map< SomeIndexType, SomeDataType, SomeComparator, //SomeAllocator>::iterator>
auto sf=p.get_future().share();
```

# 超时等待

对于时间的设定，可以设置相对时间（比如等待 100 毫秒）和绝对时间（比如等待至 2022年……）。

c++ 标准库提供了这两种时间的设定，对于相对时间，其操作方法以`_for`作为后缀，对于绝对时间，其操作方法以`_until`作为后缀。

> 比如对于 condition_variable 的 wait() 方法就有 wait_for() 和 wait_until() 两种超时等待。

## c++ 的时钟

c++ 标准库提供了头文件` <chrono>`以支持时钟相关的操作：

- `std::chrono::steady_clock`提供了具有固定不可被修改的时钟
- `std::chrono::system_clock`提供了通用时钟操作，可以被设定修改
- `std::chrono::high_resolution_clock`提供了高精度时钟操作

以上 3 个时钟都具有静态函数`now()`以获取一个绝对的时间点`time_point`。

## 周期

### ratio

`ratio`头文件提供了模板类`std::ratio<num, den>`，其值代表 N 内有 D 次数，也就是频率。

比如 1毫秒，就是 1 秒内有 1000 次，那么就表示为：`std::ratio<1,1000>`。

该头文件还提供了很多实现定义的类型，便于用户直接使用：（详见[cppreference](https://en.cppreference.com/w/cpp/numeric/ratio/ratio)）

| 定义  |          等同于           |
| :---: | :-----------------------: |
| nano  | std::ratio<1, 1000000000> |
| micro |  std::ratio<1, 1000000>   |
|  ……   |            ……             |

```cpp
#include <iostream>
#include <ratio>

int main(void){
    std::cout << std::ratio<1, 1000>::num << "\n";
    std::cout << std::ratio<1, 1000>::den << "\n";
    std::cout << std::micro::num << "\n";
    std::cout << std::micro::den << "\n";
	
	return 0;
}
```

输出为：

> 1
> 1000
> 1
> 1000000

### duration

头文件`<chrono>`提供了`std::chrono::duration<Rep,Period>`模板。

它与`std::ratio`联合使用，以表示在多少个周期内有多少个计数值。

第一个参数指定存储周期的类型值，第二个参数指定`std::ratio`。

比如：

- 使用`short`存储一分钟的计数值：`std::chrono::duration<short,std::ratio<60,1>>`
- 使用`double`存储毫秒： `std::chrono::duration<double,std::ratio<1,1000>>`

为了方便，标准库还提供了`std::nanoseconds,  std::microseconds,  std::milliseconds,  std::seconds, std::minutes, std::hours`等这些定义好的周期值。

```cpp
#include <iostream>
#include <ratio>
#include <chrono>

int main(void){
    //得到一个代表两秒的值
    auto t = std::chrono::seconds(2);

    //当前频率是 1 秒钟有 50 次跳动
    std::chrono::duration<int, std::ratio<1, 50>> val(t);

    //那么两秒对应的就是 100 次跳动
    std::cout << "count of val " << val.count() << "\n";

	
	return 0;
}
```

在 c++14 及以后，还提供了`std::chrono_literals`以使用字面值来表示周期：

```cpp
using namespace std::chrono_literals;
auto one_day=24h;
auto half_an_hour=30min;
auto max_time_between_messages=30ms;
```

 这样`15ns` 就等同于 `std::chrono::nanoseconds(15)`:

```cpp
#include <iostream>
#include <ratio>
#include <chrono>

int main(void){
    using namespace std::chrono_literals;
    //得到一个代表两秒的值
    auto t = 2s;

    //当前频率是 60 秒钟有 1 次跳动，也就是一分钟
    std::chrono::duration<double, std::ratio<60, 1>> val(t);

    //那么两秒对应的就是 0.0333 次跳动，也就是 0.0333 分钟
    std::cout << "count of val " << val.count() << "\n";

	
	return 0;
}
```

`std::chrono::duration_cast<>`用于时间之间的转换，这里可能会有精度的损失（比如毫秒转换到秒）：

```cpp
#include <iostream>
#include <ratio>
#include <chrono>

int main(void){
    std::chrono::milliseconds ms(54802);
    //最终转换为 54 秒
    std::chrono::seconds s = std::chrono::duration_cast<std::chrono::seconds>(ms);

    std::cout << "conver " << ms.count() << " ms to " << s.count() << " s\n";

	
	return 0;
}
```

周期之间也可以进行简单的运算，比如 5 秒可以使用：`5*seconds(1)`或`minutes(1) – seconds(55)`，它们都等同于` seconds(5)`。

## 时间点

`std::chrono::time_point<>`用于表示一个绝对的时间点，它有两个参数。第一个参数用于表示这个时间点的参考时钟，第二个参数用于表示周期：

```cpp
#include <iostream>
#include <ctime>
#include <chrono>
#include <ratio>
#include <iomanip>

int main(){
    using namespace std::literals; // enables the usage of 24h, 1ms, 1s instead of
                                   // e.g. std::chrono::hours(24), accordingly

    //以系统时钟作为参考，周期是 100 微秒
    const std::chrono::time_point<std::chrono::system_clock,
            std::chrono::duration<long long, std::ratio<1, 10000000>>> now =
        std::chrono::system_clock::now();

    std::cout << "time since epoch with seconds " <<
                std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count()
              << "\n";

    const std::time_t t_c = std::chrono::system_clock::to_time_t(now - 24h);
    std::cout << "24 hours ago, the time was "
              << std::put_time(std::localtime(&t_c), "%F %T.\n") << std::flush;

    return 0;
}
```

对于使用相同参考时钟的时间点，也可以进行加减运算。比如下面经过时间点求差得出一段代码的运行时间：

```cpp
#include <iostream>
#include <ctime>
#include <chrono>
#include <ratio>
#include <iomanip>

int main(){
    auto start=std::chrono::high_resolution_clock::now();
    for(int i = 0; i < 0xffffff; ++i){

    }
    auto stop=std::chrono::high_resolution_clock::now();
    std::cout<<"for loop took "
             << std::chrono::duration_cast<std::chrono::microseconds> (stop-start).count()
             << " microseconds" <<std::endl;

    return 0;
}
```

## 超时等待相关的函数

以延迟为例可以通过`std::this_thread::sleep_for`使用相对的延迟，和通过`std::this_thread::sleep_until`使用绝对延迟：

```cpp
#include <iostream>
#include <chrono>
#include <ratio>
#include <thread>

int main(){
    auto start=std::chrono::high_resolution_clock::now();
    //使用相对延迟，延迟两秒
    std::this_thread::sleep_for(std::chrono::seconds(2));

    auto stop=std::chrono::high_resolution_clock::now();
    std::cout<<"relative delay took "
             << std::chrono::duration_cast<std::chrono::microseconds> (stop-start).count()
             << " microseconds" <<std::endl;

    start=std::chrono::high_resolution_clock::now();
    //使用绝对延迟，延迟 800 毫秒
    std::this_thread::sleep_until(std::chrono::system_clock::now() + std::chrono::milliseconds(800));

    stop=std::chrono::high_resolution_clock::now();
    std::cout<<"absolute delay took "
             << std::chrono::duration_cast<std::chrono::microseconds> (stop-start).count()
             << " microseconds" <<std::endl;

    return 0;
}
```

除了延迟以外，其它的便是超时等待相关的函数。同样的，使用`xxx_for`便是相对时间，而使用`xxx_until`则是绝对时间。常用的功能函数总结如下：

- `std::this_thread::sleep_for` / `std::this_thread::sleep_until`
- `std::condition_variable::wait_for` / `std::condition_variable::wait_until`
- `std::condition_variable_any::wait_for` / `std::condition_variable_any::wait_until`

- `std::timed_mutex::try_lock_for` / `std::timed_mutex::try_lock_until`
- `std::recursive_timed_mutex::try_lock_for` / `std::recursive_timed_mutex::try_lock_until`
- `std::shared_timed_mutex::try_lock_for` / `std::shared_timed_mutex::try_lock_until`
- `std::shared_timed_mutex::try_lock_shared_for` / `std::shared_timed_mutex::try_lock_shared_until`
- `std::unique_lock<Mutex>::try_lock_for` / `std::unique_lock<Mutex>::try_lock_until`
- `std::shared_lock<Mutex>::try_lock_for` / `std::shared_lock<Mutex>::try_lock_for`
- `std::future<T>::wait_for` / `std::future<T>::wait_until`
- `std::shared_future<T>::wait_for` / `std::shared_future<T>::wait_until`
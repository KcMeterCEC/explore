---
title: '[What] Effective Modern C++ ：lambda 优于 std::bind'
tags: 
- c++
date:  2021/10/6
categories: 
- language
- c/c++
- Effective
layout: true
---

lambad 综合上优于 `std::bind`，最主要的是其优异的可读性。

<!--more-->

比如要编写一个声音报警程序，先声明以下类型：
```cpp
// 时间点
using Time = std::chrono::steady_clock::time_point;
// 报警的类型
enum class Sound { Beep, Siren, Whistle };
// 时间长度
using Duration = std::chrono::steady_clock::duration;

// 设置报警的函数
void setAlarm(Time t, Sound s, Duration d);
```

然后以 lambda 的方式来封装，产生一个 1 小时后响铃 30 秒的可调用对象：

```cpp
// setSoundL ("L" for "lambda") is a function object allowing a
// sound to be specified for a 30-sec alarm to go off an hour
// after it's set
auto setSoundL =                             
  [](Sound s)
  {
    // make std::chrono components available w/o qualification
    using namespace std::chrono;
    setAlarm(steady_clock::now() + hours(1),  // alarm to go off
             s,                               // in an hour for
             seconds(30));                    // 30 seconds
  };
```

基于 c++ 14 的话，还可以再次简化：

```cpp
auto setSoundL =                             
  [](Sound s)
  {
    using namespace std::chrono;
    using namespace std::literals;         // for C++14 suffixes
    setAlarm(steady_clock::now() + 1h,     // C++14, but
             s,                            // same meaning
             30s);                         // as above
  };
```

但使用`std::bind`来实现同样的可调用对象，则要麻烦得多，并且可读性很差：

```cpp
using namespace std::chrono;           // as above
using namespace std::literals;
using namespace std::placeholders;     // needed for use of "_1"
auto setSoundB =                       // "B" for "bind"
  std::bind(setAlarm,
            // 使用下面这种方式，那么获取到得则是绑定时得时间点，而不是调用时的时间点
            // steady_clock::now() + 1h,
            
            // 应该如下，c++ 14 中，std::plus 中的类型可以忽略
            std::bind(std::plus<>(), steady_clock::now(), 1h),
            _1,
            30s);
```


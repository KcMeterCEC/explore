---
title: 认识 fmt
tags: 
- cpp
categories:
- cpp
- professional
date: 2024/10/21
updated: 2024/10/21
layout: true
comments: true
---

虽然 C++20 已经提供了 `std::format` 这种格式化库，但直到 C++23 才支持 `std::print` 这种便利库。

又由于目前 gcc 对 C++23 支持还不完整，尤其是在嵌入式上。所以仍然是需要以 [fmt 库](https://github.com/fmtlib/fmt) 为基本使用工具。

<!--more-->

# 包含 fmt 库

[Get Started](https://fmt.dev/11.0/get-started/)中已经详细的描述了如何包含 fmt 到项目中去，为了增加项目的独立性，个人更倾向于使用`FetchContent`或`Embedded`的方式包含该库。

除了上面说的方法，还有一个简单粗暴的办法：

1. 下载源码，将文件夹`inculde/fmt`和`src`拷贝至项目中

2. 将`fmt/core.h`，`fmt/format.h`，`fmt/forat-inl.h`，`src/format.cc`添加至编译文件中

3. 将`fmt`路径添加到项目包含路径中

```shell
对于 Visual Studio，为了能够顺利编译 fmt 库。

需要在"属性"-> "C/C++" -> "命令行" -> "附加选项" 中添加 `/utf-8` 指定编码方式
```

# 基本语法

`fmt::format`和`fmt::print`语法一致，在字符串中使用花括号`{}`表示格式化输出部分，如果想输出花括号，则使用两个花括号`{{}}`。

替换字段`{}`的语法如下：

```shell
replacement_field ::= "{" [arg_id] [":" (format_spec | chrono_format_spec)] "}"
arg_id            ::= integer | identifier
integer           ::= digit+
digit             ::= "0"..."9"
identifier        ::= id_start id_continue*
id_start          ::= "a"..."z" | "A"..."Z" | "_"
id_continue       ::= id_start | digit
```

## arg_id

`arg_id`指的是要输出部分对应后面输入参数的顺序，默认为`0~9`这样的顺序：

```cpp
fmt::println("{}{}{}\n", "0", "1", "2");
// 等价于
fmt::println("{0}{1}{2}\n", "0", "1", "2");

fmt::format("{0}, {1}, {2}", 'a', 'b', 'c');
// Result: "a, b, c"
fmt::format("{}, {}, {}", 'a', 'b', 'c');
// Result: "a, b, c"
fmt::format("{2}, {1}, {0}", 'a', 'b', 'c');
// Result: "c, b, a"
fmt::format("{0}{1}{0}", "abra", "cad");  // arguments' indices can be repeated
// Result: "abracadabra"
```

如果在`arg_id`后需要增加其他描述，那需要以冒号`:`分隔`arg_id`和`format_spec`。

## format_spec

`format_spec`描述参数的表示方式，包含长度、对其、空白填充、精度、进制等。

```shell
format_spec ::= [[fill]align][sign]["#"]["0"][width]["." precision]["L"][type]
fill        ::= <a character other than '{' or '}'>
align       ::= "<" | ">" | "^"
sign        ::= "+" | "-" | " "
width       ::= integer | "{" [arg_id] "}"
precision   ::= integer | "{" [arg_id] "}"
type        ::= "a" | "A" | "b" | "B" | "c" | "d" | "e" | "E" | "f" | "F" |
                "g" | "G" | "o" | "p" | "s" | "x" | "X" | "?"
```

- `fill`表示填充的字符，除了花括号以外，其他字符都可以使用（需要指定宽度才有意义）

- `align`指定对齐方式（需要指定宽度才有意义）：
  
  - `<`：左对齐，默认值
  
  - `>`：右对齐，对于数值而言，它是默认值
  
  - `^`：居中对齐

```cpp
fmt::format("{:<30}", "left aligned");
// Result: "left aligned                  "
fmt::format("{:>30}", "right aligned");
// Result: "                 right aligned"
fmt::format("{:^30}", "centered");
// Result: "           centered           "
fmt::format("{:*^30}", "centered");  // use '*' as a fill char
// Result: "***********centered***********"

// 宽度也可以设置为参数
fmt::format("{:<{}}", "left aligned", 30);
// Result: "left aligned 
```

- `sign`仅在浮点数或有符号整数有效：
  
  - `+`：在数值为非负时加上`+`号，在数值为负数时加上`-`号
  
  - `-`：只有在数字为负数时，才加上`-`号，它是默认值
  
  - ` `：在数值为非负数时，加上空格，在数值为负数时加上`-`号

- `#`用于对显示格式的切换，仅对整数和浮点数合法：
  
  - 对于`#b or #B`二进制、`#o`8进制、`#x or #X`16进制，会输出对应的前缀

- `width`指定显示的最小位数，如果在`width`前面加`0`，则会在符号和数值之间填充0.
  
  - 当使用对齐方式时，前面加`0`的方式就会被忽略

- `precision`指定小数精度：
  
  - 对于`f or F`显示格式，指定小数点后面的位数
  
  - 对于`g or G`显示格式，指定除小数点外的位数之和

- `type`用于指定具体显示格式：
  
  - 对于字符串有：
    
    - `s`：字符串显示，默认值
    
    - `?`：调试显示，字符串被引号包含，且里面的特殊字符将不会被转义
  
  - 对于字符有：
    
    - `c`：字符显示，默认值
    
    - `?`：调试显示，字符被引号包含，且特殊字符不会被转义
  
  - 对于整数有：
    
    - `b`或`B`：以二进制显示，如果加上`#`则会分别加上`0b`和`0B`前缀
    
    - `c`：以字符显示
    
    - `d`：以十进制显示
    
    - `o`：以八进制显示
    
    - `x`或`X`：以 16 进制显示，如果加上`#`则会分别加上`0x`和`0X`前缀
  
  - 对于浮点数有：
    
    - `a`或`A`：以 16 进制显示浮点数
    
    - `e`或`E`：以科学计数法表示浮点数
    
    - `f`或`F`：以固定精度显示浮点数
    
    - `g`或`G`：对浮点数进行四舍五入
  
  - 对于指针有：`fmt::print("{:p}", fmt::ptr(p));`
    
    - `p`：以 16 进制的方式显示指针，默认值。

```cpp
fmt::format("{:.{}f}", 3.14, 1);
// Result: "3.1"

fmt::format("{:+f}; {:+f}", 3.14, -3.14);  // show it always
// Result: "+3.140000; -3.140000"
fmt::format("{: f}; {: f}", 3.14, -3.14);  // show a space for positive numbers
// Result: " 3.140000; -3.140000"
fmt::format("{:-f}; {:-f}", 3.14, -3.14);  // show only the minus -- same as '{:f}; {:f}'
// Result: "3.140000; -3.140000"

fmt::format("int: {0:d};  hex: {0:x};  oct: {0:o}; bin: {0:b}", 42);
// Result: "int: 42;  hex: 2a;  oct: 52; bin: 101010"
// with 0x or 0 or 0b as prefix:
fmt::format("int: {0:d};  hex: {0:#x};  oct: {0:#o};  bin: {0:#b}", 42);
// Result: "int: 42;  hex: 0x2a;  oct: 052;  bin: 0b101010"

fmt::format("{:#04x}", 0);
// Result: "0x00"
```

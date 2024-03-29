---
title: '[What]链接、装载与库 --> Linux共享库组织'
tags: 
- CS
date:  2018/11/25
categories: 
- book
- 程序员的自我休养
layout: true
---

为了较好的维护共享库，需要将它们按照一定的规则组织起来。

<!--more-->

# 共享库的版本
## 兼容性问题
c 语言的共享库的更新可以被分为兼容更新和不兼容更新，以下这些改变都会导致更新不兼容:
1. 导出函数的行为发生改变：虽然参数接口及返回没有改变，但相对旧版本行为变了很多
2. 导出函数被删除：这对于程序来讲就少了一些符号
3. 导出的数据结构发生变化：这导致对应内存操作不一致
4. 导出的函数的接口或返回值发生变化：这也相当于符号不匹配吧
5. 不同版本的编译器、操作系统、硬件平台等

相对来讲，c++其语法的复杂性使得兼容性更难以保持，很多时候使用 c++ 调用 c 共享库接口是个不错的选择。
## 共享库版本命名
linux规定了一套共享库版本命名规则: `libname.so.x.y.z` 
- name : 库名称
- x : 主版本号（Major Version Number），库的重大升级，可能不会兼容旧库
  + 所以以前的程序需要重新编译链接后才能使用此新库
- y : 次版本号（Minor Version Number）， 增加一些新的接口符号且保持原来的接口不变
- z : 发布版本号（Release Version Number）， 修正库的错误、性能改进等，不会添加新的接口也不会改变接口。

所以一个库的次版本号和发布版本号升级时，对应的程序是不用重新升级的，直接拿来就能用。而主版本号升级时，最好根据说明修改代码再重新编译链接。
## SO-NAME
由上面可以看出，主版本号决定了库的兼容性，一个程序主模块必须使用对应主版本号一致的共享库。

Linux中使用 `SO-NAME` 来表示共享库的主版本号，通常这是一个指向共享库全名的软链接。(比如共享库为 libfoo.so.2.6.1，对应的 SO-NAME 就为libfoo.so.2)
- 软链接会指向目录中主版本号相同、次版本号和发布版本号最新的共享库。
  + `ldconfig` 用于自动遍历共享库目录，更新软链接到最新共享库
  

在实际的主模块进行链接和运行时，都是使用以 `SO-NAME` 为名字的软链接。

在实际编译主模块源码时，只需要使用 `-l<name>` 参数，gcc会自动查找最新版本的 <name> 库。
- 查找路径由参数 `-l` 决定
- 当使用 `-static` 参数时，gcc 会查找静态库，也就是lib<name>.a

# 符号版本
## 次版本号交会问题（Minor-revision Rendezvous Problem）
当某个程序依赖于较高的次版本号的共享库，而运行于较低此版本号的共享库系统时，就可能产生缺少某些符号的错误。
- 因为次版本号可能会增加一些接口，且它只保证向后兼容性。
## 基于符号的版本机制（Symbol Versioning）
上面这个问题，使用符号版本机制来解决： 让每个导出和导入的符号都有一个相关联的版本号，它的实际做法类似于名称修饰的方法。
- 在那些新的次版本号中添加的全局符号打上相应的版本标记。
  

加上符号版本机制后，当在编译和链接程序时，链接器会根据当前程序依赖的符号而记录**它所用到的最低满足要求的符号版本**。
在程序运行时，动态链接器会通过程序内记录的它所依赖的所有共享库的符号集合版本信息，然后判定当前系统共享库中的符号集合版本是否满足这些被依赖的符号即可。

符号版本的设置可以使用符号版本脚本，而在 gcc 中还可以使用汇编宏指令来指定符号版本:
``` c
  //将add符号指定为符号标签VERS_1.1
  asm(".symver add, add@VERS_1.1")
  int add(int a, int b)
  {
    return a + b;
  }

  //还可以实现类似于c++的符号重载机制
  //这样可以兼容新旧版程序
  asm(".symver old_printf, printf@VERS_1.1")
  asm(".symver new_printf, printf@VERS_1.2")
  int old_printf()
  {
  }
  int new_printf()
  {
  }
```

# 共享库系统路径
FHS（File Hierarchy Standard）标准规定了共享库路径:
- `/lib` : 系统最关键和基础的共享库，主要被 `/bin,/sbin，启动过程` 下的程序所使用
  + 比如动态链接器、c运行时库等
- `/usr/lib` : 非系统运行时所需要的关键性共享库，主要是一些开发时用到的库，一般不会被用户的程序或 shell 脚本直接使用
- `/usr/local/lib` : 跟系统本身并不十分相关的库，主要是一些第三方应用程序的库，主要被 `/usr/local/bin` 下的程序使用
# 共享库查找过程
模块中的 `.dynamic` 标明了依赖库的路径。
- 如果此路径是绝对路径，那么就按照这个路径查找
- 如果是相对路径，则会依次在 `/etc/ld.so.cache,/usr/lib/,/lib/` 中查找

`ldconfig` 会刷新动态链接库的符号链接，并集中存放到 `/etc/ld.so.cache` 文件中，以便于快速查找。
- 所以当安装、更新共享库后，都需要使用 `ldconfig` 命令
# 环境变量
## LD_LIBRARY_PATH
用于临时改变应用程序的共享库查找路径，而不会影响系统中的其他程序。
- 有利于共享库的调试和测试

默认 =LD_LIBRARY_PATH= 的值为空，若为某个进程设置了路径，动态链接器会优先寻找此路径。
## LD_PRELOAD
指定预先装载的一些共享库或是目标文件，无论程序是否依赖于它们，LD_PRELOAD里面指定的共享库或目标文件都会被装载。
## LD_DEBUG
可以打开动态链接器的调试功能，可以设置以下值:
- files : 显示装载过程
- bindings : 显示动态链接的符号绑定过程
- libs : 显示共享库的查找过程
- versions : 显示符号的版本依赖关系
- reloc : 显示重定位过程
- symbols : 显示符号表查找过程
- statistics : 显示动态链接过程中的各种统计信息
- all : 显示以上所有信息
- help : 显示上面的各种可选值的帮助信息

比如要打印装载过程：
```shell
$ LD_DEBUG=files ./program1
```
# 共享库的创建与安装
## 创建
```shell
  gcc -shared -Wl,-soname,<soname> -o <library_name> <source_files> <library_files>
```
- `-WL,-soname`  用于指定 SO-NAME，用于以后被 `ldconfig`= 使用
  

比如有libfoo1.c，libfoo2.c，产生 libfoo.so.1.0.0 的共享库，且它们依赖于 libbar1.so，libbar2.so这两个共享库，那么命令如下:
```shell
  gcc -shared -fPIC -Wl,-soname,libfoo.so.1 -o libfoo.so.1.0.0 libfoo1.c libfoo2.c -lbar1 -lbar2
```
## 安装
1. 将生成的共享库复制到标准共享目录
2. 运行 ldconfig 生成软链接

如果不是存放在标准目录，使用 `ldconfig -n shared_library_directory` 建立SO-NAME,并且需要为gcc提供"-L"和"-l"参数
- "-L" 指定共享库的搜索路径
- "-l" 指定共享库名称
## 共享库的构造和析构
构造函数，可以在共享库加载后进行一些初始化工作，可以在main函数运行前或在 `dlopen()` 返回前运行:
``` c
  void __attribute__((constructor)) init_function(void);
```
析构函数，可以在main函数执行完毕后，或在 `dlclose()` 返回前运行:
``` c
  void __attribute__((destructor)) fini_function(void);
```

**注意:** 为了使用这种特性，gcc不可以使用 `-nostartfiles,-nostdlib` 这两个参数!

可以存在多个构造和析构函数，并为它们指定优先级：
- 对于构造，数值越小优先级越高。而析构的优先级正好相反，这也符合资源的申请和释放原则
``` c
  void __attribute__((constructor(5))) init_function1(void);
  void __attribute__((constructor(10))) init_function2(void);

  void __attribute__((destructor(10))) fini_function2(void);
  void __attribute__((destructor(5))) fini_function1(void);
```




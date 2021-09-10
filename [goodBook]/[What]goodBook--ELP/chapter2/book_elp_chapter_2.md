---
title: '[What]Learning about Toolchains'
tags: 
- CS
categories: 
- book
- Embedded Linux Programming
layout: true
---

学习书籍：[Mastering Embedded Linux Programming: Create fast and reliable embedded solutions with Linux 5.4 and the Yocto Project 3.1 (Dunfell), 3rd Edition](https://www.amazon.com/Mastering-Embedded-Linux-Programming-potential/dp/1789530385)
> 通过阅读这部书，将整个嵌入式 Linux 的开发知识串联起来，以整理这些年来所学的杂乱知识。

- 开发主机：ubuntu 20.04 LTS
- 开发板：[myc-c8mmx-c](http://www.myir-tech.com/product/myc-c8mmx.htm) imx8mm（4核 A53 + M4）
- 系统：Linux 5.4
- yocto：3.1

工具链的选择一般放在最开始，工具链选好以后最好就不要变动了。

> 或者说要变动的话，也是所有变动，所有的源码都要重新编译一次。

<!--more-->

# 准备工作

## 安装基本工具

在使用/编译工具链时，需要安装下面这些工具：

```shell
$ sudo apt install -y autoconf automake bison bzip2 cmake \
flex g++ gawk gcc gettext git gperf help2man libncurses5-dev libstdc++6 libtool \
libtool-bin make patch python3-dev rsync texinfo unzip wget xz-utils
```

## 工具链

虽然 Clang 发展迅猛，且也可以用来交叉编译。但目前 GNU 工具链依然是最受欢迎的选择。

标准的 GNU 工具链包含以下几个组成部分：

- [Binutils](http://gnu.org/software/binutils)：二进制工具的集合，包含 ld，as，addr2line，strip 等

  > 这在分析目标文件，对目标文件进行瘦身等非常有用

- [GCC](http://gcc.gnu.org/)：主要用于 c/c++ 的编译器集合

- c/c++ 库：包含支持 c/c++ 标准，且具有自己的扩展

对于嵌入式开发而言，需要包含两种编译器：

1. Native：也就是 X86 主机上用的本地编译器，这可以在前期开发应用程序时，直接在 PC 上模拟。开发效率当然是高于直接在嵌入式板上运行。

   > 当然，这就需要代码做好跨平台的兼容性。

2. Cross：进行底层（bootloader，kernel）开发或需要将应用程序在目标板上运行时，才需要进行交叉编译。

其实，即使开发主机和目标板的架构一样。也应该将他们的工具链分开，因为开发主机会随着时间推移而更新其工具链，这也会造成不一致的情况。

## CPU 架构的差异与工具链

在选择工具链的时候，有下面这些因素需要考虑：

- CPU 架构：是 ARM、ARM64，还是 MIPS

- CPU 所支持的大小端

- CPU 是否具备硬件浮点单元：如果不具备，则只能使用软件模拟浮点运算

- CPU 所对应的 ABI

  > ARM 架构使用的是`Extended Application Binary Interface（EABI）`。
  >
  > 而根据 CPU 是否支持硬件浮点，又分为普通的 EABI 和带硬件浮点的 EABI：
  >
  > `Extended Application Binary Interface Hard-Float（EABIHF）`

GNU 工具链通过名称的前缀来区分这些差异，之间用短横线区分：

>  `CPU`-`[Vendor]`-`Kernel`-`Operating system`-`tools name`

比如 `arm-xilinx-linux-gnueabi-gcc`。

- CPU：指定 CPU 架构，比如`arm,mips,x86_64`

  > 如果 CPU 支持大小端切换，那么还会加上`el`对应小端，`eb`对应大端。
  >
  > 比如 `mipsel`对应 MIPS 小端模式，`armeb`对应 ARM 大端模式

- Vendor：说明工具链的提供者，比如`buildroot,poly,unknown`，有些时候也没有该项

- Kernel：说明是用于裸机还是带系统，比如对于 Linux 就是字符串 `linux`。

- Operating system：指定 ABI，比如对于 GNU 对应 ARM 版本且带硬件浮点：`gnueabihf`

- tools name：就是工具名了，比如`gcc,g++,ldd`

如果工具链的名字信息不全（通常是 Native 编译器），那么可以通过`-dumpmachie`选项来输出：

```shell
~$ gcc -dumpmachine
x86_64-linux-gnu
```

## c 库的差异

c 库有以下几个选择：

- [glibc](https://www.gnu.org/software/libc/)：GNU 标准 C 库，对 POSIX 支持也是最为完善的，只是体积占用比较大。
- [musl libc](https://musl.libc.org/)：兼容性与 glibc 比较接近，但是占用体积比较小
- [uClibc-ng](https://uclibc-ng.org/)：专用于嵌入式场景的 c 库，主要还是 uClinux 用得多
- [eglibc](http://www.eglibc.org/home)：也是专用于嵌入式场景的 c 库，但已经好几年没有更新了

所以，如果 RAM 很小，那就选 musl libc，否则还是选 glibc 是最简单粗暴的方式。

# 获取工具链

工具链的获取有 3 种选择：

1. 选择已经编译好的第三方工具链
   - SOC 厂商或开发板厂商会提供他们的工具链
   - 一些开源组织（比如[linaro](https://www.linaro.org/)）会提供他们的工具链
   - 发行版也会维护交叉编译工具链
2. 选择构建工具（buildroot,yocto）提供的工具链
3. 使用源码自己构建工具链

一般在没有特殊需求的情况下，都会使用前两个选择。

## 获取已有的工具链

首选在 SOC 厂商网站上获取他们所提供的工具链，其次才是在`linaro`网站上获取。

其工具链位于[arm 工具链主页](https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain)中，但由于网络原因，推荐使用[清华大学开源镜像站](https://mirrors.tuna.tsinghua.edu.cn/armbian-releases/_toolchain/)。

## 自己构建工具链

构建工具链最简单的办法是通过[crosstool-NG](https://github.com/crosstool-ng/crosstool-ng) 来完成自动化构建。

### 安装 crosstool-NG

```shell
# 如果有代理，可以在命令行使用代理来加速
# export http_proxy="http://xx.xx.xx.xx:port"
# export https_proxy="http://xx.xx.xx.xx:port"
$ git clone https://github.com/crosstool-ng/crosstool-ng
$ ./bootstrap
$ ./configure
$ make
$ sudo make install
```

### 查看默认支持的工具链配置

可以先使用`ct-ng list-samples`命令列出 Crosstool-NG 所支持的类型。

然后在需要构建的工具链名称前面加`show-`便可以看到针对该工具链的一些配置：

```shell
$ ct-ng show-aarch64-unknown-linux-gnu
[L...]   aarch64-unknown-linux-gnu
    Languages       : C,C++
    OS              : linux-5.13.1
    Binutils        : binutils-2.37
    Compiler        : gcc-11.2.0
    C library       : glibc-2.34
    Debug tools     : gdb-10.2
    Companion libs  : expat-2.4.1 gettext-0.20.1 gmp-6.2.1 isl-0.24 libiconv-1.16 mpc-1.2.0 mpfr-4.1.0 ncurses-6.2 zlib-1.2.11
    Companion tools :
```

### 编译工具链

先选择`aarch64-unknown-linux-gnu`工具链，就和编译 uboot,kernel 选择配置文件一样：

```shell
$ ct-ng aarch64-unknown-linux-gnu
```

工具链进一步配置，这和 uboot,kernel 对配置做修改一样的操作：

```shell
$ ct-ng menuconfig
```

- 关闭`Path and misc options->Render the toolchain read-only`

  > 为了在后面可以在工具链库路径中加入其他库，这样在交叉编译时不会因为找不到库而编译错误

- ~~选择`Target options->Floating point`为`hardware(FPU)`~~（32 位 arm 中有此选项）

  > 如果有硬件浮点的话，那么选择此项才能产生使用硬件浮点单元的汇编，以提高运行效率

- ~~填入`Target options->Use specific FPU`值为`neon`~~（32 位 arm 中有此选项）

  > 产生一个裸机版本的工具链，以可以编译内核

然后开始构建：

```shell
$ ct-ng build
```

最终的输出位于：`~x-tools/aarch64-unknown-linux-gnu`

# 使用工具链

## 加入环境变量

在编译好工具链后，就需要将其路径加入`PATH`环境变量，以让当前 SHELL 可以正常使用：

```shell
$ PATH=~/x-tools/aarch64-unknown-linux-gnu/bin:$PATH
```

## 查看版本和配置

```shell
# 查看版本
$ aarch64-unknown-linux-gnu-gcc --version
# 查看编译时的配置
$ aarch64-unknown-linux-gnu-gcc -v
```

在查看配置时，有几个选项是值得关注的：

- `--with-sysroot=`：指定默认的 sysroot 目录

- `--enable-languages=`：说明编译器支持的版本

- `--with-cpu=`：针对的 CPU

  > 如果想在编译时设定为其他 CPU，可以在编译时使用选项`-mcpu=xxx`

- `--with-float=`：是否支持硬件浮点

- `--enable-threads=posix`：是否支持 POSIX 线程

## sysroot

`sysroot`指的是一个包含库、头文件、配置文件的一个目录。

这些文件就是编译时查找的头文件、库等。

可以使用`-print-sysroot`选项来输出该路径：

```shell
$ aarch64-unknown-linux-gnu-gcc -print-sysroot
```

其中：

- `lib`文件夹：包含了 C 语言的动态链接库，链接器等
- `/usr/lib/`：包含了 C 语言的静态链接库
- `/usr/include`：包含了以上库的头文件
- `/usr/bin`：包含了在目标板上运行的工具
- `/usr/share`：包含的是一些本地化，国际化等
- `sbin`：主要包含`ldconfig`工具，用于优化动态库的载入路径

## 工具链中的其他工具

编译出来的工具链，还有一些其他常用的工具：

- `addr2line`：将执行文件中打印地址反推到源码的文件及行数。

  > 运行崩溃时，日志打印栈调用地址，然后通过该工具来反推源码文件及行数。定位问题很有帮助。

- `ar`：打包目标文件为静态链接库

- `as`：汇编器

- `c++filt`：重组 c++ 和 java 符号

- `cpp`：c 预处理器

- `elfedit`：编辑 ELF 文件的头

- `g++`：c++ 编译前端

- `gcc`：c 编译前端

- `gcov`：代码覆盖率工具

- `gdb`：强大的调试器

- `gprof`：程序分析工具

- `ld`：链接器

- `nm`：查看目标文件的符号表

- `objcopy`：拷贝和转化目标文件

- `objdump`：查看目标文件的详细信息

- `ranlib`：改变静态链接库的索引以加快链接速度

- `readelf`：查看目标文件信息的另一个工具

- `size`：输出目标文件代码段、数据段等占用

- `strings`：显示文件中的可显示字符

- `strip`：去除目标文件中的调试信息

## C 库中的组件

c 库由 4 部分组成来实现 POSIX API：

- `libc`： c 库的主要部分，包含了常用的函数
- `libm`：包含数学运算的函数
- `libpthread`：包含`pthread`相关操作函数
- `librt`：实时操作函数，比如共享内存、异步 I/O

其中`libc`组件是默认都会链接的，不需要在编译命令中指明，而其他 3 个在需要的时候需要指明。方式就是`-l`加上名称，名称去掉`lib`前缀。

> 比如要链接数学库，就使用 -lm
>
> 要用实时操作函数，就使用 -lrt
>
> 要用多线程，就使用 -lpthread 或 -pthread

要查看一个可执行文件的链接库，可以使用`readelf`来查看：

```shell
$ readelf -a a.out | grep "Shared library"
```

# 链接静态/动态库

这方面的工作，就交给[现代 CMake](http://kcmetercec.top/2021/06/10/cmake_modern/)是最简单粗暴的方式。

关于动态库的组织关系，参考[此文章](http://kcmetercec.top/2018/11/25/linker_load_chapter8/)。

# 使用不同的构建工具

对于应用编写，无脑使用 CMake 即可。

但对于第三方库、bootloader、kernel、rootfs 可能使用的是 makefile、autotools 等。

## Makefile

对使用到 Makefile 的工程进行交叉编译时，大部分情况下只需要设定变量` CROSS_COMPILE`来指定工具链：

```shell
# 方法 1
$ make CROSS_COMPILE=arm-cortex_a8-linux-gnueabihf-
# 方法 2
$ export CROSS_COMPILE=arm-cortex_a8-linux-gnueabihf-
$ make
```

对于像 U-boot、kernel 这种兼容多种硬件的项目，还需要设定`ARCH`变量来指定硬件内核。

## Autotools

对于使用 Autotools 构建的项目，一般先使用`./configure --help`来查看其构建所支持的选项，然后再使用 make 来进行构建。

### 选项

其常用的选项如下：

- `CC`：指定 C 编译器
- `CFLAGS`：指定 C 编译器的选项
- `CXX`：指定 c++ 编译器
- `CXXFLAGS`：指定 c++ 编译器的选项
- `LDFLAGS`：指定链接选项，一般是库路径
- `LIBS`：指定需要链接的库
- `CPPFLAGS`：c 和 c++ 预编译选项，比如指定头文件路径
- `CPP`：指定 c 与编译器

### 常用编译命令

大部分情况下，只需要指定编译器和主机即可：

```shell
# host 指定代码需要运行的目标机，如果是 native 编译则不需要指定这些选项
$ CC=arm-cortex_a8-linux-gnueabihf-gcc ./configure --host=arm-cortex_a8-linux-gnueabihf-gcc
```

默认的安装目录是在`<sysroot>/usr/local/`如果想要改变安装路径，需要使用`prefix`选项：

```shell
$ CC=arm-cortex_a8-linux-gnueabihf-gcc \
./configure --host=arm-cortex_a8-linux-gnueabihf --prefix=/usr
```

对于交叉编译库，一般在`make install`时设置`DESTDIR`变量到`sysroot`，以正确进行交叉编译：

> 要不然交叉编译时，就要指定库路径和头文件路径

```shell
$ make DESTDIR=$(arm-cortex_a8-linux-gnueabihf-gcc -print-
sysroot) install
```

### 包管理

[pkg-config](https://www.freedesktop.org/wiki/Software/pkg-config/) 工具提供了对包管理的支持。

比如查看一个库所对应的库名称，c 选项：

```shell
# 指定搜寻路径
$ export PKG_CONFIG_LIBDIR=$(arm-cortex_a8-linux-gnueabihf-gcc \
-print-sysroot)/usr/lib/pkgconfig
$ pkg-config sqlite3 --libs --cflags
# 这里显示编译时只要 -lsqlite3 便可以使用该库了
-lsqlite3 便可以使用该库了
```

还可以直接使用输出结果作为编译选项：

```shell
$ export PKG_CONFIG_LIBDIR=$(arm-cortex_a8-linux-gnueabihf-gcc \
-print-sysroot)/usr/lib/pkgconfig
$ arm-cortex_a8-linux-gnueabihf-gcc $(pkg-config sqlite3 
--cflags --libs) \
sqlite-test.c -o sqlite-test
```

## CMake

对于 CMkae 的使用，参考[现代 CMake](http://kcmetercec.top/2021/06/10/cmake_modern/)即可。

对于交叉编译，查看[编写工具链文件即可](http://kcmetercec.top/2018/08/02/linux_cmake_toolchains/)。

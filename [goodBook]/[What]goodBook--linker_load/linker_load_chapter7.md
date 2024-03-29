---
title: '[What]链接、装载与库 --> 动态链接'
tags: 
- CS
date:  2018/11/25
categories: 
- book
- 程序员的自我休养
layout: true
---

静态链接使得内存浪费太大并且更新不方便，而动态链接则弥补了这个不足。

动态链接的基本思想是把程序按照模块拆分成各个相对独立部分，在程序运行时才将它们链接在一起形成一个完整程序。
而不像静态链接一样把所有程序模块都链接成一个单独的可执行文件。
- linux下为**动态共享对象(DSO, Dynamic Shared Objects)**， 以 `.so` 为扩展名
- windows下为**动态链接库(Dynamical Linking Library)**， 以 `.dll` 为扩展名

动态链接的优点如下:
1. 一个动态链接库被多个进程所使用，节省了内存空间
2. 由于多个进程共享同一模块，使得 cpu cache 命中率很高
3. 动态模块升级时不用更新程序其他部分，使得升级方便
4. 程序在运行时可以动态加载各种程序模块，可以被用于制作插件
5. 只要操作系统提供了相应的接口，模块就可以跨操作系统兼容
  - 如何接口没有管理好，那么兼容性将会是个问题
<!--more-->
# 实例感受
测试代码如下：
``` c
  //file program1.c
  #include "lib.h"

  int main()
  {
    foobar(1);

    return 0;
  }
  //file program2.c
  #include "lib.h"

  int main()
  {
    foobar(2);

    return 0;
  }
  //file lib.c
  #include <stdio.h>

  void foobar(int i)
  {
    printf("printing from lib.so %d\n", i);
  }
  //file lib.h
  #ifndef __LIB_H__
  #define __LIB_H__
  extern void foobar(int i);
  #endif
```
编译共享库及执行验证
``` shell
  $ gcc -fPIC -shared -o lib.so lib.c
  $ gcc -o program1 program1.c ./lib.so
  $ gcc -o program2 program2.c ./lib.so
  $ ls
  lib.c  lib.h  lib.so  program1  program1.c  program2  program2.c
  $ ./program1
  printing from lib.so 1
  $ ./program2
  printing from lib.so 2
```
为了能够观察代码在虚拟地址中的映射关系，修改 `lib.c` :
``` c
  #include <stdio.h>
  #include <unistd.h>

  void foobar(int i)
  {
    printf("printing from lib.so %d\n", i);
    printf("sleep\n");
    while(1)
      {
        sleep(1);  
      }
  }
```
可以看到它映射格局如下:
```shell
  $ ./program1&
  [3] 549
  printing from lib.so 1
  sleep
  $ cat /proc/549/maps 
55c3030fc000-55c3030fd000 r-xp 00000000 08:10 44885                      /home/cec/lab/linux/link/program1
55c3032fc000-55c3032fd000 r--p 00000000 08:10 44885                      /home/cec/lab/linux/link/program1
55c3032fd000-55c3032fe000 rw-p 00001000 08:10 44885                      /home/cec/lab/linux/link/program1
55c30507b000-55c30509c000 rw-p 00000000 00:00 0                          [heap]
7fa47bf7e000-7fa47c165000 r-xp 00000000 08:10 42386                      /lib/x86_64-linux-gnu/libc-2.27.so
7fa47c165000-7fa47c365000 ---p 001e7000 08:10 42386                      /lib/x86_64-linux-gnu/libc-2.27.so
7fa47c365000-7fa47c369000 r--p 001e7000 08:10 42386                      /lib/x86_64-linux-gnu/libc-2.27.so
7fa47c369000-7fa47c36b000 rw-p 001eb000 08:10 42386                      /lib/x86_64-linux-gnu/libc-2.27.so
7fa47c36b000-7fa47c36f000 rw-p 00000000 00:00 0
7fa47c36f000-7fa47c370000 r-xp 00000000 08:10 44884                      /home/cec/lab/linux/link/lib.so
7fa47c370000-7fa47c56f000 ---p 00001000 08:10 44884                      /home/cec/lab/linux/link/lib.so
7fa47c56f000-7fa47c570000 r--p 00000000 08:10 44884                      /home/cec/lab/linux/link/lib.so
7fa47c570000-7fa47c571000 rw-p 00001000 08:10 44884                      /home/cec/lab/linux/link/lib.so
7fa47c571000-7fa47c59a000 r-xp 00000000 08:10 42363                      /lib/x86_64-linux-gnu/ld-2.27.so
7fa47c78e000-7fa47c791000 rw-p 00000000 00:00 0
7fa47c798000-7fa47c79a000 rw-p 00000000 00:00 0
7fa47c79a000-7fa47c79b000 r--p 00029000 08:10 42363                      /lib/x86_64-linux-gnu/ld-2.27.so
7fa47c79b000-7fa47c79c000 rw-p 0002a000 08:10 42363                      /lib/x86_64-linux-gnu/ld-2.27.so
7fa47c79c000-7fa47c79d000 rw-p 00000000 00:00 0
7ffe11729000-7ffe1174a000 rw-p 00000000 00:00 0                          [stack]
7ffe117be000-7ffe117c1000 r--p 00000000 00:00 0                          [vvar]
7ffe117c1000-7ffe117c2000 r-xp 00000000 00:00 0                          [vdso]

```
在堆与栈之间，映射了动态链接库 `libc,lib` 以及动态链接器 `ld` 。
- 在运行 program1 之前，动态链接器先完成链接工作，然后再把控制权交给 program1 执行。
# 地址无关代码
动态链接库在被装载时其地址是未知的，这是为了避免:
1. 多个动态库的干涉问题
2. 自身以后升级，内部函数和变量地址改变的问题
   

所以使用了**装载时重定位(Load Time Relocation)**的方式： 在链接时，对所有绝对地址的引用不作重定位，而把这一步推迟到装载时再完成。
一旦模块装载地址确定，即目标地址确定，那么系统对程序中所有的绝对地址引用进行重定位。

但这种方式依然有问题: 因为需要重定位，就需要修改动态链接库的代码(也就是地址会改变)。但是动态链接库是需要多个进程共享的，多个进程拥有独立的数据部分，但代码部分是共享的。这就无法满足此需求。

于是，最终的**地址无关代码(PIC, Position-independent Code)**方式就产生了: 把指令中那些需要被修改的部分分离出来，跟数据部分放在一起，这样指令部分就可以保存不变。
而数据部分可以在每个进程拥有一个副本。
- 在实现时，数据段中存放指向这些函数的指针数组(全局偏移表，Global Offset Table, GOT)，通过数组来间接找到动态链接库代码的位置。
  

地址无关引用方式如下表:
|          | 指令跳转、调用      | 数据访问      |
|----------|-------------------|---------------|
| 模块内部 | 相对跳转和调用      | 相对地址访问  |
| 模块外部 | 间接跳转和调用(GOT) | 间接访问(GOT) |

# 延迟绑定
动态链接在程序启动时装载一起运行时的 GOT 定位都会减慢程序的运行速度，为了优化启动速度使用延迟绑定（Lazy Binding）的方式来优化。
- 延迟绑定使用 PLT（Procedure Linkage Table） 的方式实现

其核心思想就是：当函数被第一次调用到的时候才执行符号绑定、重定位等操作。
- 因为很多函数并不会被使用

PLT在函数第一次被调用后，首先进行符号查找、重定位，然后才会填充 GOT 表。
> 最开始 GOT 中只保存被引用函数在重定位表中的索引，PLT 代码根据此索引得到需要被重定位的函数，再结合当前被链接的模块调用查找功能函数获取函数地址。最终才将该函数的地址填充到 GOT 表。下一次再进行函数调用时，就直接可以通过 GOT 表地址来调用了。整个过程类似于操作系统使用 MMU 来实现虚拟内存到物理内存的 lazy 映射机制。

ELF 将 GO T拆分成了两个表叫做`.got`和`.got.plt`，`.got`用来保存全局变量引用的地址，`.got.plt`用来保存函数引用的地址。

# 动态链接相关结构
动态链接方式的elf文件启动步骤为：
1. 读取可执行文件头部，检查文件合法性，从头部中的`Program Header`中读取每个`Segment`的虚拟地址、文件地址和属性，并将它们映射到进程虚拟空间的相应位置
2. 将动态链接器加载到进程地址空间并将控制权交给动态链接器的入口地址。
3. 动态链接器执行一系列自身初始化操作，根据当前环境参数开始对可执行文件进行动态链接工作，当链接工作完成后将控制权转交到可执行文件的入口地址，程序开始运行
## ".interp"段
`.interp` 段保存一个字符串，指定该可执行文件所需要的动态连接器的路径。
``` shell
program1:     file format elf64-x86-64

Contents of section .interp:
 0238 2f6c6962 36342f6c 642d6c69 6e75782d  /lib64/ld-linux-
 0248 7838362d 36342e73 6f2e3200           x86-64.so.2. 
```
可以看到在x86-64系统上其为 `/lib64/ld-linux-x86-64.so.2` ,实际上它是一个符号链接，指向当前系统的动态连接器。

这样的好处是：当动态连接器版本有所更新时，不需要重新编译可执行文件，因为符号链接的路径和名称都不会被改变。
## ".dynamic"段(动态链接描述头)
`.dynamic` 段保存了动态连接器所需要的基本信息，比如依赖于哪些共享对象、动态链接符号表的位置、动态链接重定位表的位置、共享对象初始化代码的地址等。
- `.dynamic` 存在于动态链接文件中，类似于elf文件头，用于描述此文件的概览
``` c
  typedef struct
  {
    Elf64_Sxword	d_tag;			/* Dynamic entry type */
    union
    {
      Elf64_Xword d_val;		/* Integer value */
      Elf64_Addr d_ptr;			/* Address value */
    } d_un;
  } Elf64_Dyn;
```
比较常用的d_tag有下面这些值:
| d_tag类型            | d_un的含义                                         |
|----------------------|----------------------------------------------------|
| DT_SYMTAB            | 动态链接符号表的地址，d_ptr表示".dynsym"的地址     |
| DT_STRTAB            | 动态链接字符串表地址，d_ptr表示".dynstr"的地址     |
| DT_STRSZ             | 动态链接字符串表大小，d_val表示大小                |
| DT_HASH              | 动态链接哈希表地址,d_ptr表示".hash"的地址          |
| DT_SONAME            | 本共享对象的"SO-NAME"                              |
| DT_RPATH             | 动态链接共享对象搜索路径                           |
| DT_INIT              | 初始化代码地址                                     |
| DT_FINIT             | 结束代码地址                                       |
| DT_NEED              | 依赖的共享对象文件,d_ptr表示所依赖的共享对象文件名 |
| DT_REL/DT_RELA       | 动态链接重定位表地址                               |
| DT_RELENT/DT_RELAENT | 动态重读位表入口数量                               |
``` shell
$ readelf -d lib.so

Dynamic section at offset 0xe20 contains 24 entries:
  Tag        Type                         Name/Value
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
 0x000000000000000c (INIT)               0x4e8
 0x000000000000000d (FINI)               0x644
 0x0000000000000019 (INIT_ARRAY)         0x200e10
 0x000000000000001b (INIT_ARRAYSZ)       8 (bytes)
 0x000000000000001a (FINI_ARRAY)         0x200e18
 0x000000000000001c (FINI_ARRAYSZ)       8 (bytes)
 0x000000006ffffef5 (GNU_HASH)           0x1f0
 0x0000000000000005 (STRTAB)             0x350
 0x0000000000000006 (SYMTAB)             0x230
 0x000000000000000a (STRSZ)              157 (bytes)
 0x000000000000000b (SYMENT)             24 (bytes)
 0x0000000000000003 (PLTGOT)             0x201000
 0x0000000000000002 (PLTRELSZ)           24 (bytes)
 0x0000000000000014 (PLTREL)             RELA
 0x0000000000000017 (JMPREL)             0x4d0
 0x0000000000000007 (RELA)               0x428
 0x0000000000000008 (RELASZ)             168 (bytes)
 0x0000000000000009 (RELAENT)            24 (bytes)
 0x000000006ffffffe (VERNEED)            0x408
 0x000000006fffffff (VERNEEDNUM)         1
 0x000000006ffffff0 (VERSYM)             0x3ee
 0x000000006ffffff9 (RELACOUNT)          3
 0x0000000000000000 (NULL)               0x0
```
## 动态符号表
静态链接中，符号的建立和使用被分别称为定义和引用。
而动态链接中，动态链接库符号被外部使用时称为导出（Export），对应使用外部符号的部分称为导入（Import）。

和静态链接一样，为了表示符号的导入导出关系，elf使用**动态符号表(Dynamic Symbol Table)**来保存这些信息，段名 `.dynsym`
- 与符号表（.symtab）不同的是，.dynsym 只保存了与动态链接相关的符号。而所有的符号依然保存在 `.symtab` 中。

同样的，动态符号表中实际包含的是符号的下标，真正的字符串内存存在于**动态符号字符串表（.dynstr ,Dynamic String Table）** 中
- 由于动态链接下，需要在运行时查找符号，为了加快符号的查找过程，还需要有辅助的**符号哈希表（.hash）*。

```shell
$ readelf --dyn-syms  lib.so 

Symbol table '.dynsym' contains 12 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
     1: 0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND _ITM_deregisterTMCloneTab
     2: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND printf@GLIBC_2.2.5 (2)
     3: 0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND __gmon_start__
     4: 0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND _ITM_registerTMCloneTable
     5: 0000000000000000     0 FUNC    WEAK   DEFAULT  UND __cxa_finalize@GLIBC_2.2.5 (2)
     6: 000000000020102c     0 NOTYPE  GLOBAL DEFAULT   22 _edata
     7: 0000000000201030     0 NOTYPE  GLOBAL DEFAULT   23 _end
     8: 000000000020102c     0 NOTYPE  GLOBAL DEFAULT   23 __bss_start
     9: 00000000000004e8     0 FUNC    GLOBAL DEFAULT    9 _init
    10: 0000000000000644     0 FUNC    GLOBAL DEFAULT   13 _fini
    11: 000000000000060a    57 FUNC    GLOBAL DEFAULT   12 foobar


$ readelf -sD  lib.so 

Symbol table of `.gnu.hash' for image:
  Num Buc:    Value          Size   Type   Bind Vis      Ndx Name
    6   0: 000000000020102c     0 NOTYPE  GLOBAL DEFAULT  22 _edata
    7   0: 0000000000201030     0 NOTYPE  GLOBAL DEFAULT  23 _end
    8   1: 000000000020102c     0 NOTYPE  GLOBAL DEFAULT  23 __bss_start
    9   1: 00000000000004e8     0 FUNC    GLOBAL DEFAULT   9 _init
   10   2: 0000000000000644     0 FUNC    GLOBAL DEFAULT  13 _fini
   11   2: 000000000000060a    57 FUNC    GLOBAL DEFAULT  12 foobar
```
## 动态链接重定位表
在动态链接下，无论是可执行文件或共享对象，一旦它依赖于其他共享对象，那么它代码或数据中就会有对于导入符号的引用。
在编译时这些导入符号的地址未知（在静态链接中，这些目标文件中的未知地址最终在链接阶段被修正），所以就需要在运行时将这些导入符号的引用修正，也就是重定位。
- 如果一个共享对象不是以 PIC 模式编译的，那么它的代码段和数据段是需要在装载时重定位的
- 如果一个共享对象是 PIC 模式编译的，那么它的数据段是需要重定位的
  + 代码段通过 GOT 变为了相对地址引用，但 GOT 存在于数据段中，而数据段可能包含绝对地址引用。
    

静态链接的重定位是在静态链接时完成的，目标文件中包含有重定位表(.rel.text, .rel.data)。

动态链接的重定位是在装载时完成的，动态链接文件中的重定位表分别叫做 `.rel.dyn, .rel.plt` 分别对应 `.rel.data, .rel.text` 
- `.rel.dyn` 是对数据引用的修正，修正的位置位于 `.got` 以及数据段
- `.rel.plt` 是对函数引用的修改，修正的位置位于 `.got.plt` 

``` shell
$ readelf -r lib.so
Relocation section '.rela.dyn' at offset 0x428 contains 7 entries:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
000000200e10  000000000008 R_X86_64_RELATIVE                    600
000000200e18  000000000008 R_X86_64_RELATIVE                    5c0
000000201020  000000000008 R_X86_64_RELATIVE                    201020
000000200fe0  000100000006 R_X86_64_GLOB_DAT 0000000000000000 _ITM_deregisterTMClone + 0
000000200fe8  000300000006 R_X86_64_GLOB_DAT 0000000000000000 __gmon_start__ + 0
000000200ff0  000400000006 R_X86_64_GLOB_DAT 0000000000000000 _ITM_registerTMCloneTa + 0
000000200ff8  000500000006 R_X86_64_GLOB_DAT 0000000000000000 __cxa_finalize@GLIBC_2.2.5 + 0

Relocation section '.rela.plt' at offset 0x4d0 contains 1 entry:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
000000201018  000200000007 R_X86_64_JUMP_SLO 0000000000000000 printf@GLIBC_2.2.5 + 0
```
## 动态链接时进程堆栈初始化信息
进程初始化的时候，堆栈里面保存了关于进程执行环境和命令行参数等信息，还保存了动态链接器所需要的一些**辅助信息数组(Auxiliary Vector)**。
``` c
  typedef struct
  {
    uint64_t a_type;		/* Entry type */
    union
    {
      uint64_t a_val;		/* Integer value */
      /* We use to have pointer elements added here.  We cannot do that,
         though, since it does not work when using 32-bit definitions
         on 64-bit platforms and vice versa.  */
    } a_un;
  } Elf64_auxv_t;
```
| a_type 定义 | a_type 值 | a_val含义    |
|-------------|----------|-----------|
| AT_NULL     |         0 | 数组结束     |
| AT_EXEFD    |         2 | 可执行文件的句柄，动态链接器通过此句柄访问可执行文件 |
| AT_PHDR     |         3 | 可执行文件中程序头表(Program Header)在进程中的地址   |
| AT_PHENT    |         4 | 可执行文件中程序头表每个入口的大小                   |
| AT_PHNUM    |         5 | 可执行文件中程序头表中入口的数量                     |
| AT_BASE     |         7 | 动态连接器本身的装载地址                             |
| AT_ENTRY    |         9 | 可执行文件入口地址                                   |

进程栈的视图如下:
![](./process_stack.jpg)

使用下面的代码可以验证: 
``` c
#include <stdio.h>
#include <stdint.h>
#include <elf.h>

int main(int argc, char*argv[])
{
  intptr_t *p = (intptr_t *)argv;
  int arg_cnt = *(p - 1);

  printf("argument count is %d\n", arg_cnt);
  for(int i = 0; i < arg_cnt; ++i, p += 1){
      printf("%s\n", (char*)*p);
  }
  //跳过 0
  p += 1;

  printf("Environment:\n");
  while(*p){
      printf("%s\n", (char*)*p);
      p += 1;
  }

  //跳过 0
  p += 1;

  printf("Auxiliary Vectors:\n");
  Elf64_auxv_t* aux;
  aux = (Elf64_auxv_t*)p;

  while(aux->a_type != AT_NULL){
      printf("Type: %lu Value: %lx\n", aux->a_type, aux->a_un.a_val);
      aux += 1;
  }

  return 0;
}
```
# 动态链接的步骤和实现
动态链接的基本步骤分为3步:
1. 启动动态链接器本身
2. 装载所有需要的共享对象
3. 重定位和初始化
## 动态链接器启动
动态链接器本身也是一个共享对象，所以动态链接器需要有些特殊性：
1. 动态链接器不可以依赖于其他任何共享对象
2. 动态链接器本身所需要的全局、静态变量以及函数的重定位工作由它本身完成。
  - 这部分启动代码被称为**自举(Bootstrap)**
    
```shell
  动态链接器入口地址即使自举代码的入口，当操作系统将进程控制权交给动态链接器时，
  动态链接器的自举代码即开始执行。自举代码首先会找到自己的 GOT ,而 GOT 的第一个入口保存的是".dynamic"段的偏移地址，由此找到了动态链接器本身的".dynamic"段。

  通过".dynamic"中的信息，自举代码便可以获得动态链接器本身的重定位表和符号表，从而得到动态链接器本身的重定位入口，先将它们全部重定位。从这一步开始，动态链接器代码中才可以开始使用自己的全局变量和静态变量。
```
## 装载共享对象
完成自举后，动态链接器将可执行文件的符号表和链接器本身的符号表合并到一个符号表中，称为**全局符号表(Global Symbol Table)**，链接器根据".dynamic"段中内容(DT_NEEDED)来得到此文件的依赖对象。

链接器列出可执行文件中所需要的所有共享对象，将这些对象的名字放入到一个装载集合中。然后从集合里取一个名字并打开该文件并映射。

如果共享对象也依赖于其他对象，那么将所依赖的共享对象的名字放入到装载集合中，如此循环直到所有的依赖共享对象都被装载进来。
### 符号的优先级
当多个共享库中有同名的全局变量被引用，应该使用哪一个呢？

示例代码如下:
``` c
  //file a1.c
  #include <stdio.h>

  void a()
  {
    printf("a1.c\n");
  }
  //file a2.c
  #include <stdio.h>

  void a()
  {
    printf("a2.c\n");
  }
  //file b1.c
  void a();

  void b1()
  {
    a();
  }
  //file b2.c
  void a();

  void b2()
  {
    a();
  }
```
假设b1.c使用a1.c的变量，b2.c使用a2.c的变量:
``` shell
  cec@ubuntu:~/exercise/linux/linker_loader/dynamical/symbol$ gcc -fPIC -shared a1.c -o a1.so
  cec@ubuntu:~/exercise/linux/linker_loader/dynamical/symbol$ gcc -fPIC -shared a2.c -o a2.so
  cec@ubuntu:~/exercise/linux/linker_loader/dynamical/symbol$ gcc -fPIC -shared b1.c a1.so -o b1.so
  cec@ubuntu:~/exercise/linux/linker_loader/dynamical/symbol$ gcc -fPIC -shared b2.c a2.so -o b2.so
  cec@ubuntu:~/exercise/linux/linker_loader/dynamical/symbol$ ldd b1.so 
    linux-vdso.so.1 (0x00007ffddabfe000)
    a1.so => not found
  cec@ubuntu:~/exercise/linux/linker_loader/dynamical/symbol$ ldd b2.so
    linux-vdso.so.1 (0x00007ffcdd59a000)
    a2.so => not found
```
接下来调用b1和b2:
`` c
  //file main.c
  void b1();
  void b2();
  int main()
  {
    b1();
    b2();
    while(1);

    return 0;
  }
```
将a1.so,b1.so,a2.so,b2.so拷贝进/usr/lib后:
```
  cec@ubuntu:~/exercise/linux/linker_loader/dynamical/symbol$ ./main
  a1.c
  a1.c
  cec@ubuntu:~/exercise/linux/linker_loader/dynamical/symbol$ cat /proc/82889/maps
  55a2d2ab6000-55a2d2ab7000 r-xp 00000000 08:01 5382434                    /home/cec/exercise/linux/linker_loader/dynamical/symbol/main
  55a2d2cb6000-55a2d2cb7000 r--p 00000000 08:01 5382434                    /home/cec/exercise/linux/linker_loader/dynamical/symbol/main
  55a2d2cb7000-55a2d2cb8000 rw-p 00001000 08:01 5382434                    /home/cec/exercise/linux/linker_loader/dynamical/symbol/main
  55a2d365b000-55a2d367c000 rw-p 00000000 00:00 0                          [heap]
  7f3d46a43000-7f3d46a44000 r-xp 00000000 08:01 4328772                    /usr/lib/a2.so
  7f3d46a44000-7f3d46c43000 ---p 00001000 08:01 4328772                    /usr/lib/a2.so
  7f3d46c43000-7f3d46c44000 r--p 00000000 08:01 4328772                    /usr/lib/a2.so
  7f3d46c44000-7f3d46c45000 rw-p 00001000 08:01 4328772                    /usr/lib/a2.so
  7f3d46c45000-7f3d46c46000 r-xp 00000000 08:01 4325633                    /usr/lib/a1.so
  7f3d46c46000-7f3d46e45000 ---p 00001000 08:01 4325633                    /usr/lib/a1.so
  7f3d46e45000-7f3d46e46000 r--p 00000000 08:01 4325633                    /usr/lib/a1.so
  7f3d46e46000-7f3d46e47000 rw-p 00001000 08:01 4325633                    /usr/lib/a1.so
  7f3d46e47000-7f3d4702e000 r-xp 00000000 08:01 4985510                    /lib/x86_64-linux-gnu/libc-2.27.so
  7f3d4702e000-7f3d4722e000 ---p 001e7000 08:01 4985510                    /lib/x86_64-linux-gnu/libc-2.27.so
  7f3d4722e000-7f3d47232000 r--p 001e7000 08:01 4985510                    /lib/x86_64-linux-gnu/libc-2.27.so
  7f3d47232000-7f3d47234000 rw-p 001eb000 08:01 4985510                    /lib/x86_64-linux-gnu/libc-2.27.so
  7f3d47234000-7f3d47238000 rw-p 00000000 00:00 0 
  7f3d47238000-7f3d47239000 r-xp 00000000 08:01 4342578                    /usr/lib/b2.so
  7f3d47239000-7f3d47438000 ---p 00001000 08:01 4342578                    /usr/lib/b2.so
  7f3d47438000-7f3d47439000 r--p 00000000 08:01 4342578                    /usr/lib/b2.so
  7f3d47439000-7f3d4743a000 rw-p 00001000 08:01 4342578                    /usr/lib/b2.so
  7f3d4743a000-7f3d4743b000 r-xp 00000000 08:01 4342577                    /usr/lib/b1.so
  7f3d4743b000-7f3d4763a000 ---p 00001000 08:01 4342577                    /usr/lib/b1.so
  7f3d4763a000-7f3d4763b000 r--p 00000000 08:01 4342577                    /usr/lib/b1.so
  7f3d4763b000-7f3d4763c000 rw-p 00001000 08:01 4342577                    /usr/lib/b1.so
  7f3d4763c000-7f3d47663000 r-xp 00000000 08:01 4985482                    /lib/x86_64-linux-gnu/ld-2.27.so
  7f3d47844000-7f3d47846000 rw-p 00000000 00:00 0 
  7f3d47861000-7f3d47863000 rw-p 00000000 00:00 0 
  7f3d47863000-7f3d47864000 r--p 00027000 08:01 4985482                    /lib/x86_64-linux-gnu/ld-2.27.so
  7f3d47864000-7f3d47865000 rw-p 00028000 08:01 4985482                    /lib/x86_64-linux-gnu/ld-2.27.so
  7f3d47865000-7f3d47866000 rw-p 00000000 00:00 0 
  7ffcf4861000-7ffcf4882000 rw-p 00000000 00:00 0                          [stack]
  7ffcf4888000-7ffcf488b000 r--p 00000000 00:00 0                          [vvar]
  7ffcf488b000-7ffcf488d000 r-xp 00000000 00:00 0                          [vdso]
  ffffffffff600000-ffffffffff601000 r-xp 00000000 00:00 0                  [vsyscall]
```
这种一个共享对象里面的全局符号被另一个共享对象的同名全局符号覆盖的现象被称为共享对象全局符号介入（Global Symbol Interpose）.

Linux下的规则为: 当一个符号需要被加入全局符号表时，如果相同的符号名已经存在，则 **后加入的符号被忽略。**
- 在实际使用中就要避免这种符号重名的问题，否则就很可能出现莫名其妙的问题

由于main先调用的b1，所以对应的a1先被加载，接下来要加载a2时，其符号便被忽略了。
## 重定位和初始化
此步开始重新遍历可执行文件和每个共享对象的重定位表，将需要重定位的位置进行修正。

- 如果某个共享对象有 `.init` 段，那么动态链接器会执行`.init`段中的代码，用以实现共享对象特有的初始化过程。
  + 可执行文件中的 `.init` 段由程序初始化部分完成。
- 如果某个共享对象有 `.finit` 段，那么动态链接器会在进程退出时执行`.finit`段中的代码，用以实现共享对象特有的退出过程。
# 显式运行时链接(Explicit Run time Linking)
用户可以在运行时指定加载或卸载对应的模块，这就可以实现插件的功能，使得程序模块组织变得很灵活。

动态连接器如果被指定以相对路径打开共享库，其查找顺序为：
1. 查找有环境变量`LD_LIBRARY_PATH`指定的一系列目录
2. 查找由 `/etc/ld.so.cache`里面所指定的共享库路径
3. `/lib,/usr/lib`
​``` c
  /**
   ,* @brief : 加载动态库
   ,* @par: filename: 被加载动态库的路径
   ,* @par : flag : 函数符号解析方式
   ,* - RTLD_LAZY : 延迟绑定
   ,* - RTLD_NOW : 立即加载
   ,* @ret : 返回模块句柄，失败返回NULL
   ,*/
  void *dlopen(const char *filename, int flag);
  /**
   ,* @brief : 得到符号的地址
   ,* @handle : dlopen句柄
   ,* @symbol : 符号
   ,*/
  void *dlsym(void *handle, char *symbol);
  /**
   ,* @brief : 卸载动态库
   ,*/
  int dlclose(void *handle);
  /**
   ,* @brief 检查上次调用是否成功
   ,* @ret :成功返回NULL,否则返回对应的错误消息
   ,*/
  char *dlerror(void);
```

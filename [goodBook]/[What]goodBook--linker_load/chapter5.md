---
title: '[What] 链接、装载与库 --> 可执行文件的装载与进程'
tags: 
- CS
date:  2018/11/22
categories: 
- book
- 程序员的自我休养
layout: true
---

熟悉linux下可执行文件的装载过程。
<!--more-->
# 进程虚拟地址空间及装载
- 关于Linux下的内存分配，参考[linux内存管理笔记](http://kcmetercec.top/2018/03/07/linux_memory_overview_usage/#org17ea0b4)。
- 关于动态装载，参考[linux内存消耗](http://kcmetercec.top/2018/06/17/linux_memory_overview_consume/)
# 从操作系统的角度看可执行文件 

在操作系统的支持下，运行一个程序最开始只需要做三件事:
1. 创建一个独立的虚拟地址空间: 也就是建立一个页表还有[vma数据结构](http://kcmetercec.top/2018/06/17/linux_memory_overview_consume/#orga864b7a)
  - 真正的页映射到物理地址，是在产生 pagefault 时实际映射的
2. 读取可执行文件头，并且建立虚拟空间与可执行文件的映射关系
  - 知道这个关系后，才能从可执行文件的对应位置读取(可执行文件位于硬盘)，这里也会填充 VMA
3. 将CPU的指令寄存器设置成可执行文件的入口地址，启动运行
  - 这包含内核态切换到用户态的改变

以上这些步骤完成后，可执行文件的代码和数据并没有载入内存。

当一开始CPU在入口地址执行时，就会产生pagefault，内核通过分析其 vma 从硬盘中读取代码段并建立页表映射关系后，CPU再次从入口地址正常执行。
# 进程虚拟存储空间分布
## elf的链接和执行
如果一个 vma 对应 elf 上一个段的话，那么就需要段的映射是页对齐的。

当一个 elf 文件有很多段时，就会需要在虚拟地址空间对应很多页（直接对应到物理地址的页），而大部分页都有剩余空间，这就会造成内存的浪费。

但是段的权限则基本上只有3种:
1. 可读可执行：代码段
2. 可读可写：数据段和BSS段
3. 只读：只读段

所以可以将具有相同权限的段合并到一起形成一个 `segment` ，大大减小内存的浪费。
- 在将目标文件链接成可执行文件时，链接器会尽量把相同权限属性的段分配在同一空间。

静态编译如下代码:
``` c
  #include <unistd.h>

  int main()
  {
    while(1)
      {
        sleep(1000);
      }

    return 0;
  }
```
``` shell
  gcc -static section_mapping.c -o section_mapping.elf
```
使用readelf查看其段表:
``` shell
There are 33 section headers, starting at offset 0xcdd70:

Section Headers:
  [Nr] Name              Type             Address           Offset
       Size              EntSize          Flags  Link  Info  Align
  [ 0]                   NULL             0000000000000000  00000000
       0000000000000000  0000000000000000           0     0     0
  [ 1] .note.ABI-tag     NOTE             0000000000400190  00000190
       0000000000000020  0000000000000000   A       0     0     4
  [ 2] .note.gnu.build-i NOTE             00000000004001b0  000001b0
       0000000000000024  0000000000000000   A       0     0     4
readelf: Warning: [ 3]: Link field (0) should index a symtab section.
  [ 3] .rela.plt         RELA             00000000004001d8  000001d8
       0000000000000228  0000000000000018  AI       0    20     8
  [ 4] .init             PROGBITS         0000000000400400  00000400
       0000000000000017  0000000000000000  AX       0     0     4
  [ 5] .plt              PROGBITS         0000000000400418  00000418
       00000000000000b8  0000000000000000  AX       0     0     8
  [ 6] .text             PROGBITS         00000000004004d0  000004d0
       000000000008f3b0  0000000000000000  AX       0     0     16
  [ 7] __libc_freeres_fn PROGBITS         000000000048f880  0008f880
       0000000000001523  0000000000000000  AX       0     0     16
  [ 8] __libc_thread_fre PROGBITS         0000000000490db0  00090db0
       00000000000010eb  0000000000000000  AX       0     0     16
  [ 9] .fini             PROGBITS         0000000000491e9c  00091e9c
       0000000000000009  0000000000000000  AX       0     0     4
  [10] .rodata           PROGBITS         0000000000491ec0  00091ec0
       000000000001926c  0000000000000000   A       0     0     32
  [11] .stapsdt.base     PROGBITS         00000000004ab12c  000ab12c
       0000000000000001  0000000000000000   A       0     0     1
  [12] .eh_frame         PROGBITS         00000000004ab130  000ab130
       000000000000a578  0000000000000000   A       0     0     8
  [13] .gcc_except_table PROGBITS         00000000004b56a8  000b56a8
       000000000000008e  0000000000000000   A       0     0     1
  [14] .tdata            PROGBITS         00000000006b6120  000b6120
       0000000000000020  0000000000000000 WAT       0     0     8
  [15] .tbss             NOBITS           00000000006b6140  000b6140
       0000000000000040  0000000000000000 WAT       0     0     8
  [16] .init_array       INIT_ARRAY       00000000006b6140  000b6140
       0000000000000010  0000000000000008  WA       0     0     8
  [17] .fini_array       FINI_ARRAY       00000000006b6150  000b6150
       0000000000000010  0000000000000008  WA       0     0     8
  [18] .data.rel.ro      PROGBITS         00000000006b6160  000b6160
       0000000000002d94  0000000000000000  WA       0     0     32
  [19] .got              PROGBITS         00000000006b8ef8  000b8ef8
       00000000000000f8  0000000000000000  WA       0     0     8
  [20] .got.plt          PROGBITS         00000000006b9000  000b9000
       00000000000000d0  0000000000000008  WA       0     0     8
  [21] .data             PROGBITS         00000000006b90e0  000b90e0
       0000000000001af0  0000000000000000  WA       0     0     32
  [22] __libc_subfreeres PROGBITS         00000000006babd0  000babd0
       0000000000000048  0000000000000000  WA       0     0     8
  [23] __libc_IO_vtables PROGBITS         00000000006bac20  000bac20
       00000000000006a8  0000000000000000  WA       0     0     32
  [24] __libc_atexit     PROGBITS         00000000006bb2c8  000bb2c8
       0000000000000008  0000000000000000  WA       0     0     8
  [25] __libc_thread_sub PROGBITS         00000000006bb2d0  000bb2d0
       0000000000000008  0000000000000000  WA       0     0     8
  [26] .bss              NOBITS           00000000006bb2e0  000bb2d8
       00000000000016f8  0000000000000000  WA       0     0     32
  [27] __libc_freeres_pt NOBITS           00000000006bc9d8  000bb2d8
       0000000000000028  0000000000000000  WA       0     0     8
  [28] .comment          PROGBITS         0000000000000000  000bb2d8
       0000000000000029  0000000000000001  MS       0     0     1
  [29] .note.stapsdt     NOTE             0000000000000000  000bb304
       0000000000001638  0000000000000000           0     0     4
  [30] .symtab           SYMTAB           0000000000000000  000bc940
       000000000000a998  0000000000000018          31   678     8
  [31] .strtab           STRTAB           0000000000000000  000c72d8
       0000000000006920  0000000000000000           0     0     1
  [32] .shstrtab         STRTAB           0000000000000000  000cdbf8
       0000000000000176  0000000000000000           0     0     1
Key to Flags:
  W (write), A (alloc), X (execute), M (merge), S (strings), I (info),
  L (link order), O (extra OS processing required), G (group), T (TLS),
  C (compressed), x (unknown), o (OS specific), E (exclude),
  l (large), p (processor specific)

```
然后换个角度来查看其 segment，描述segment的结构叫做程序头（Program Header），用于描述ELF文件该如何被操作系统映射到进程的虚拟空间。
``` shell
Elf file type is EXEC (Executable file)
Entry point 0x400a50
There are 6 program headers, starting at offset 64

Program Headers:
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  LOAD           0x0000000000000000 0x0000000000400000 0x0000000000400000
                 0x00000000000b5736 0x00000000000b5736  R E    0x200000
  LOAD           0x00000000000b6120 0x00000000006b6120 0x00000000006b6120
                 0x00000000000051b8 0x00000000000068e0  RW     0x200000
  NOTE           0x0000000000000190 0x0000000000400190 0x0000000000400190
                 0x0000000000000044 0x0000000000000044  R      0x4
  TLS            0x00000000000b6120 0x00000000006b6120 0x00000000006b6120
                 0x0000000000000020 0x0000000000000060  R      0x8
  GNU_STACK      0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x0000000000000000 0x0000000000000000  RW     0x10
  GNU_RELRO      0x00000000000b6120 0x00000000006b6120 0x00000000006b6120
                 0x0000000000002ee0 0x0000000000002ee0  R      0x1

 Section to Segment mapping:
  Segment Sections...
   00     .note.ABI-tag .note.gnu.build-id .rela.plt .init .plt .text __libc_freeres_fn __libc_thread_freeres_fn .fini .rodata .stapsdt.base .eh_frame .gcc_except_table
   01     .tdata .init_array .fini_array .data.rel.ro .got .got.plt .data __libc_subfreeres __libc_IO_vtables __libc_atexit __libc_thread_subfreeres .bss __libc_freeres_ptrs
   02     .note.ABI-tag .note.gnu.build-id
   03     .tdata .tbss
   04
   05     .tdata .init_array .fini_array .data.rel.ro .got
```
从上面输出可以明确看到哪些 section 被分配到了同一个 segment，然后被装载（LOAD）进虚拟内存。

所以 section 是从链接视图（Linking View）来看 elf 文件的，而 segment 是从执行视图（Execution View）来看elf文件的。

## segment数据结构
  描述segment是由数据结构程序头表（Program Header Table）来完成的。
- **目标文件不需要被装载，所以没有程序头表，而ELF可执行文件和共享文件都有**
  
``` c
  typedef struct
  {
    Elf64_Word	p_type;			/* Segment type */
    Elf64_Word	p_flags;		/* Segment flags */
    Elf64_Off	  p_offset;		/* Segment file offset */
    Elf64_Addr	p_vaddr;		/* Segment virtual address */
    Elf64_Addr	p_paddr;		/* Segment physical address */
    Elf64_Xword	p_filesz;		/* Segment size in file */
    Elf64_Xword	p_memsz;		/* Segment size in memory */
    Elf64_Xword	p_align;		/* Segment alignment */
  } Elf64_Phdr;
```
- 其中 `p_memsz` 是可能大于 `p_filesz` 的，比如数据段和 BSS 段合并为一个`segment`时，BSS 不会占用文件的空间，但是在虚拟内存中则会实际占用空间。

## 堆和栈
vma 除了映射 elf 以外，还会映射执行时用到的堆和栈，一个进程的堆栈查看方式[在此](http://kcmetercec.top/2018/06/17/linux_memory_overview_consume/#org0fb19a4)。

## 进程栈初始化
在启动进程前，操作系统会将该进程的环境变量、输入参数压入栈。

对应 c 代码中 main 会获得栈中的参数信息。

---
title: '[What] compiler -> 常用命令'
tags: 
- compiler
date:  2018/11/16
categories: 
- program
- compiler
layout: true
---

整理 linux 下编译链接相关的命令，避免遗忘。

<!--more-->

# 编译
- `gcc -E hello.c -o hello.i` / `g++ -E hello.cc -o hello.ii`
  + `-E`表示只进行预编译，可以用于验证当前代码预编译后的结果。
- `gcc -S hello.i -o hello.s` / `g++ -S hello.ii -o hello.s`
  + 注意此处是大写的`-S`，也可以直接从源文件`-S`到汇编文件。
- `gcc -c hello.s -o hello.o` / `g++ -c hello.s -o hello.o`
  + 也可以直接从源文件一步到位到目标文件

- `gcc -c -fleading-underscore hello.c` ：默认符号不带下划线，使用此选项后会加上下划线

标文件                                    |
|         |                            |
| gcc -c -fno-common hello.c                 | 把所有未初始化的全局变量不以COMMON块的形式处理                         |
| gcc -c -ffunction-sections -fdata-sections | 将数据和代码都单独分段，以在链接时将未使用的代码移除目标文件，减小大小 |
| gcc -c -fno-builtin hello.c                | 关闭内置函数优化选项                                                   |
| ld -T <link_script>                        | 指定链接脚本                                                           |
| gcc -fPIC -shared -o hello.so hello.c      | 以位置无关码的形式生成动态链接库                                       |
| gcc -c hello.c -la -o hello.o              | 链接动态库 liba.so , 加上参数 -static 表示链接静态库                   |

# 查看
- `file <file_name>` ： 查看文件是哪些类型 
- `size <file_name>` ：查看目标文件 text 段、数据段、bss 段的大小
- `objdump -h <file_name>`：查看目标文件关键段表整体描述
- `objdump -s -d <file_name>`：将所有的段以 16 进制打印并反汇编代码段
- `objcopy -I binary -O elf32-i386 -B i386 <input_file> <output_name>.o`：将文件转换为 i386 格式的目标文件 
- `readelf -h <file_name>` ：读取ELF文件头
- `readelf -S <file_name>`：显示elf文件的完整段表 （注意是大写的 S）
- `nm <filename>`/`readelf -s <file_name>`：显示 elf 文件的符号表

| objdump -r <file_name>                                               | 查看目标文件的重定位表      
| readelf -l <file_name>                                               | 查看elf文件的segment，了解映射到虚拟地址空间的结构 |
| readelf -d <file_name>.so                                            | 查看动态链接文件头(.dynamic 段)                    |
| readelf -sD <file_name>.so                                           | 查看动态链接文件符号哈希表                         |
| readelf --dyn-syms <file_name>.so                                    | 查看动态链接文件的动态符号表                       |
| ar -t <lib_name>.a                                                   | 查看静态库所包含哪些目标文件                       |
| ar -x <lib_name>.a                                                   | 解压静态库中的目标文件                             |
| ld -verbose                                                          | 查看链接器的默认链接脚本                           |
| ldd <file_name>                                                      | 查看程序主模块或共享库依赖于哪些共享库             |

- =readelf -d <filename>.so | grep TEXTREL= : 若无任何输出，代表此动态链接库是位置无关码的形式
- =readelf -l <filename> | grep interpreter= : 查看可执行文件动态连接器路径


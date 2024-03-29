---
title: Kconfig 基本使用
tags: 
 - linux
categories:
 - linux
 - kernel
 - make
date: 2023/8/19
updated: 2023/8/19
layout: true
comments: true
---

u-boot 或者 Linux 在进行配置内核时，其调用步骤如下:

1. `make ARCH=<arch> <xxx_defconfig> menuconfig` 
   - ARCH : 指定要配置的构架
   - <xxx_defconfig> : 指定默认的参考配置,比如arm默认配置位于 `arch/arm/configs/` 
     + 一般都可以参考这些配置，不然内核的配置项太多了。比如 `make ARCH=arm s3c2410_defconfig menuconfig`
2. 配置工具都会提取 `./Kconfig` 文件,此文件 `source` 读取 `arch/${ARCH}/Kconfig`
3. `arch/${ARCH}/Kconfig` 再source其他文件夹下的 `Kconfig` ,层层调用来完成整个界面的映射.配置界面的显示,也是对应层层显示的.
4. 在完成配置后，在内核根目录下会生成文件 .config(新配置) 和 .config.old(之前配置)，用户根据查看这两个文件可以以一个全局视野查看内核配置以及相对上次修改的配置

经过上面的配置，然后分别编译内核文件和模块文件:

1. `make ARCH=<arch> CROSS_COMPILE=<arm-gcc> zImage` :编译内核文件(比如 `make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage`)
   + 编译完成后，在内核根目录会有未压缩的 `vmlinux` 和符号表 `System.map`,以及在 `arch/xxx/boot/` 目录下会有已经压缩的zImage
2. `make ARCH=<arch> CROSS_COMPILE=<arm-gcc> modules` : 编译内核模块
   + 内核模块对应的存在于其源码的路径中
   + 为了便捷的将编译的模块安装在文件系统，一般还会执行 `make modules_install` ，默认会安装在目标文件系统的 `/lib/modules/$(KERNELRELEASE)`

<!--more-->

# 菜单入口

最基本的一个配置如下:r4

```shell
config MODVERSIONS
       bool "Set version information on all module symbols"
       depends on MODULES
       help
            Usually, modules have to be recompiled whenever you switch to a new kernel....
```

每一行都由一个关键字做起始,后面可以跟多个参数。 

"config"代表一个新的配置选项，后面的缩进行则是这个配置的属性。

属性可以是配置类型，输入提示，依赖，帮助信息，默认值等等。
多个"config" 后面可以跟相同的名字,但必须保证它们的输入提示是一样的，并且类型也不能起冲突。

config 后的名称 `MODVERSIONS` 在编译过程中其实是 `CONFIG_MODVERSIONS`。

# 菜单属性

一个菜单可以具有多个属性,但不是每个属性都可以同时使用。

## type (类型)

使用: `bool "string"`

| 类型       | 值         |
| -------- | --------- |
| bool     | y / n     |
| tristate | y / n / m |
| string   | 字符串       |
| hex      | 0x\*\*    |
| int      | \*\*      |

此类型的值也就是 `CONFIG_MODVERSIONS` 的值， `tristate` 和 `string` 是基本类型，其他类型都是由它们演化出来的。

type 类型后跟的字符串是一个输入提示字符.。

```shell
bool "Networking support"

# 等价于

bool
prompt "Networking support"
```

## input prompt (输入提示)

使用: `prompt "string" [if <expr>]`

每个菜单只能有 **一个** 提示信息, `if` 用于在依赖项使能的情况下,才显示这条提示.

## default (默认值)

使用: `default <expr> [if <expr>]`

每个菜单可以有多个默认值,但真正起作用的只有第一个, `if` 用于在依赖项使能的情况下,才使用这个默认值.

## type + default (默认类型及默认值)

使用: `def_bool / def_tristate <expr> [ if <expr> ]`

这是一种简单的写法, `if` 用于在依赖项使能的情况下,才使用这个值

## dependencies (依赖)

使用: `depends on <expr>`

表示只有依赖的菜单使能了,这个菜单才会显示.当有多个依赖时, 使用 `&&` 连接.

```shell
bool "foo" if BAR
default y if BAR

# 等价于

depends on BAR
bool "foo"
default y
```

在 depends on 中,当 A 依赖于 B ,则 A 的值有如下几种情况.

| B 的值 | A 的 值     |
| ---- | --------- |
| Y    | Y / M / N |
| M    | M / N     |
| N    | N         |

## reverse dependencies (反向依赖)

使用: `select <symbol> [if <expr>]`

相比于 `depends on`，反向依赖规定菜单值的下限。

在 select 中,当 A 反向依赖于B ,则 B 的值有以下几种情况

| A 的值 | B 的值      |
| ---- | --------- |
| N    | N / M / Y |
| M    | M / Y     |
| Y    | Y         |

当 select 有多个值时，则下限值是这些值中的最大值。

## weak reverse dependencies: (反向弱依赖)

使用: `imply <symbol> [if <expr>]`

imply 使得 symbol 在任何时候都可以设置为 N.

```shell
config FOO
       tristate
       imply BAZ

config BAZ
       tristate
       depends on BAR
```

| FOO | BAR | BAZ 的默认值 | BAZ 可以设定的值 |
| --- | --- | -------- | ---------- |
| n   | y   | n        | N / M / Y  |
| m   | y   | m        | N / M / Y  |
| y   | y   | y        | Y / N      |
| y   | n   | \*       | N          |

当一个驱动可以应用于多个组件时，可以关闭其中一个或多个，而不用关闭驱动。

## limiting menu display (菜单限制信息)

使用: `visible if <expr>`

此属性只能在菜单块中使用,当 expr 为 true 则此菜单块显示,否则隐藏

## numerical ranges (数字输入范围)

使用: `range <symbol> <symbol> [if <expr>]`

用于限制 int 或 hex 的输入范围

## help text (帮助信息)

使用: `help 或者 ---help---`

## misc options (其他依赖属性)

使用: `option <symbol> [=<value>]`

- defconfig_list : 默认值列表
- modules : 
- env=<value> : 设置环境变量的值
- allnoconfig_y : 

# 依赖关系表达式

```shell
<expr> ::= <symbol>                       (1)
           <symbol> ’=‘ <symbol>          (2)
           <symbol> ’!=‘ <symbol>         (3)
           ’(‘<expr>’)’                   (4)
           ‘!‘<expr>                      (5)
           <expr> ’&&‘ <expr>             (6)
           <expr> ’||‘ <expr>             (7)
```

1. 将 symbol 值赋值给 expr ,bool 和 tristate 类型直接赋值,其他类型值为 n.
2. 如果两个 symbol 的值相等, 则返回 y ,否则为 n
3. 如果两个 symbol 的值不等, 则符号 y, 否则为 n
4. 返回表达式的值
5. 返回非 expr 的结果
6. 返回两个 expr 与运算
7. 返回两个 expr 或运算

表达式的值可以为 n, m和 y。当表达式的值为 m 或 y 时，菜单可见。

symbol 有两种类型，一种是常数型，一种是非常数型。

非常数型由 config 关键字定义，由 字母，数字，下划线组成。常数 symbol 总是用単引号或者双引号括起来，内部可以使用转义字符。

# 菜单结构

一个 Kconfig 文件的两头包含 menu 和 endmenu,这样就形成了一个菜单块.

```shell
menu "Network device support"
     depends on NET

config NETDEVICES

endmenu
```

如上所示, 在 menu 和 endmenu 之间的菜单都会成为 `Network device support` 的子菜单,只有 NET 打开时,这个菜单块才可见。

# 语法

配置文件就是由很多小的菜单项组合而成的,每一行都由一个关键字做起始。

- config

```shell
config <symbol>
<config options>
```

- menuconfig

```shell
menuconfig <symbol>
<config options>
```

menuconfig 表示它下面的选项都是它的子选项.

```shell
(1);
menuconfig M
if M
   config C1
   config C2
endif

(2):
menuconfig M
config C1
       depends on M
config C2
       depends on M
```

- choice/endchoice

```shell
choice [symbol]
<choice options>
<choice block>
endchoice
```

用 choice 来生成一个可选的列表,当一个硬件有多种驱动时,这种方法比较适用。

- comment

```shell
comment <prompt>
<comment options>
```

在图形界面中显示一定的注释.

- if/endif

```shell
if <expr>
<if block>
endif
```

当 expr 为真时, block 中的选项才显示.

- source

```shell
source <prompt>
#+end_example
```

- mainmenu

```shell
mainmenu <prompt>
```

显示在配置界面的最上方,如同标题一样.

# 技巧

## 限制某些选项只能备编译为模块

```shell
config FOO
       depends on BAR && m
```

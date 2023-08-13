---
title: 使用Grabserial来检测代码运行时间
tags: 
 - linux
categories:
 - linux
 - kernel
 - debug
date: 2023/8/10
updated: 2023/8/10
layout: true
comments: true
---

[Grabserial](https://elinux.org/Grabserial) 是一个串口监视工具，其最大的特色在于：可以监视每一行串口输出的时间和相对上一行串口输出的时间差。

基础此功能，我们可以推导出使用此工具可以完成以下调试工作：

1. 检查系统启动的完整时间（Linux，RT-thread...）
2. 检查特定一段代码的运行时间(比如调试应用程序的算法效率)

> `minicom` 使用 `CTAL + a + n` 也可以打开时间戳模式，但是最多只能精确到 1ms 并且没有时间差的显示

<!--more-->

# 安装

``` shell
# 拷贝库
git clone https://github.com/tbird20d/grabserial
cd grabserial
# 安装
sudo python setup.py install
```

# 使用

grabserial 的默认配置为：

- 端口号： /dev/ttyS0
- 波特率： 115200
- 8位数据位且无停止位

所以一般情况下在传输协议上的设置只需要设置端口号即可。

其输出格式为： [绝对时间][相对上一行的时间] 串口内容

**以下命令都比较长，建议常用的命令可以使用 alias命令封装一次。**

##  持续捕捉输出

``` shell
# -v 显示详细信息
# -d 设置端口
# -t 显示每一行的时间
sudo grabserial -v -d /dev/ttyUSB0 -t
```

使用上面的命令 grabserial 将会一直捕捉标准输出，使用 `CTRL+C` 退出。

## 捕捉系统的启动时间

``` shell
# -v 显示详细信息
# -d 设置端口
# -t 显示每一行的时间
# -e 持续捕捉多少秒
# -m 当匹配到指定字符串后，清零时间重新计时(字符串使用正则表达式)
sudo grabserial -v -d /dev/ttyUSB0 -e 30 -t -m "^Linux version.*"
```

## 捕捉两段特定输出之间的时间差

**注意：** 此命令需要字符串输出在同一行

``` shell
# -v 显示详细信息
# -d 设置端口
# -t 显示每一行的时间
# -i 一行中的停止字符串(字符串使用正则表达式)
# 此行命令用户捕捉Linux内核的解压缩时间
sudo grabserial -v -d /dev/ttyUSB0 -e 30 -t -m "Uncompressing Linux" -i "done,"
```

# 关于网络数据的时间截取

有的时候需要截取通过网络发送过来信息的时间戳，对此有两个解决方案：

1. 通过分析 grabserial 的代码，为其添加连接 socket 的代码
2. 通过 secure CRT 的日志时间戳功能粗略的计算
  + 此方法无法显示时间戳的相对值

## 通过secure CRT 来截取

在 `Session Optons -> Log File` 中依次做如下设置：

- 在 `Log file name` 来设置输出日志文件名
- 选中 `Start log upon connect` 选项
- 在 `On each line:` 条目中输入 "%h:%m:%s(%t):" (去掉引号) 以显示时:分:秒:(毫秒)
- 然后重新连接服务器即可

关于时间戳可以用的格式如下(更多的信息需查看其help文件)：

``` shell
  %H - hostname

  %S - session name

  %Y - four-digit year

  %y - two-digit year

  %M - two-digit month

  %D - two-digit day of the month

  %P - port

  %h - two-digit hour

  %m - two-digit minute

  %s - two-digit seconds

  %t - three-digit milliseconds

  %% - percent (%)

  %envvar% - environment variable
```

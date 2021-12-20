---
title: ERPC 使用体验
tags: 
- framework
categories:
- framework
- ERPC
date: 2021/12/18
updated: 2021/12/18
layout: true
comments: true
---

在没有使用 [RPC](https://zh.wikipedia.org/wiki/%E9%81%A0%E7%A8%8B%E9%81%8E%E7%A8%8B%E8%AA%BF%E7%94%A8) 之前，那就需要程序员自己来完成两个进程（芯片）之间的通信。无论是对于发射端还是接收端，其逻辑都类似如下：

1. 发送端根据制定的传输格式传输二进制流
2. 接收端根据接收到的二进制流，以状态机的方式依次分解二进制流的内容
3. 最终将解析出来的命令和数据与对应的处理程序进行关联调用

人为实现这个过程比较繁琐：

1. 发射端和接收端可能会存在大小端的问题，这需要单独处理
2. 如果代码架构不好，那么换一个底层通信协议便会导致又需要重新实现一次这个过程
3. 长期维护起来比较麻烦，尤其是存在多个进程（芯片）之间通信时
4. 发射端和接收端存在同步和异步调用关系，人为实现较为麻烦

而有了 RPC 框架，便可以以函数调用的方式来实现多个进程（芯片）之间的通信，通信细节对于程序员来讲就是透明的。程序员便可以专注于上层业务逻辑，提高开发效率。

相比较于代码量庞大的 [grpc](https://grpc.io/)，[ERPC](https://github.com/EmbeddedRPC/erpc) 更适合于嵌入式通信的应用场景，我们先来体验一下它。

<!--more-->

# 获取代码并打补丁

## 安装依赖

EPRC 的工具需要一些依赖库才可以工作，所以需要先安装依赖：

```shell
sudo apt install -y flex bison libboost-dev libboost-system-dev libboost-filesystem-dev
```

## 获取代码

ERPC 主要分为 `Master` 和 `develop` 两个分支，在 clone 代码以后，首先需要切换到 `Master` 分支：

```shell
$ git clone https://github.com/EmbeddedRPC/erpc.git
$ cd erpc/
$ git checkout master
```

## BUG 修复

虽然这 `Master` 分支是最新的 1.8.1 版本，但由于其存在重复定义 BUG，所以需要修复该问题。按照这个 [Pull request](https://github.com/EmbeddedRPC/erpc/pull/180/files/71d0063d1c13562df961df39331020624c516bfd) 进行修复即可。

# 编译并安装

编译和安装步骤倒是轻车熟路了：

```shell
$ make -j8
$ sudo make install
```

安装完成后，安装路径位于：

```shell
Installing headers in /usr/local/include/erpc
Installing liberpc.a in /usr/local/lib
Installing erpcgen in /usr/local/bin
Installing erpcsniffer in /usr/local/bin
```

# 编写 demo

## 定义 IDL 文件

IDL 文件用于定义客户端和服务端通信的接口，下面建立一个简单的文件 `erpcdemo.erpc` ：

```cpp
// 定义工程的名字，后面生成的文件就会以这个名字作为前缀
program erpcdemo

// 定义一个接口
interface DEMO {
    // 这里表示可调用函数 DemoHello 输入类型是 binary，输出类型也是 binary
    DemoHello(binary val) -> binary
}
```

接下来便是生成对应的文件：

```shell
$ erpcgen erpcdemo.erpc
```

便会生成下面 4 个文件：

```shell
erpcdemo.h
erpcdemo_client.cpp
erpcdemo_server.cpp
erpcdemo_server.h
```

对于客户端而言，需要包含`erpcdemo.h`，`erpcdemo_client.cpp`文件。

对于服务端而言，需要包含`erpcdemo_server.cpp`，`erpcdemo_server.h`文件。

## 提供 TCP 通信实例

由于 ERPC 默认编译方式并没有把创建 TCP 实例的代码包含进库中，所以我们需要将 `erpc_c/setup/erpc_setup_tcp.cpp` 复制到当前测试文件夹下。

## 实现服务端

服务端用于创建连接并实现接口：

```cpp
/**
 * @file: test_erpcdemo_server.cpp
 */
#include <cstdlib>

#include <iostream>
#include <string>

#include <erpc_server_setup.h>
#include <erpc_transport_setup.h>

#include "erpcdemo_server.h"

static const char* ret = "Hello, this is server!\n";

binary_t * DemoHello(const binary_t * val) {
    std::cout << "client message: " << (char*)val->data;

    int len = std::strlen(ret) + 1;
    char* buf = (char*)std::malloc(len);
    std::strncpy(buf, ret, len - 1);

    binary_t* message = new binary_t{(uint8_t*)buf, (uint32_t)(len - 1)};

    return message;
}

int main(int argc, char *argv[]) {
    // 创建服务端
    auto transport = erpc_transport_tcp_init("127.0.0.1", 60901, true);
    // 建立消息缓存
    erpc_mbf_t message_buffer_factory = erpc_mbf_dynamic_init();
    // 初始化服务端对象
    erpc_server_init(transport, message_buffer_factory);
    // 将当前服务端加入事件检测机制
    erpc_add_service_to_server(create_DEMO_service());

    std::cout << "server is running!\n";
    // 启动服务
    erpc_server_run();
    // 当客户端退出后，服务端也主动退出
    erpc_transport_tcp_close();

    return 0;
}
```

## 实现客户端

客户端就是与服务端连接，并调用接口：

```cpp
/**
 * @file: test_erpcdemo_client.c
 *
 */

#include <iostream>
#include <string>

#include <erpc_client_setup.h>
#include <erpc_port.h>
#include <erpc_transport_setup.h>

#include "erpcdemo.h"

int main(int argc, char *argv[]) {
    // 创建客户端
    auto transport = erpc_transport_tcp_init("127.0.0.1", 60901, false);
    // 初始化消息缓存
    auto message_buffer_factory = erpc_mbf_dynamic_init();
    // 加入消息
    erpc_client_init(transport, message_buffer_factory);

    auto message = "Hello, this is client!\n";
    binary_t cmd{(uint8_t*)message, (uint32_t)(std::strlen(message))};

    std::cout << "Get message of server: " << DemoHello(&cmd)->data << "\n";
    // 关闭连接
    erpc_transport_tcp_close();

    return 0;
}
```

## 编写 Makefile

Makefile 比较简单，如下：

```makefile
INCLUDE = /usr/local/include/erpc
LIBRARY = /usr/local/lib

all:
        g++  test_erpcdemo_client.cpp erpcdemo_client.cpp erpc_setup_tcp.cpp -I${INCLUDE} -L${LIBRARY} -lerpc -lpthread -o client
        g++  test_erpcdemo_server.cpp erpcdemo_server.cpp erpc_setup_tcp.cpp -I${INCLUDE} -L${LIBRARY} -lerpc -lpthread -o server
```

## 运行

服务端输出：

```shell
server is running!
client message: Hello, this is client!
```

客户端输出：

```shell
Get message of server: Hello, this is server!
```


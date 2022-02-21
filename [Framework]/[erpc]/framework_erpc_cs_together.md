---
title: ERPC 同时运行一个服务端和客户端
tags: 
- framework
categories:
- framework
- ERPC
date: 2021/12/20
updated: 2022/2/21
layout: true
comments: true
---

在使用 EPRC 进行 TCP 通信的过程中，如果需要同时运行一个客户端和服务端就会出现异常。

这是因为其提供的 `erpc_setup_tcp.cpp` 只能初始化一个实例，那就需要对其进行理解并修改。

<!--more-->

# EPRC 能否支持在运行服务端的时候运行客户端？

从理论上来讲，服务端和客户端都维护自己对应的端口，读写数据都走自己的端口即可，互不相干。

从 ERPC 的 API 可以看到，服务端和客户端创建的代码是不一样的：

```cpp
/*!
 * @brief This function initializes client.
 *
 * @param[in] transport Initiated transport.
 * @param[in] message_buffer_factory Initiated message buffer factory.
 *
 * This function initializes client with all components necessary for serve client request.
 */
void erpc_client_init(erpc_transport_t transport, erpc_mbf_t message_buffer_factory);
/*!
 * @brief This function initializes server.
 *
 * This function initializes server with all components necessary for running server.
 *
 * @return Server object type.
 */
erpc_server_t erpc_server_init(erpc_transport_t transport, erpc_mbf_t message_buffer_factory);
```

那么应该是可以将二者区分开来应用的。

# `erpc_setup_tcp.cpp` 的更改

在 `erpc_setup_tcp.cpp` 中，其使用 `s_transport` 来对 TCP 对象进行创建，但是模板类中的私有成员对象仅能存储一个对象元素：

```cpp
/*!
 * @brief Storage for the object.
 *
 * An array of uint64 is used to get 8-byte alignment.
 */
uint64_t m_storage[(sizeof(T) + sizeof(uint64_t) - 1) / sizeof(uint64_t)];
```

如果我们要同时使用一个服务端和客户端，就需要调用 `erpc_transport_tcp_init` 函数两次以创建两个对象，所以这里就需要对其进行更改：

```cpp
/*
 * Copyright 2020 (c) Sierra Wireless
 * Copyright 2021 ACRIOS Systems s.r.o.
 * All rights reserved.
 *
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "erpc_manually_constructed.h"
#include "erpc_tcp_transport.h"
#include "erpc_transport_setup.h"

using namespace erpc;

////////////////////////////////////////////////////////////////////////////////
// Variables
////////////////////////////////////////////////////////////////////////////////

static ManuallyConstructed<TCPTransport> s_transport[2];
// 新增加标记来避免多次调用该函数
static bool initialized[2];

////////////////////////////////////////////////////////////////////////////////
// Code
////////////////////////////////////////////////////////////////////////////////

erpc_transport_t erpc_transport_tcp_init(const char *host, uint16_t port, bool isServer)
{
    erpc_transport_t transport;

    // we can only initialize once
    if (initialized[isServer]) {
        return NULL;
    }

    // 通过 isServer 的值来区分是客户端还是服务端
    s_transport[isServer].construct(host, port, isServer);
    if (kErpcStatus_Success == s_transport[isServer]->open())
    {
        transport = reinterpret_cast<erpc_transport_t>(s_transport[isServer].get());
        initialized[isServer] = true;
    }
    else
    {
        transport = NULL;
    }

    return transport;
}

void erpc_transport_tcp_close(void)
{
    if (initialized[false]) {
        s_transport[false].get()->close(true);
        initialized[false] = false;
    }
    if (initialized[true]) {
        s_transport[true].get()->close(true);
        initialized[true] = false;
    }
}
```

# 修改及验证

其实我们只需要在 [上一篇 demo](http://kcmetercec.top/2021/12/18/framework_erpc_demo/) 的基础之上，再增加一个服务端，来接收原来服务端的数据即可验证。

## 新服务端的 IDL 文件

新服务端的 IDL 文件 `erpcserver.erpc` 依然很简单：

```cpp
// 定义工程的名字，后面生成的文件就会以这个名字作为前缀
program erpcserver

// 定义一个接口
interface SERVER {
    // 这里表示可调用函数 ServerHello 输入类型是 int32，无输出类型
    oneway ServerHello(int32 val)
}
```

然后再按照之前的方式生成文件即可。

## `test_erpcdemo_server.cpp`

原服务端也需要增加初始化客户端的代码：

```cpp
/**
 * @file: test_erpcdemo_server.cpp
 */
#include <cstdlib>

#include <iostream>
#include <string>

#include <erpc_client_setup.h>
#include <erpc_server_setup.h>
#include <erpc_transport_setup.h>

#include "erpcdemo_server.h"
#include "erpcserver.h"

static const char* ret = "Hello, this is server!\n";

binary_t * DemoHello(const binary_t * val) {
    std::cout << "client message: " << (char*)val->data;

    int len = std::strlen(ret) + 1;
    char* buf = (char*)std::malloc(len);
    std::strncpy(buf, ret, len - 1);
    
    binary_t* message = new binary_t{(uint8_t*)buf, (uint32_t)(len - 1)};

    // 给另一个服务端发数据
    ServerHello(-123456);

    return message;
}

int main(int argc, char *argv[]) {
    // 创建客户端
    auto transport1 = erpc_transport_tcp_init("127.0.0.1", 60902, false);
    // 初始化消息缓存
    auto message_buffer_factory1 = erpc_mbf_dynamic_init();
    // 加入消息
    erpc_client_init(transport1, message_buffer_factory1);

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

## `test_erpcserver_server.cpp`

```cpp
/**
 * @file: test_erpcserver_server.cpp
 */
#include <cstdlib>

#include <iostream>
#include <string>

#include <erpc_server_setup.h>
#include <erpc_transport_setup.h>

#include "erpcserver_server.h"

void ServerHello(int32_t val) {
    std::cout << "I get value from client: " << val << "\n";
}

int main(int argc, char *argv[]) {
    // 创建服务端
    auto transport = erpc_transport_tcp_init("127.0.0.1", 60902, true);
    // 建立消息缓存
    erpc_mbf_t message_buffer_factory = erpc_mbf_dynamic_init();
    // 初始化服务端对象
    erpc_server_init(transport, message_buffer_factory);
    // 将当前服务端加入事件检测机制
    erpc_add_service_to_server(create_SERVER_service());

    std::cout << "server2 is running!\n";
    // 启动服务
    erpc_server_run(); 
    // 当客户端退出后，服务端也主动退出
    erpc_transport_tcp_close();

    return 0;
}
```

## NESTED_CALLS_DETECTION

`NESTED_CALLS_DETECTION` 宏是用于检测在服务端的函数被调用期间，是否又进行了其他接口函数的调用。这个宏默认是使能的。
> 服务端生成的自动代码中，会先后设置变量 `nestingDetection` 的值为 `true` 和 `false`，以检测这期间是否有嵌套调用。

而如果我们修改当前代码到客户端和服务端同时使用时，便会给这个宏带来误导，导致客户端的调用函数可能会返回失败 `kErpcStatus_NestedCallFailure`。

所以这里要在文件 `erpc_config.h` 中关闭该宏。

## 修改 Makefile

原服务端既是客户端也是服务端，且我们也新增了代码，所以需要修改如下：

```makefile
INCLUDE = /usr/local/include/erpc
LIBRARY = /usr/local/lib

all:
	g++  test_erpcdemo_client.cpp erpcdemo_client.cpp erpc_setup_tcp.cpp -I${INCLUDE} -L${LIBRARY} -lerpc -lpthread -o client
	g++  test_erpcdemo_server.cpp erpcdemo_server.cpp erpcserver_client.cpp erpc_setup_tcp.cpp -I${INCLUDE} -L${LIBRARY} -lerpc -lpthread -o server
	g++  test_erpcserver_server.cpp erpcserver_server.cpp erpc_setup_tcp.cpp -I${INCLUDE} -L${LIBRARY} -lerpc -lpthread -o server2
```

## 验证

可以看到已经正常运行了：

新服务端：

```shell
$ ./server2
server2 is running!
I get value from client: -123456
```

原服务端：

```shell
$ ./server
server is running!
client message: Hello, this is client!
```

原客户端：

```shell
$ ./client
Get message of server: Hello, this is server!
```

# 总结

其实在 ERPC 源码中存在着不少静态全局变量，这是代码中的 Bad smell，这些对象应该是能够被动态的创建和销毁的。

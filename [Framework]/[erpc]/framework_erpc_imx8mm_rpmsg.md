---
title: IMX8MM 使用 ERPC 结合 rpmsg 完成 A53 和 M4 的通信
tags: 
- framework
categories:
- framework
- ERPC
date: 2021/12/21
updated: 2021/12/23
layout: true
comments: true
---

NXP 官方提供了 M4 和 A53 通信的 demo，但是仅仅是演示作用：
- M4 端仅使用 rpmsg 与 A53 进行通信，没有 ERPC 封装
- A53 端将 rpmsg 操作暴露成了一个 tty 设备，仅适合 `echo` 演示，不适合编写代码完成通信
- 需要在 rpmsg 的基础上进行 ERPC 封装

那么完成的步骤就是：
1. 完成用户态代码实现与 M4 进行 rpmsg 通信
2. 对 rpmsg 进行 ERPC 封装

<!--more-->

# `rpmsg_char` 驱动

内核文件 `drivers/rpmsg/rpmsg_char.c` 驱动，可以将 rpmsg 相关操作暴露在用户空间的 `/dev/rpmsg_ctrlX` 路径中。

用户可以操作 `/dev/rpmsg_ctrlX` 文件，以创建对应通信端口。

## 打补丁

kernel 主线的代码对 `rpmsg_char` 的支持不够完善，所以我们需要先应用[这个补丁](https://lwn.net/Articles/743115/)，以完成对通信端口动态的创建。

## 使能

在 menuconfig 路径 `Device Drivers -> Rpmsg drivers` 确认 `RPMSG device interface`使能。

> 使能后，`Enable Virtio RPMSG char device driver support` 也会默认使能。

启动新编译的内核后，便可以看到 rpmsg 的控制设备 `/dev/rpmsg_ctrl0`。

# 编写用户态代码

## 流程
对应的头文件位于 `include/uapi/linux/rpmsg.h`，根据该头文件及其代码可以看出应用流程为：
1. 首先使用 `ioctl()` 操作 `/dev/rpmsg_ctrl0` 设备，发送命令 `RPMSG_CREATE_EPT_IOCTL` 来创建一个端口。
2. 操作端口 `/dev/rpmsgX` ，使用 `read()`,`write()` 系统调用完成对端口的读写操作
3. 对端口 `/dev/rpmsgX`，使用 `ioctl()`，发送命令 `RPMSG_DESTROY_EPT_IOCTL` 来销毁该端口

在创建端口设备时，需要填充结构体 `rpmsg_endpoint_info`:
 ```cpp
/**
 * struct rpmsg_endpoint_info - endpoint info representation
 * @name: name of service
 * @src: local address
 * @dst: destination address
 */
struct rpmsg_endpoint_info {
    char name[32];
    uint32_t src;
    uint32_t dst;
};
```
这里面填充的值，需要根据 M4 端创建的服务端而定。

在使用 NXP 所提供的 `imx_rpmsg_tty.c` 驱动中，其输出：
```shell
imx_rpmsg_tty virtio0.rpmsg-virtual-tty-channel-1.-1.30: new channel: 0x400 -> 0x1e!
```
也就是说，其对应：
- name：`rpmsg-virtual-tty-channel-1`
- src：`0x400`
- dst：`0x1e`

## 编写及测试
有了上面的基础，那就可以写一个简单的测试程序了：
```cpp
/**
 * file: rpmsg_test.c
 * author: kcmetercec (kcmeter.cec@gmail.com)
 */ 

#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>


#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <linux/rpmsg.h>

#define DEVICE_CONTROL_NAME		"/dev/rpmsg_ctrl0"
#define DEVICE_EP_NAME			"/dev/rpmsg0"

#define READ_BUF_SIZE	(128)


int main(int argc, char* argv[]) {
	if (argc != 2) {
		printf("usage: %s <send command>\n", argv[0]);

		return 1;
	}

	int control_device_fd = open(DEVICE_CONTROL_NAME, O_RDWR);
	if (control_device_fd == -1) {
		perror("Can't open control device: ");

		return 1;
	}

	struct rpmsg_endpoint_info ep_info = {
		.name = "rpmsg-virtual-tty-channel-1",
		.src = 0x400,
		.dst = 0x1e,
	};

	if (ioctl(control_device_fd, RPMSG_CREATE_EPT_IOCTL, &ep_info)) {
		perror("Can't create endpoint:");

		return 1;
	}

	int ep_fd = open(DEVICE_EP_NAME, O_RDWR);
	if (ep_fd == -1) {
		perror("Can't open endpoint device: ");

		return 1;
	}	

	int write_size = strlen(argv[1]);

	ssize_t ret = write(ep_fd, argv[1], write_size);
	if (ret != write_size) {
		perror("write failed:");

		return 1;
	}

	char read_buf[READ_BUF_SIZE];

	ret = read(ep_fd, read_buf, READ_BUF_SIZE);
	if (ret < 0) {
		perror("read failed:");
	} else if(ret == 0) {
		printf("read end of file.\n");
	} else {
		read_buf[READ_BUF_SIZE - 1] = '\0';
		printf("read from m4: %s\n", read_buf);
	}


	if (ioctl(ep_fd, RPMSG_DESTROY_EPT_IOCTL)) {
		perror("Can't destroy endpoint:");
	}

	close(ep_fd);
	close(control_device_fd);

	return 0;
}
```
通过以上简单的代码，便可以完成与 M4 的回环测试了。

# EPRC 封装

在 M4 和 A53 通信的过程中，M4 是作为服务端（remote）而存在的，而 A53 是作为客户端（master）而存在的。

## 服务端实现

查看当前 ERPC 的代码，其已经具备了 `erpc_transport_rpmsg_lite_rtos_remote_init()` 函数，其创建的实例是 `RPMsgRTOSTransport` 类。

`RPMsgRTOSTransport` 类已经实现了直接使用 `rpmsg_lite` 库的创建、读、写函数，所以对于 M4 而言，只需要将 ERPC 库移植到其代码中即可。

## 客户端实现

客户端则是使用 `rpmsg_char` 接口完成的数据读写，所以这里需要我们自己实现一个 transport 类以及对应的 setup 函数。

### 编译无法通过的坑

在将 ERPC 源码移植到 M4 工程中时，会有如下类似警告：

```shell
MIMX8MM6_cm4.h:6371:51: error: 'reinterpret_cast<CCM_Type*>(808976384)' is not a constant expression
```
这个警告造成的原因是有如下代码：

```cpp
// ...
#define CCM_BASE (0x30380000u)
#define CCM ((CCM_Type*)CCM_BASE)
// ...

typedef enum _clock_root_control
{
    kCLOCK_RootM4 = (uint32_t)(&(CCM)->ROOT[1].TARGET_ROOT),
    // ...
} clock_root_control_t;
```
注意看，**这是一个枚举类型**。

C++ 标准规定，枚举类型的值必须是常量表达式，而 `CCM` 宏的实现方式由 c++ 编译器解释就是使用 `reinterpret_cast` 对指针进行从新解释。那就是说它不是一个常量表达式，这就会造成编译时报错。

所以，为了解决这个报错，就需要将这行代码替换为常量表达式。

这个代码的意义就是为了获取 `CCM` 空间下 `ROOT[1].TARGET_ROOT` 处所在的地址，地址以整型表示。

而 C/C++ 提供了宏 `offsetof` 来以常量的方式计算地址偏移：

```cpp
#include <stddef.h>
#define offsetof(type, member)
```
那么上面的枚举就可以修改为：

```cpp
kCLOCK_RootM4 = (uint32_t)(CCM_BASE + offsetof(CCM_Type, ROOT[1].TARGET_ROOT)),
```

### transport 类

根据前面的测试代码，再继承自 `Transport` 类，很容易就能写出 `transport` 类。

头文件：`erpc_rpmsg_char_transport.h`

```cpp
/*
 * Copyright (c) 2014-2016, Freescale Semiconductor, Inc.
 * Copyright 2016-2020 NXP
 * Copyright 2021 kcmetercec (kcmeter.cec@gmail.com)
 * 
 * All rights reserved.
 *
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
#ifndef _EMBEDDED_RPC__RPMSG_CHAR_TRANSPORT_H_
#define _EMBEDDED_RPC__RPMSG_CHAR_TRANSPORT_H_

#include <linux/rpmsg.h>

#include <array>

#include "erpc_transport.h"

/*!
 * @addtogroup rpmsg_char_transport
 * @{
 * @file
 */

////////////////////////////////////////////////////////////////////////////////
// Classes
////////////////////////////////////////////////////////////////////////////////

namespace erpc {
/*!
 * @brief Client side of rpmsg transport.
 *
 * @ingroup rpmsg_char_transport
 */
class RPMsgCharTransport : public Transport
{
public:
    /*!
     * @brief Constructor.
     *
     * This function initializes object attributes.
     *
     * @param[in] name Specify the name of the remote device.
     * @param[in] src Specify the local address.
     * @param[in] dst Specify the destination address.
     */
    RPMsgCharTransport(const char *name, uint32_t src, uint32_t dst);

    /*!
     * @brief RPMsgCharTransport destructor
     */
    virtual ~RPMsgCharTransport();

    /*!
     * @brief This function will connect client to the server.
     *
     * @retval #kErpcStatus_Success When client connected successfully.
     * @retval #kErpcStatus_ConnectionFailure Connecting to the specified host failed.
     */
    virtual erpc_status_t connect(void);

    /*!
     * @brief This function disconnects client.
     *
     * @retval #kErpcStatus_Success Always return this.
     */
    virtual erpc_status_t disconnect(void);
    /*!
     * @brief Store incoming message to message buffer.
     *
     * In block while no message come.
     *
     * @param[in] message Message buffer, to which will be stored incoming message.
     *
     * @retval kErpcStatus_ReceiveFailed Failed to receive message buffer.
     * @retval kErpcStatus_Success Successfully received all data.
     */
    virtual erpc_status_t receive(MessageBuffer *message);

    /*!
     * @brief Function to send prepared message.
     *
     * @param[in] message Pass message buffer to send.
     *
     * @retval kErpcStatus_SendFailed Failed to send message buffer.
     * @retval kErpcStatus_Success Successfully sent all data.
     */
    virtual erpc_status_t send(MessageBuffer *message);
private:
    struct rpmsg_endpoint_info m_ep_info;
    int m_control_fd = 0;
    int m_ep_fd = 0;
    std::array<char, 256> m_read_buf;
};

} // namespace erpc

/*! @} */

#endif // _EMBEDDED_RPC__RPMSG_CHAR_TRANSPORT_H_

```

源文件：`erpc_rpmsg_char_transport.cc`

```cpp
/*
 * Copyright (c) 2015, Freescale Semiconductor, Inc.
 * Copyright 2016 NXP
 * Copyright 2021 kcmetercec (kcmeter.cec@gmail.com)
 * 
 * All rights reserved.
 *
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
#include "erpc_rpmsg_char_transport.h"

#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <fcntl.h>

#include <cstring>
#include <cstdio>

using namespace erpc;

#define DEVICE_CONTROL_NAME		"/dev/rpmsg_ctrl0"
#define DEVICE_EP_NAME			"/dev/rpmsg0"

////////////////////////////////////////////////////////////////////////////////
// Code
////////////////////////////////////////////////////////////////////////////////

RPMsgCharTransport::RPMsgCharTransport(const char *name, uint32_t src, uint32_t dst)
:Transport()
{
    std::memcpy(m_ep_info.name, name, std::strlen(name));
    m_ep_info.name[31] = '\0';
    m_ep_info.src = src;
    m_ep_info.dst = dst;
}

RPMsgCharTransport::~RPMsgCharTransport()
{
    disconnect();
}

erpc_status_t RPMsgCharTransport::connect(void)
{
    int m_control_fd = open(DEVICE_CONTROL_NAME, O_RDWR);
	if (m_control_fd == -1) 
    {
		std::perror("Can't open control device: ");

		return kErpcStatus_ConnectionFailure;
	}

	if (ioctl(m_control_fd, RPMSG_CREATE_EPT_IOCTL, &m_ep_info)) 
    {
		std::perror("Can't create endpoint:");

        disconnect();
		return kErpcStatus_ConnectionFailure;
	}

	m_ep_fd = open(DEVICE_EP_NAME, O_RDWR);
	if (m_ep_fd == -1) {
		std::perror("Can't open endpoint device: ");

        disconnect();
		return kErpcStatus_ConnectionFailure;
	}

    return 	kErpcStatus_Success;
}

erpc_status_t RPMsgCharTransport::disconnect(void)
{
    if (m_ep_fd)
    {
        if (ioctl(m_ep_fd, RPMSG_DESTROY_EPT_IOCTL)) 
        {
		    std::perror("Can't destroy endpoint:");
	    }
        close(m_ep_fd);
    }
    if (m_control_fd)
    {
        close(m_control_fd);
    }

    m_ep_fd = 0;
    m_control_fd = 0;

    return 	kErpcStatus_Success;
}

erpc_status_t RPMsgCharTransport::receive(MessageBuffer *message)
{
	int ret = read(m_ep_fd, m_read_buf.data(), m_read_buf.size());
	if (ret < 0) 
    {
		std::perror("read failed:");

        return kErpcStatus_ReceiveFailed;
	} 
    else if(ret == 0) 
    {
		std::perror("read end of file:");

        return kErpcStatus_ReceiveFailed;
	} 
    else 
    {
		message->set(reinterpret_cast<uint8_t*>(m_read_buf.data()), ret);
        message->setUsed(ret);
	}

    return kErpcStatus_Success;
}

erpc_status_t RPMsgCharTransport::send(MessageBuffer *message)
{
    uint8_t* buf = message->get();
    uint32_t length = message->getLength();
    uint32_t used = message->getUsed();

    message->set(NULL, 0);

    ssize_t ret = write(m_ep_fd, buf, used);
	if (ret != used) 
    {
		std::perror("write failed:");


        message->set(buf, length);
        message->setUsed(used);
		return kErpcStatus_SendFailed;
	}

    return kErpcStatus_Success; 
}
```
### setup 函数

setup 函数就是创建连接即可，然后在 `erpc_transport_setup.h` 中声明该函数即可。

源文件：`erpc_setup_rpmsg_char.cpp`

```cpp
/*
 * Copyright (c) 2014-2016, Freescale Semiconductor, Inc.
 * Copyright 2016-2020 NXP
 * Copyright 2021 kcmetercec (kcmeter.cec@gmail.com)
 * All rights reserved.
 *
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "erpc_manually_constructed.h"
#include "erpc_rpmsg_char_transport.h"
#include "erpc_transport_setup.h"

using namespace erpc;

////////////////////////////////////////////////////////////////////////////////
// Variables
////////////////////////////////////////////////////////////////////////////////

static ManuallyConstructed<RPMsgCharTransport> s_transport;

////////////////////////////////////////////////////////////////////////////////
// Code
////////////////////////////////////////////////////////////////////////////////

erpc_transport_t erpc_transport_rpmsg_char_init(const char *name, uint32_t src, uint32_t dst)
{
    erpc_transport_t transport;

    s_transport.construct(name, src, dst);
    if (s_transport->connect() == kErpcStatus_Success)
    {
        transport = reinterpret_cast<erpc_transport_t>(s_transport.get());
    }
    else
    {
        transport = NULL;
    }

    return transport;
}
```
# 验证
将 A53 端代码交叉编译并验证，一切工作如预期。😊
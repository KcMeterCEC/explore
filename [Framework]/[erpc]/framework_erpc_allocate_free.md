---
title: ERPC 接口内存的申请和释放
tags: 
- framework
categories:
- framework
- ERPC
date: 2022/1/17
updated: 2022/1/17
layout: true
comments: true
---

在 ERPC 的 IDL 说明文档中，对于接口内存的申请和释放是这样描述的：

> - **On the client side:** All memory space has to be allocated and provided by the user code. The shim code only reads from or writes into this memory space.
> - **On the server side:** All memory space is allocated and provided by the shim code. The user code only reads from or writes into this memory space.

为了避免在实际使用中产生内存泄漏，还是需要实际查看代码来理解。

其实这里分两种情况：
1. 以指针作为返回参数
2. 以指针作为形参

<!--more-->

这一部分的具体实现，需要查看生成的 server 和 client 端的代码来理解，还是以 [ERPC 使用体验](http://kcmetercec.top/2021/12/18/framework_erpc_demo/) 的生成代码来看，其 API 为：
```cpp
binary_t * DemoHello(const binary_t * val);
```
那么这里就主要观察 **binary_t** 这种内置类型。
# 服务端
服务端生成的代码如下：
```cpp

static void read_binary_t_struct(erpc::Codec * codec, binary_t * data)
{
    uint8_t * data_local;
    codec->readBinary(&data->dataLength, &data_local);
    data->data = (uint8_t *) erpc_malloc(data->dataLength * sizeof(uint8_t));
    if (data->data == NULL)
    {
        codec->updateStatus(kErpcStatus_MemoryError);
    }
    else
    {
        memcpy(data->data, data_local, data->dataLength);
    }
}


static void free_binary_t_struct(binary_t * data)
{
    if (data->data)
    {
        erpc_free(data->data);
    }
}

erpc_status_t DEMO_service::DemoHello_shim(Codec * codec, MessageBufferFactory *messageFactory, uint32_t sequence)
{
    erpc_status_t err = kErpcStatus_Success;

    binary_t *val = NULL;
    // 申请形参的内存
    val = (binary_t *) erpc_malloc(sizeof(binary_t));
    if (val == NULL)
    {
        codec->updateStatus(kErpcStatus_MemoryError);
    }
    binary_t * result = NULL;

    // startReadMessage() was already called before this shim was invoked.

    read_binary_t_struct(codec, val);

    err = codec->getStatus();
    if (err == kErpcStatus_Success)
    {
        // Invoke the actual served function.
#if ERPC_NESTED_CALLS_DETECTION
        nestingDetection = true;
#endif
        // 执行 API
        result = DemoHello(val);
#if ERPC_NESTED_CALLS_DETECTION
        nestingDetection = false;
#endif

        // preparing MessageBuffer for serializing data
        err = messageFactory->prepareServerBufferForSend(codec->getBuffer());
    }

    if (err == kErpcStatus_Success)
    {
        // preparing codec for serializing data
        codec->reset();

        // Build response message.
        codec->startWriteMessage(kReplyMessage, kDEMO_service_id, kDEMO_DemoHello_id, sequence);

        write_binary_t_struct(codec, result);

        err = codec->getStatus();
    }

    // 释放形参内存中 data 所指向的内存
    if (val)
    {
        free_binary_t_struct(val);
    }
    // 释放形参本身的内存
    if (val)
    {
        erpc_free(val);
    }

    // 释放返回值内存中 data 所指向的内存
    if (result)
    {
        free_binary_t_struct(result);
    }
    // 释放返回值本身的内存
    if (result)
    {
        erpc_free(result);
    }

    return err;
}
```
从上面的代码可以看出来：
1. 服务端会自动申请形参的内存，以及形参内部数据指针的内存
2. 服务端会自动释放形参相关的所有内存
3. 服务端会自动释放返回值相关的所有内存

那么对于服务端的用户实现的代码，就需要：
1. 对于形参
  - 如果服务端形参是读指针，那么只需要直接读取即可
  - 如果服务端形参是写指针，那么用户需要申请其内部`data`指针所指向的内存
2. 对于返回
  - 用户需要完成对`binary_t`以及其内部`data`指针所指向的内存的申请

所以在`server`端用户代码就是这样写的：
```cpp
binary_t * DemoHello(const binary_t * val) {
    std::cout << "client message: " << (char*)val->data;

    int len = std::strlen(ret) + 1;
    char* buf = (char*)std::malloc(len);
    std::strncpy(buf, ret, len - 1);

    binary_t* message = new binary_t{(uint8_t*)buf, (uint32_t)(len - 1)};

    return message;
}
```
当`DemoHello`函数执行完毕后，申请的这两段内存是会被自动释放掉的。

# 客户端
客户端其自动生成代码如下：
```cpp
static void read_binary_t_struct(erpc::Codec * codec, binary_t * data)
{
    uint8_t * data_local;
    codec->readBinary(&data->dataLength, &data_local);
    data->data = (uint8_t *) erpc_malloc(data->dataLength * sizeof(uint8_t));
    if (data->data == NULL)
    {
        codec->updateStatus(kErpcStatus_MemoryError);
    }
    else
    {
        memcpy(data->data, data_local, data->dataLength);
    }
}

// DEMO interface DemoHello function client shim.
binary_t * DemoHello(const binary_t * val)
{
    erpc_status_t err = kErpcStatus_Success;

    binary_t * result = NULL;

    //......
        // 申请读取内存
        result = (binary_t *) erpc_malloc(sizeof(binary_t));
        if (result == NULL)
        {
            codec->updateStatus(kErpcStatus_MemoryError);
        }
        // 这里会申请读取数据内存
        read_binary_t_struct(codec, result);

        err = codec->getStatus();
    //......

    // Dispose of the request.
    g_client->releaseRequest(request);

    // Invoke error handler callback function
    g_client->callErrorHandler(err, kDEMO_DemoHello_id);

#if ERPC_PRE_POST_ACTION
    pre_post_action_cb postCB = g_client->getPostCB();
    if (postCB)
    {
        postCB();
    }
#endif


    return result;
}
```
可以看到，客户端代码是会自动完成对`binary_t`以及其内部`data`指针所指向的内存的申请。

所以：
1. 客户端在接收到数据并处理后，**需要主动释放器返回指针的内存**！

所以，客户端的代码也是这样写的：
```cpp
int main(int argc, char *argv[]) {
    // 创建客户端
    auto transport = erpc_transport_tcp_init("127.0.0.1", 60901, false);
    // 初始化消息缓存
    auto message_buffer_factory = erpc_mbf_dynamic_init();
    // 加入消息
    erpc_client_init(transport, message_buffer_factory);

    auto message = "Hello, this is client!\n";
    binary_t cmd{(uint8_t*)message, (uint32_t)(std::strlen(message))};

    binary_t *ret = DemoHello(&cmd);

    std::cout << "Get message of server: " << ret->data << "\n";

    if (ret->data) {
        erpc_free(ret->data);
    }

    if (ret) {
        erpc_free(ret);
    }
    // 关闭连接
    erpc_transport_tcp_close();

    return 0;
}

```

# 注意
以上是 ERPC 针对`binary_t`而言，它会主动释放其内部的`data`缓存，因为这是它内置类型。

而如果是用户自定义的结构体指针中还包含其他数据指针，就需要小心管理了。

所以为了避免这种情况：
1. 简单数据类型，使用结构体进行传递
2. 复杂的数据，通过`binary_t`进行传递
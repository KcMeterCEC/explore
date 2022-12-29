---
title: 对 ARM 指令 WFI，WFE 的粗浅理解
tags: 
- arm
categories:
- processor
- arm
date: 2022/12/29
updated: 2022/12/29
layout: true
comments: true
---

ARM 具有 `WFI` 和 `WFE` 两个指令，都可以让 SOC 进入低功耗模式，但在使用时有些注意的地方。

参考链接：

- 窝窝科技 [ARM WFI和WFE指令](http://www.wowotech.net/armv8a_arch/wfe_wfi.html)

- [Arm Developer](https://developer.arm.com/documentation/ka001283/latest) 上的回答

- 文档 [How to enter low-power mode through WFI instruction](https://www.arterytek.com/download/FAQ/FAQ0111_How_to_enter_low_power_mode_through_WFI_EN_V2.0.0.pdf)

<!--more-->

# `WFI` 和 `WFE` 的异同

`WFI` 是 Wait For Interrupt 的缩写，`WFE` 是 Wait For Event 的缩写。

显然 Event 是包含 Interrupt 的，也就是说 `WFE` 是可以被除中断外的其它事件唤醒的。

由于 `WFE` 可以被软件主动发出事件唤醒，那么在多核场景下就可以让部分核心进入低功耗的状态。

> 比如 Linux kernel 里面使用的 spin lock，按照原始的定义：未获取到资源的核心应该进入 `while(1)`的状态。
> 
> 如果使用了 WFE 就可以让未获取资源的核心主动进入低功耗模式省电，而获取到资源的核心在释放自旋锁时，就发送事件唤醒进入低功耗的核心。

# `WFI` 的使用注意事项

`WFI` 由于可以被中断唤醒，所以需要在使用 `WFI` 指令前先关闭中断并清除 pending flags，否则具有 pending flags 的情况下，`WFI` 指令就会退化为 NOP 指令。

整个过程有严格的顺序：

1. 配置 NVIC 以关闭中断（首先关闭中断，以避免会产生新的 pending flags）

2. 清除外设的 pending flags

3. 清除 NVIC 的 pending flags（由于 NVIC pending flags 是由外设 pending flags 触发的，所以要先清除外设 pending flags）

4. 使用`DSB`，`DSI`指令确保数据和指令的同步

5. 调用`WFI`进入低功耗模式

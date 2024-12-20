---
title: Swupdate 的简易使用
tags: 
- swupdate
categories: 
- linux
- make
- swupdate
date: 2024/12/19
updated: 2024/12/20
layout: true
comments: true
---

这里记录 Swupdate 的简易使用说明。

<!--more-->

# 初识

## 流程

SWUpdate 是位于用户空间的应用程序，用于升级嵌入式系统（不包含 bootloader）。

它以事务的方式标识整个升级过程，事务的标识会写入到 bootloader 中，bootloader 会根据事务标记的值来确认当前升级是否成功。

比如 SWUpdate 通过设置环境变量`recovery_status`，来表示升级过程：

1. 开始升级时，其值为`progress`

2. 升级成功后，其值会被擦除

3. 升级失败，其值为`failed`

bootloader 通过查看其值为`progress`或`failed`则代表其升级未完成：

- 如果当前为`single-copy`模式，则会再次启动升级流程

- 如果当前为`double-copy`模式，则会启动上一个版本的程序

## 文件格式

![](./pic/swupdate_file_struct.jpg)

上图为其打包后的文件版本，主要是`sw-description`来实现多个镜像文件的描述。

可以看到它是将多个文件打包为一个`cpio`文件，那么这里再来复习一下`cpio`工具的操作：

```shell
### 打包
# 创建打包：通过 find 遍历当前文件及文件夹输出给 cpio
find . -depth -print | cpio -o > /path/archive.cpio


### 解包
# 可以解包所有文件
cpio -i -vd < archive.cpio
# 也可以只提取指定文件
cpio -i -d /etc/fstab < archive.cpio


### 查看
# 仅查看内容不解包
cpio -t < archive.cpio
```

## 编译

在 `buildroot`中只需要搜`swupdate`就可以找到该包并使能，如果想要更细致的配置，可以通过以下命令配置：

```shell
make swupdate-menuconfig
```

在输出路径`output/build/swupdate/tools`中有文件`swupdate-progress.c`可以作为很好的参考，用于与`swupdate`交互获取当前的状态。

## 使用

`swupdate`的一般流程如下：

1. 提取`sw-description`并校验，如果还使能了签名验证，还会提取`sw-description.sig` 文件进行签名验证。

2. 根据`sw-description`中提供的信息，读取当前设备的硬件版本，来验证是否有兼容该硬件版本的软件包。

3. 根据`sw-description`中的信息识别哪些软件包需要被安装，如果具有`embedded-script`则会在解析这些软件包前执行这些脚本，如果具有`hooks`则会在解析软件包时执行（即使这些软件包会被跳过）。最终生成一张执行列表和对应的哪些`handler`需要被调用。

4. 如果有`pre update command`，则先执行这些命令

5. 如果有分区的必要，则执行`partition handlers`

6. 依次从`cpio`文件中提取需要安装的软件包，在读取软件包时还会进行内容校验，如果检验失败则报错。

7. 在安装软件包之前，如果具有`pre-install`脚本，则会先执行这些脚本

8. 执行对应软件包的`handler`来安装软件包

9. 安装完成后，如果具有`post-install`脚本，则会执行这些脚本

10. 更新 bootloader 的环境变量

11. 向外部接口输出升级状态

12. 如果具有`post update command`则执行这些命令



使用`swupdate`执行升级命令为：

```shell
swupdate -i <filename>
```

也可以启动一个网络服务，通过网页来升级：

```shell
# 启动后就可以通过 http://<target_ip>:8080 来访问
swupdate -w "--document-root ./www --port 8080"
```
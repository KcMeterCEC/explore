---
title: '[What] Yocto Project 初识'
date: 2018/9/13
tags: 
- yocto
categories: 
- linux
- make
- yocto
layout: true
---

参考书籍：《Embedded Linux System with the Yocto Project》
- 书籍比实际的 yocto 版本要低，所以 yocto 的详细命令需要参考其[对应版本手册](https://www.yoctoproject.org/docs/)。

运行环境:
- ubuntu18.04 amd64
- yocto 3.2.1

[yocto](https://en.wikipedia.org/wiki/Yocto-) 代表 10^-24 的小数因子，是国际标准的最小小数精度。

而 yocto project 使用此名称以代表其项目可以特别精细的调整嵌入式 linux 开发的各个阶段。

<!--more-->

# 编译第一个 yocto 工程
## yocto 的完整离线构建工具
在 yocto 的[下载页面](https://www.yoctoproject.org/software-overview/downloads/) 提供了一个叫做**Yocto Project Build Appliance** 的安装包，它其实是一个官方已经配置好的虚拟机，
并且已经安装好了一切依赖软件，可以直接在 windows 上通过虚拟机运行，这样可以方便的体验其编译及仿真运行流程。

## 准备工作
### 硬件推荐设置
- CPU：单核速度越快越好，核心越多越好......
- 内存：4GB
  - 低于 1GB 将无法运行
- 硬盘：500GB（如果是 SSD 的话最好）
  - 至少 100GB
- 需要网络连接：工具链会下载源码
  - 或者也可以提前下载自己需要的源码，离线编译
  - 如果要下载源码，建议使用[代理](https://wiki.yoctoproject.org/wiki/Working_Behind_a_Network_Proxy)

### 依赖库安装

需要安装的依赖包有：
- git1.8.3.1 或更高等级
- tar1.28 或更高
- Python3.5.0 或更高 
- 安装QEMU所需要的基本依赖
```shell
sudo apt install gawk wget git diffstat unzip texinfo gcc-multilib \
build-essential chrpath socat cpio python python3 python3-pip python3-pexpect python-git \
xz-utils debianutils iputils-ping libsdl1.2-dev xterm subversion texi2html texinfo \
make xsltproc docbook-utils fop dblatex xmlto 
```

### yocto 源码获取

yocto 项目更新分为次要版本和主要版本更新，其中主要版本更新每隔半年发布一次，次要版本则在半年之间发布更新。
- 次要版本每次更新代表修复了上一主要版本的一些 bug，但并不会加入新的功能
- 主要版本每次更新都会带有新功能、新配置文件等加入
  

基于以上特性，建议使用`git`的方式获取其源码，以可以合并次要版本修复 bug。
- 实际做项目中不建议经常合并主要版本，因为这意味着会有很多冲突需要解决。

进入 yocto 的[下载页面](https://www.yoctoproject.org/software-overview/downloads/)可以看到最新稳定版的公告，使用`git`获取当前源码：
```shell
  git clone -b gatesgarth git://git.yoctoproject.org/poky.git
  #建立一个 learn 分支来折腾
  git checkout -b learn
```
## 编译镜像文件
### 配置基本环境
yocto 提供了脚本`oe-init-build-env`用于设置环境变量并在当前目录新建一个`build`文件夹并生成基本文件来作为构建目录。
- 也可以在脚本后跟目录路径来别处生成目录
- 此脚本执行后会将当前路径切换到 bulid 文件夹中
```shell
  # 注意: source oe-init-build-env 命令需要在重启后都执行一次以设置环境变量, 否则会提示 bitbake 命令找不到!
  # oe-init-build-env 脚本相当于建立了一个隔离区，不影响当前系统的全局配置
  source oe-init-build-env
```
执行以上步骤后，会在`build/conf`文件夹下生成配置文件，可以通过配置这些文件来更改设置，其中的`local.conf`就是用于构建环境设置的文件:
- 文件中 "#" 用于注释，注释已经很清楚的说明了各项参数的意义， **但以下几点需要注意**
  - `MACHINE`：目标板架构
  - `TOPDIR`： 其值就是`build`目录的路径
  - `DL_DIR`：通过网络下载的源码的存放位置，此位置可以用于几个构建工程共享，当工具链发现已有安装包时，就不会再从网络下载了
    - 建议将此文件夹设置在`build`目录之外，这样即可以很好共享，也可以当不构建此工程时可以直接删除`build`目录
  - `SSTATE_DIR`：共享缓存文件的存放位置,工具链生成的很多中间文件，与 `DL_DIR`相似，可以多个工程共享中间文件
    - 建议将此文件夹设置在`build`目录之外，这样即可以很好共享，也可以当不构建此工程时可以直接删除`build`目录
  - `TMPDIR`：构建的输出目录,默认即可
    - 此目录包含所有的编译输出，忒大……
- 为了能够节约硬盘空间, 可以在`local.conf`文件中加入一行：
  - 用于删除一些不必要的编译中间文件
```shell
INHERIT += "rm_work"
```

### 开始编译

首次编译需要一定的时间, 因为需要首次下载文件。
- 至于时间要根据网速而定，一般几个小时吧……

**注意:**首次编译及下载会消耗很多 CPU 和内存, 对于配置不高的主机，最好将 UI 界面退出, 进入命令行界面。否则容易导致**ubuntu 自动重启**。

```shell
  #编译完整的并带GUI的发行版
  bitbake core-image-sato
  #也可以加上 -k 选项当有一般错误时不停止编译
  bitbake -k core-image-sato
```
也可以先下载文件再编译：
```shell
  bitbake -c fetchall core-image-sato
```
## 开始仿真
使用`Ctrl -C`退出仿真环境.
```shell
runqemu qemux86
```
## 注意事项
### 从别处拷贝整个工程
由于工程内部很多变量依然保存的是之前工程的配置, 所以需要先**删除build/tmp/目录下的内容, 重新编译才能正常运行!**
# yocto 工程全局概览
yocto 工程是由好几个开源工程组合起来的，这些小工程都兼容 OpenEmbedded 项目，
yocto 团队与 OpenEmbedded 团队共同维护 yocto 项目。

其成员如下所示:
- Application Developement Toolkit(ADT)： ADT 提供了 yocto 构建的基础工具，包括：交叉编译工具链、QEMU、linux 内核源码、根文件系统 
  - Poky 根据其配置而选择性的打包 ADT 中提供的工具和源码
- AutoBuilder：AutoBuilder 通过 Buildbot 实现构建的自动集成，yocto 的 QA 团队使用此工具完成持续集成和回归测试。
- BitBake：BitBake 是由 OpenEmbedded 提供的构建工具，类似于make，cmake 这类专用于编译的构建工具
- Build Appliance：完整安装 yocto 所有工具及依赖的 ubuntu 虚拟机，用于用户初次体验及测试
- Cross-Prelink：用于在编译时刻确定动态链接库的位置，以避免在运行时加载动态链接库而使性能下降。
- Eclipse IDE Plugin：为 eclipse 开发的专用插件
- EGLIBC(embedded version of the GNU C Library)：针对嵌入式的 glibc 库，但其体积小，性能高。 
- Hob：用于 BitBake 的 GUI 程序，图形化的方式来配置编译过程。
- Matchbox：专用于嵌入式平台下的图形管理器
- OpenEmbedded Core(OE Core)：OpenEmbedded 项目的核心组件
- Poky： Yocto 所提供的一个默认发行版，实际开发以其为基础做修改
- Pseudo：Pseudo提供了一个虚拟环境，使得普通用户也拥有 root 部分权限，便于修改文件系统、权限等功能
- Swabber：提供一个构建沙盒环境，此环境中的工具链都是嵌入式工具链，不会与主机上的工具链相互冲突 
- Toaster：Toaste r也是一个 GUI 形式的构建配置工具，但是它是可以通过远程网页的形式来访问的
  - 这在多人协作开发大工程时很为有用

**厉害的是，yocto团队将这些小工程的耦合性做到了最小，也就是每个小工程都可以单独使用！**

# yocto的历史简略
知道历史对理解现在有很大的意义。

OpenEmbedded 和 Yocto 都派生于开源项目 OpenZaurus，OpenZaurus 是由夏普公司开发的基于 Linux 的应用于 PDA 的软件平台。
当时夏普公司致力于以最简洁的方式可以构建出一套完整的系统，由此便诞生了 `OpenEmbedded` 项目。

`OpenEmbedded`项目于2003年建立，它通过元数据(`metadata` ,描述数据的数据)来配置构建流程，到 2005 年开发组将其分离为`BitBake`构建系统
和`OpenEmbedded metadata`系统。`OpenEmbedded`受到了很多 Linux 免费和商业发型版厂商的支持，其中的 MontaVista Software 和 OpenedHand
便构建出了`Poky`发行版。

- 元数据文件指的是配置文件的总称，比如配置文件、recipes文件、append 文件等。

`BitBake`派生于 Gentoo Linux 发行版下的 Portage（由 Python 实现）,`BitBake`在 Portage的规则基础上做了一些扩展，Portage 由以下两部分组成:

- ebuild：构建源码的系统
- emerge： 管理 ebulid 下的包依赖

`Poky`发行版是一个通用版本，能比较容易的移植到其他硬件平台，很多其他的嵌入式发行版都基于此版本。

为了能够实现将`Poky`可以轻松移植到很多其他架构上的目的，Intel 找到了 Linux 基金会并提出了此想法，
Linux 基金会在 2010 年 10 月 26 日对外宣布 Yocto 项目启动，在 2011 年 4 月 6 日宣布其初始版本发布。

## yocto 与 OpenEmbedded 的关系
yocto 与 OpenEmbedded 是两个相互合作的项目，两个项目的元数据是共享的避免重复开发。

- OpenEmbedded 专注于技术难点、recipes、还有板级支持（bsp），将这些部分进行分层开发
- yocto 专注于构建框架，致力于以简便的方式帮助用户构建嵌入式和后期的测试

## yocto中的一些专业术语

| 术语                        | 说明                                      |
|-|-|
| Append file                 | Append 文件使用`.bbappend`作为后缀，用于对 `recipe`文件的扩展或修改                                                                             |
| BitBake                     | OpenEmbedded 中的构建引擎，其通过读取元数据文件(如: recipe 文件)等配置文件实现编译控制                                                              |
| Board Support package(BSP)  | 用于对硬件的软件支持包，包含代码、文档、数据文件等                                                                                                 |
| Class                       | Class文件使用`.bbclass`作为后缀，是元数据文件(如:recipe 文件)的基类文件，很多文件都可以继承于它                                                   |
| Configuration file          | 配置文件包含对构建过程中的**全局变量**，通过对变量设置来改变构建行为                                                                                 |
| Cross-development toolchain | 针对目标板的工具链集合                                                                                                                             |
| image                       | 镜像文件包含 bootloader，kernel，rootfs 集合或其中单独的一个                                                                                         |
| Layer                       | yocto 使用分层的方式来分别配置软件各个部分，一个层就是当前部分相联系软件的元数据文件的集合                                                             |
| metadata                    | metadata 指的是用于控制 BitBake 行为的文件，包含 class，recipes，append，configuration 文件                                                             |
| OpenEmbedded Core(OE Core)  | 用于 OpenEmbedded 与 Yocto 之间的 metadata 共享的机制                                                                                                    |
| Package                     | Package 是将软件、库、文档打包为特定格式，供操作系统安装或卸载。Yocto 中表示软件包或 metadata 包                                                       |
| Package management system   | 管理系统之上的 package 安装、升级、卸载，以及各个包之间的依赖、兼容性等问题                                                                          |
| Poky                        | yocto 的基础发行版                                                                                                                                  |
| recipe                      | 使用`.bb`作为后缀，属于metadata file的一种，用于控制 BitBake 对某一小组件的构建行为，比如源码下载位置、patch 位置、如何安装、依赖关系、如何编译等等 |
| task                        | BitBake 分析 recipe 执行构建，每个构建都是一个task                                                                                                    |
| Upstream                    | 指对应部分源码的上游地址或补丁地址                                                                                                                 |
|Extensible Software Development Kit (ESDK)|yocto 可以为当前目标板创建 SDK 以便于软件开发和构建|
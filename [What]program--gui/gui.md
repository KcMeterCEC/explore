[What] program --> GUI
=======================

## GUI 的选择

目前将编程平台分为三类：

1. 基于裸机或者 RTOS 的单片机平台

首先考虑的必是优秀的国产 RTOS --> RT Thread, 如果单片机是 emwin 授权的那就使用 emwin，否则使用 rt thread配套的 RTGUI。

如果单片机资源不够，或者是RT Thread没有移植好的，那么可以考虑 FreeRTOS 或者是自己写个合作式调度器， 那么对应的GUI 就是**免费
且开源的GUI** --> [littlev](littlev.hu)

2. 基于 linux 的嵌入式平台

u-boot 使用 littlev

app 使用 Qt

3. 基于 linux / windows等系统的桌面应用

需求**运行效率**的使用 Qt

需求**开发效率**的使用 Python

## littlev

littlev 是免费且开源的基于 C 代码的 GUI，移植性相当强，并且其具有 PC 端仿真代码，大大提高了调试效率。

### 安装仿真环境

1. 安装 SDL2

SDL2 是一个库，提供一个可以直接控制硬件的接口。

> sudo apt install libsdl2-dev

2. 安装 eclipse

在官网下载 eclipse 时需要选择**大连东软信息学院**镜像站，提高下载速度。

在安装 eclipse 之前需要先安装 java 环境：

#### 懒人安装

> sudo apt install default-jdk

> 设置环境变量,  编辑文件 "~/.bash_aliases" 输入 "export JAVA\_HOME='/usr/lib/jvm/java-8-openjdk-amd64/jre/bin'"

#### 安装正式版本

> sudo add-apt-repository ppa:webupd8team/java

> sudo apt update

> sudo apt install oracle-java8-install  (可以安装 java6/7/8/9)

> sudo apt install oracle-java8-set-default (可以安装 java6/7/8/9)

> java -version (查看版本)

> 配置在各个 java 版本间切换， sudo update-alternatives --config java  , 星号代表正在使用的版本，输入编号即可选择

> 设置环境变量,  编辑文件 "~/.bash_aliases" 输入 "export JAVA\_HOME='/usr/lib/jvm/java-8-oracle/jre/bin'"


3. 下载 pc 仿真代码

> git clone https://github.com/littlevgl/proj_pc

> cd proj_pc

> git submodule init

> git submodule update

4. 启动 eclipse 并导入 littlev 工程， 编译， 运行。

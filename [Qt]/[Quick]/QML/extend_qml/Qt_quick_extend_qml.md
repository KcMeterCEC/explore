---
title: '[What]Qt c++ 扩展 QML'
tags: 
- Qt
date:  2021/2/26
categories: 
- Qt
- Quick

---

学习书籍：
1. [《QmlBook》](http://qmlbook.github.io/index.html)

Qt 版本：Qt 5.12.10

c++ 主要实现业务逻辑，qml/js 实现 UI 逻辑，是比较好的开发组合方式。
<!--more-->

# 理解 Qml 运行时环境

## 工程配置

为了使用 Qt Quick ，工程中需要包含`quick`模块。

为了加快`qml`文件的加载速度，它们需要能够被预先编译为字节码，需要满足以下条件：

1. 所有的`qml`文件必须被放置在资源文件系统中
2. 应用代码载入`qml`文件以``qrc:/URL`的形式载入
3. 在配置中加入`qtquickcompiler`选项。

综合以上，一个简单的工程配置如下：

```makefile
QT += quick

CONFIG += c++11
CONFIG += qtquickcompiler

# You can make your code fail to compile if it uses deprecated APIs.
# In order to do so, uncomment the following line.
#DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000    # disables all the APIs deprecated before Qt 6.0.0

SOURCES += \
        main.cpp

RESOURCES += qml.qrc

# Additional import path used to resolve QML modules in Qt Creator's code model
QML_IMPORT_PATH =

# Additional import path used to resolve QML modules just for Qt Quick Designer
QML_DESIGNER_IMPORT_PATH =

# Default rules for deployment.
qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target
```

## 载入`qml`文件

```cpp
#include <QGuiApplication>
#include <QQmlApplicationEngine>

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);

    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;
    const QUrl url(QStringLiteral("qrc:/main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
```

`QQmlApplicationEngine`以`qrc/URL`的形式载入起始`qml`文件后，在`qml`文件内部便可以以当前相对路径的方式载入其他`qml`文件了。

## 扩展`qml`的方式

有以下几种方式来扩展`qml`：

1. 使用`setContextProperty()`将 c++ 中的值用于`qml`
2. 使用`qmlRegisterType`来注册对象到`qml`中
3. 使用`qml`扩展插件

### setContextProperty

`setContextProperty`是最为简单的一种方式，只需要将全局对象的 API 暴露给`qml`即可。

在 c++ 中设置：

```c++
QScopedPointer<CurrentTime> current(new CurrentTime());

QQmlApplicationEngine engine;

engine.rootContext().setContextProperty("current", current.value())

engine.load(source);
```

然后就可以在`qml`中使用：

```javascript
import QtQuick 2.5
import QtQuick.Window 2.0

Window {
    visible: true
    width: 512
    height: 300

    Component.onCompleted: {
        console.log('current: ' + current)
    }
}
```

### qmlRegisterType

`qmlRegisterType`将 c++ 类的生命周期交由`qml`来控制，在启动前需要保证所有的相关库都链接完成。

在 c++ 中将类`CurrentTime`暴露给`qml`，以元素`CurrentTime`命名：

```c++
QQmlApplicationEngine engine;

qmlRegisterType<CurrentTime>("org.example", 1, 0, "CurrentTime");

engine.load(source);
```

`qml`中便可以以一个元素的方式来使用：

```javascript
import org.example 1.0

CurrentTime {
    // access properties, functions, signals
}
```

### 以扩展插件的方式

扩展插件的方式是最灵活易用的方式，建议使用这种方式。

插件是在需要使用的时候动态的加载的，而不像库那样需要在启动时就完成加载。

接下来就以一个实例来说明如何创建一个插件。

# 创建插件的基本框架

Qt creator 包含一个叫做` QtQuick 2 Extension Plugin`的向导，下面创建一个名称为`fileio`对应类为`FileIO`，并且其 URI 为`org.example.io`的插件。

> URI 的意思就是这个插件在 Qt 目录中的安装路径，比如`org.example.io`就会安装在<QT_INSTALL_PATH>/org/example/io，这个路径下。
>
> 其他代码在 import org.example.io 时，qml 引擎便会在这个路径下寻找此插件。

## 工程配置

```makefile
TEMPLATE = lib
TARGET = fileio
QT += qml quick
CONFIG += plugin c++11

TARGET = $$qtLibraryTarget($$TARGET)
uri = org.example.io

# Input
SOURCES += \
        fileio_plugin.cpp \
        fileio.cpp

HEADERS += \
        fileio_plugin.h \
        fileio.h

DISTFILES = qmldir

!equals(_PRO_FILE_PWD_, $$OUT_PWD) {
    copy_qmldir.target = $$OUT_PWD/qmldir
    copy_qmldir.depends = $$_PRO_FILE_PWD_/qmldir
    copy_qmldir.commands = $(COPY_FILE) "$$replace(copy_qmldir.depends, /, $$QMAKE_DIR_SEP)" "$$replace(copy_qmldir.target, /, $$QMAKE_DIR_SEP)"
    QMAKE_EXTRA_TARGETS += copy_qmldir
    PRE_TARGETDEPS += $$copy_qmldir.target
}

qmldir.files = qmldir
unix {
    installPath = $$[QT_INSTALL_QML]/$$replace(uri, \., /)
    qmldir.path = $$installPath
    target.path = $$installPath
    INSTALLS += target qmldir
}
```

观察其工程配置，可以看到有个文件叫做`qmldir`，其内容如下：

```ini
module org.example.io
plugin fileio
```

可以看到这个模块名称也是`org.example.io`,插件名称就是`fileio`。

## 插件类

`FileioPlugin`类继承自`QQmlExtensionPlugin`：

```cpp
#ifndef FILEIO_PLUGIN_H
#define FILEIO_PLUGIN_H

#include <QQmlExtensionPlugin>

class FileioPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    //标记这是一个 QML 扩展插件
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    //用于注册插件
    void registerTypes(const char *uri) override;
};

#endif // FILEIO_PLUGIN_H
```

查看注册插件的代码，发现就是使用的`qmlRegisterType`来完成的：

```cpp
#include "fileio_plugin.h"

#include "fileio.h"

#include <qqml.h>

void FileioPlugin::registerTypes(const char *uri)
{
    // @uri org.example.io
    //注册类 FileIO,其 uri 为 org.example.io,元素名称为 FileIO
    qmlRegisterType<FileIO>(uri, 1, 0, "FileIO");
}
```






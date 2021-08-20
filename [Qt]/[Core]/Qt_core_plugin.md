---
title: '[What]基于 Qt Core 完成插件'
tags: 
- Qt
categories: 
- Qt
- Core
layout: true
---

基于 Qt Core 完成插件，在[知乎](https://zhuanlan.zhihu.com/p/49943870)上已经有了通俗的解析。
但还有一些需要注意的地方。

<!--more-->

# 以非纯虚函数的方式作为接口

通常我们希望用户仅需要实现自己需要实现的部分，其他无需实现的部分应该由接口调用其默认行为。

这种情况下，接口就应该是一个普通虚函数而非纯虚函数。

需要注意的是：**虚函数的定义需要放到接口的声明处，而不能单独新建一个 cc 文件来实现，否则会加载失败。**

> 猜测无法分离实现的原因：用户实现的插件会包含接口头文件，而头文件中没有定义，导致最终链接的动态链接库没有接口的具体实现。

# 使用 `QPluginLoader` 来调试加载插件的错误

`QPluginLoader`具有成员函数`errorString()`，但需要在**使用`instance()`成员函数之后**，才能够比较准确的反应出问题所在。

> 上面非纯虚函数实现不能分离的问题，就是通过这种方式找出来的。

`QPluginLoader`默认会从环境变量路径中搜寻插件，所以为了调试方便，可以使用`QCoreApplication::addLibraryPath("./")`来将当前路径加入搜寻路径中。

# 示例

## 接口的定义

```cpp
#ifndef INTERFACE_COMMON_H_
#define INTERFACE_COMMON_H_

/** \file
 * A common interface for all devices.
 */

#include <QtPlugin>
#include <QString>

namespace frame{
namespace interface{
/** \class Common
 *  \brief Devices should inherit this class to implement specific detail.
 * 
 * If some device didn't have some implementation,the parent class would use default implementation.
 */
class Common{
public:
    /**
     * \param[in] value should be set [0, 100].
     * \note
     * 1. Display should be **OFF** when the value is 0.
     * 2. The brightness should be limited on 100 when value is larger than 100.
     */
    virtual void DisplayBrightnessSet(quint8 value){

    }
    virtual quint8 DisplayBrightnessGet(void) const{

        return 100;
    }
};
} // namespace interface
} // namespace frame

// Q_DECLARE_INTERFACE should be out of namespace!
Q_DECLARE_INTERFACE(frame::interface::Common, 
"frame.interface.device.common")
#endif // INTERFACE_COMMON_H_
```

## 插件的实现

```cpp
#include <QtPlugin>
#include <QObject>
#include <QDebug>

#include "interface/device/interface_common.h"

class PluginCommon : public QObject, frame::interface::Common{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "frame.interface.device.common")
    Q_INTERFACES(frame::interface::Common)

public:
    void DisplayBrightnessSet(quint8 value) override;
    quint8 DisplayBrightnessGet(void) const override;    
};

#include "plugin_common.moc"

#define LOG_OUT qDebug() << "PluginCommon: "
void PluginCommon::DisplayBrightnessSet(quint8 value){
    LOG_OUT << "Set brightness " << value;
}
quint8 PluginCommon::DisplayBrightnessGet(void) const{
    LOG_OUT << "Return brightness";

    return 100;
}
```

## 载入插件

```cpp
#include <QCoreApplication>
#include <QPluginLoader>
#include "spdlog/spdlog.h"

#include "interface/device/interface_common.h"

//! This is test string for doxygen!
int main(int argc, char* argv[]){
    spdlog::set_level(spdlog::level::debug);
    spdlog::info("Hello world!");

    // load plugins
    QCoreApplication::addLibraryPath("./");
    QPluginLoader plugin_loader("./build/plugins/device/plugin_common");    
    QObject *plugin = plugin_loader.instance();    
    
    if(plugin){
        frame::interface::Common* common = qobject_cast<frame::interface::Common*>(plugin);

        common->DisplayBrightnessSet(55);
        spdlog::debug("get brightness: {}", common->DisplayBrightnessGet());
    }else{
        spdlog::error("Can't load plugin: {}", 
        plugin_loader.errorString().toLatin1().toStdString());
    }

    return 0;
}
```


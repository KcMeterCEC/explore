---
title: '[What]Qt Quick QML 中的动画元素'
tags: 
- Qt
date:  2021/2/8
categories: 
- Qt
- Quick
layout: true
---

学习书籍：
1. [《QmlBook》](http://qmlbook.github.io/index.html)

Qt 版本：Qt 5.12.10

前面学了基础元素的基本操作部分，现在来学习一下动画。
<!--more-->

# 基础属性

动画（Animations）用于控制一个对象的属性在改变时的中间插值过程。

所有的动画都共用一个定时器，所以这些动画可以实现同步。

一个动画是改变了一个对象的多个属性来完成的，所以动画具有很多元素来实现这些属性的修改，以下是常用的元素：
- `PropertyAnimation` : 动态的修改属性的值
- `NumberAnimation` : 动态的修改类型为 qreal 的值
- `ColorAnimation` : 动态的修改颜色值
- `RotationAnimation` : 动态的修改旋转角度

除此之外还有以下元素用于特定场合：
- `PauseAnimation` : 暂停动画
- `SequentialAnimation` : 将多个动画串联
- `ParallelAnimation` : 将多个动画并联
- `AnchorAnimation` : 动态修改 anchor 的值
- `ParentAnimation` : 动态修改父元素的值
- `SmoothedAnimation` : 平滑的修改一个值
- `SpringAnimation` : 弹性修改值
- `PathAnimation` : 根据一个路径来修改
- `Vector3dAnimation` : 动态修改 QVector3d 的值

而有些时候，我们还会需要动画期间修改属性值或运行一个脚本，为此 Qt Quick 提供了：
- `PropertyAction` : 在动画期间立即修改的属性
- `ScriptAction` : 在动画期间运行脚本 

当我们想点击一下鼠标将一个对象动态移动时，可以如下：
``` js
import QtQuick 2.12

  //以一张图片作为根 root
  Image{
      id: root

      source: "images/background.png"

      //定义图像间隔，动画执行时间，运行标志
      property int padding: 40
      property int duration: 4000
      property bool running: false

      Image{
          id: box
          //图像位于起始 x 处，y 轴位于父图像中间
          x : root.padding
          y : (root.height - height) / 2
          source : "images/box_green.png"

          //修改图片 x 坐标的动画
          NumberAnimation on x{
              //终点位置
              to: root.width - box.width - root.padding
              //运行时间
              duration: root.duration
              //开始执行动画的标记
              running: root.running
          }

          //修改图片的旋转角度
          RotationAnimation on rotation{
              //最终要旋转 360°
              to: 360
              //运行时间
              duration: root.duration
              //开始执行动画的标记
              running: root.running
          }
      }

      //当鼠标点击后，将运行标志位置为真
      MouseArea{
          anchors.fill: parent
          onClicked: root.running = true
      }
  }
```
# 使用动画

动画的触发方式有以下 3 种：
1. *Animation on property*，当所有的元素被加载后，动画自动启动
2. *Behavior on property*，当属性的值被改变后，动画启动
3. *Standalone Animatioin*，当显示的使用 `stat()` 或 `running` 被设置为真时

为了更好的理解这几种触发方式，先创建一个组件“ClickableImage”：

```js
//ClickAbleImage.qml
import QtQuick 2.12

//这次是继承自基类
Item {
    id: root
    //Item 的大小就是子控件的组合大小
	width: container.childrenRect.width
	height: container.childrenRect.height
	//导出组件的 text 和 soruce 属性
	property alias text: label.text
	property alias source: image.source
    signal clicked
    
    //元素排成一列
    Column{
		id: container
		Image{
			id: image
		}
		Text{
			id: label
			width: image.width
			horizontalAlignment: Text.AlighHCenter
			wrapMode: Text.WordWrap
			color: "#ececec"
		}
    }

    //当捕捉到点击事件后，便发送 clicked 信号
    MouseArea{
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
```

**需要注意的是：**该组件的长宽是由其子元素而决定的，所以外部调用者不能再设置其长宽了，否则会破坏该组件的正常显示。

然后是通过这些触发方式来使用这个组件：

```js
import QtQuick 2.12

Rectangle{
    id: root

    width: 500;height: 500

	//这个元素的动画在脚本启动后便会运行
    ClickableImage{
        id: greenBox
        x:40;y :root.height - height

        source:"./images/box_green.png"
        text:"animation on property"
        
        //动态的修改 y 值
        NumberAnimation on y {
			to: 40; duration: 4000
        }
    }
    
    ClickableImage{
		id: blueBox
		x: (root.width - width) / 2;
		y: root.height - height
		
		source:"./images/box_blue.png"
		text: "behavior on property"
		
		//动画又 y 值而确定
		Behavior on y{
			NumberAnimation{
				duration: 4000
			}
		}
		
		//当被点击后，y 坐标通过动画设置到目标值
		onClicked: y = 40 + (Math.random() * (205-40))
    }
    ClickableImage{
		id: redBox
		x: root.width - width - 40
		y: root.height - height
		
		source: "./images/box_red.png"
		text:"standalone animation"
		
		//这个动画不主动的关联任何属性
		NumberAnimation{
			id: anim
			target: redBox
			properties: "y"
			to: 40
			duration: 4000
		}
		
		//当被点击后，主动执行动画
		onClicked: anim.start();
    }
}
```

# 组合动画

- `ParallelAnimation`使得其子动画可以被并行的执行
- `SequentialAnimation`使得其子动画以串行的方式执行

如下便是使用并行动画的例子：

```js
import QtQuick 2.12
Rectangle {
    id: root
    width: 600
    height: 400
    color: "#f0f0f0"
    border.color: Qt.lighter(color)

    property int duration: 3000
    property Item ufo: ufo

    Image {
        anchors.fill: parent
        source: "./images/ufo_background.png"
    }
    //当该图片被点击后，动画被启动
    ClickableImage {
        id: ufo
        x: 20; y: root.height-height
        text: 'ufo'
        source: "./images/ufo.png"
        onClicked: anim.restart()
    }
    ParallelAnimation {
        id: anim
        //此动画用于改变 ufo 的 y 值
        NumberAnimation {
            target: ufo
            properties: "y"
            to: 20
            duration: root.duration
        }
        //此动画用于改变 ufo 的 x 值
        NumberAnimation {
            target: ufo
            properties: "x"
            to: 160
            duration: root.duration
        }
    }
}
```

只要将`ParallelAnimation`修改为`SequentialAnimation`，图片的移动方式便是串行的了，先改变 y 值，然后改变 x 值。



并行和串行动画还可以进行嵌套以实现更为复杂的动画:

```js
import QtQuick 2.12
Item {
    id: root
    width: 570
    height: 390

    property int duration: 3000

    /*
     * @brief: 画背景
     */
    Rectangle {
        id: sky
        width: parent.width
        height: 200
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0080FF" }
            GradientStop { position: 1.0; color: "#66CCFF" }
        }
    }
    Rectangle {
        id: ground
        anchors.top: sky.bottom
        anchors.bottom: root.bottom
        width: parent.width
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00FF00" }
            GradientStop { position: 1.0; color: "#00803F" }
        }
    }

    //当图片被点击后，球回到起始位置，动画便开始执行
    Image {
        id: ball
        x: 0; y: root.height-height
        source: "./images/soccer_ball.png"
        MouseArea {
            anchors.fill: parent
            onClicked: {
                    ball.x = 0;
                    ball.y = root.height - ball.height;
                    ball.rotation = 0;
                    anim.restart()
                }
            }
    }

    // 将上下运动和左右运行进行并行
    ParallelAnimation {
        id: anim
        //先做一个顺序动画
        SequentialAnimation {
            //先改变 y 的值，由下到上
            NumberAnimation {
                target: ball
                properties: "y"
                to: 20
                duration: root.duration * 0.4
            }
            //再改变 y 的值，由上到下
            NumberAnimation {
                target: ball
                properties: "y"
                to: 240
                duration: root.duration * 0.6
            }
        }
        //这个动画用于改变 x 的值
        NumberAnimation {
            target: ball
            properties: "x"
            to: 400
            duration: root.duration
        }
        //运动的同时旋转
        RotationAnimation {
            target: ball
            properties: "rotation"
            to: 720
            duration: root.duration
        }
    }
}
```

# 状态与转换

## 状态

用户接口可以被设置为多种状态，在状态的切换过程中还可以定义转换的附加动作。

状态使用`State`元素来表示，这些元素被放置于`states`数组中：

```js
import QtQuick 2.12
Item {
    id: root
    //注意这里使用的是方括号
    states: [
        State {
            name: "go"
            PropertyChanges {  }
        },
        State {
            name: "stop"
            PropertyChanges {  }
        }
    ]
    //状态的散转是通过修改 state 属性来完成的
    Button {
        id: goButton
        onClicked: root.state = "go"
    }
}
```

下面以一个红绿灯的例子来说明操作状态的散转：

```js
import QtQuick 2.12
Rectangle {
    id: root
    width: 150
    height: 250

    property color black: '#1f1f21'
    property color red: '#fc3d39'
    property color green: '#53d769'


    gradient: Gradient {
        GradientStop { position: 0.0; color: "#2ed5fa" }
        GradientStop { position: 1.0; color: "#2467ec" }
    }

    Rectangle {
        id: light1
        x: 25; y: 15
        width: 100; height: width
        radius: width/2
        color: root.black
        border.color: Qt.lighter(color, 1.1)
    }
    Rectangle {
        id: light2
        x: 25; y: 135
        width: 100; height: width
        radius: width/2
        color: root.black
        border.color: Qt.lighter(color, 1.1)
    }

    //默认的状态是 stop
    state: "stop"
    //状态列表里面有 stop 和 go 两种状态
    states: [
        State {
            name: "stop"
            PropertyChanges { target: light1; color: root.red }
            PropertyChanges { target: light2; color: root.black }
        },
        State {
            name: "go"
            PropertyChanges { target: light1; color: root.black }
            PropertyChanges { target: light2; color: root.green }
        }
    ]

    //当被点击后，状态就可以切换
    MouseArea {
        anchors.fill: parent
        onClicked: parent.state = (parent.state == "stop"? "go" : "stop")
    }
}
```

## 转换

转换也是由多个`Transition`元素所组成，放置在`transitions`数组中，以指定状态散转的时候插入中间动作：

```js
import QtQuick 2.12
Rectangle {
    id: root
    width: 150
    height: 250

    property color black: '#1f1f21'
    property color red: '#fc3d39'
    property color green: '#53d769'


    gradient: Gradient {
        GradientStop { position: 0.0; color: "#2ed5fa" }
        GradientStop { position: 1.0; color: "#2467ec" }
    }

    Rectangle {
        id: light1
        x: 25; y: 15
        width: 100; height: width
        radius: width/2
        color: root.black
        border.color: Qt.lighter(color, 1.1)
    }
    Rectangle {
        id: light2
        x: 25; y: 135
        width: 100; height: width
        radius: width/2
        color: root.black
        border.color: Qt.lighter(color, 1.1)
    }

    //默认的状态是 stop
    state: "stop"
    //状态列表里面有 stop 和 go 两种状态
    states: [
        State {
            name: "stop"
            PropertyChanges { target: light1; color: root.red }
            PropertyChanges { target: light2; color: root.black }
        },
        State {
            name: "go"
            PropertyChanges { target: light1; color: root.black }
            PropertyChanges { target: light2; color: root.green }
        }
    ]


    transitions: [
        Transition {
            //从 stop 状态变化为 go 状态后，将会执行这个转换
            from: "stop"; to: "go"
            //如果使用通配符的话，则意味着所有状态的转变都会使用该转换
            // from: "*"; to: "*"
            //从 stop 到 go 需要两秒的时间来缓慢切换
            ColorAnimation { target: light1; properties: "color"; duration: 2000 }
            ColorAnimation { target: light2; properties: "color"; duration: 2000 }
        }
    ]

    //当被点击后，状态就可以切换
    MouseArea {
        anchors.fill: parent
        onClicked: parent.state = (parent.state == "stop"? "go" : "stop")
    }
}
```


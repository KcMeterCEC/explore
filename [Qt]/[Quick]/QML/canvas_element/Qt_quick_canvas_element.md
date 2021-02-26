---
title: '[What]Qt Quick 在画布上绘制'
tags: 
- Qt
date:  2021/2/23
categories: 
- Qt
- Quick
layout: true
---

学习书籍：
1. [《QmlBook》](http://qmlbook.github.io/index.html)

Qt 版本：Qt 5.12.10

Qt Quick 也提供了最为基本的绘制工具，`Canvas`元素提供了最基本的画布，用户就在这个画布上画点线面即可，比如下面就填充了一个方形：
```javascript
import QtQuick 2.5

Canvas {
    id: root
    // canvas size
    width: 200; height: 200
    // 绘图操作要在 onPaint 事件处理中完成
    onPaint: {
    // 2d contex 提供绘图控制
    var ctx = getContext("2d")
    // 设置线宽及颜色
    ctx.lineWidth = 4
    ctx.strokeStyle = "blue"
    // 设置填充的颜色
    ctx.fillStyle = "red"
    // 开始绘制
    ctx.beginPath()
    // 设置起始点
    ctx.moveTo(50,50)
    // upper line
    ctx.lineTo(150,50)
    // right line
    ctx.lineTo(150,150)
    // bottom line
    ctx.lineTo(50,150)
    // 结束绘制
    ctx.closePath()
    // 使能填充效果
    ctx.fill()
    // 使能外框的绘制效果
    ctx.stroke()
    }
}
```
<!--more-->

# 基本流程

在`Canvas`中绘图，其坐标（0，0）默认是在左上角，并且 x 是从左到右增加，y 是从上到下增加。

绘制最基本的线条的基本流程是：

1. 设置线宽（lineWidth）、线颜色（strokeStyle）、填充颜色（fillStyle）等
2. 启动绘制（beginPath）
3. 设置起始点（moveTo）
4. 按照坐标进行绘制
5. 结束绘制（closePath）
6. 使能填充（fill）及外框绘制（stroke）

除了基本线条，Qt Quick 还提供了很多常用图形的绘制，比如矩形：

```javascript
import QtQuick 2.12

Canvas {
    id: root
    // canvas size
    width: 200; height: 200
    // handler to override for drawing
    onPaint: {
        var ctx = getContext("2d")
        ctx.fillStyle = 'green'
        ctx.strokeStyle = "blue"
        ctx.lineWidth = 4
        // draw a filles rectangle
        ctx.fillRect(20, 20, 80, 80)
        // cut our an inner rectangle
        ctx.clearRect(30,30, 60, 60)
        // stroke a border from top-left to
        // inner center of the larger rectangle
        ctx.strokeRect(20,20, 40, 40)
    }
}
```

# 渐变色

在画布上画渐变色：

```javascript
import QtQuick 2.12

Canvas {
    id: root
    // canvas size
    width: 200; height: 200
    // handler to override for drawing
    onPaint: {
        var ctx = getContext("2d")
        //设定渐变的区域
        var gradient = ctx.createLinearGradient(100,0,100,200)
        //起始颜色
        gradient.addColorStop(0, "blue")
        //终止颜色
        gradient.addColorStop(0.5, "lightsteelblue")
        ctx.fillStyle = gradient
        ctx.fillRect(50,50,100,100)
    }
}
```

# 阴影

```javascript
import QtQuick 2.12

Canvas {
    id: root
    // canvas size
    width: 300; height: 200
    // handler to override for drawing
    onPaint: {
        var ctx = getContext("2d")
        //画深色背景
        ctx.strokeStyle = "#333"
        ctx.fillRect(0,0,root.width,root.height);

        //设置阴影
        ctx.shadowColor = "#2ed5fa";
        ctx.shadowOffsetX = 2;
        ctx.shadowOffsetY = 2;
        ctx.shadowBlur = 10;

        ctx.font = 'bold 80px 方正姚体';
        ctx.fillStyle = "#24d12e";
        ctx.fillText("Canvas!",30,180);
    }
}
```

Canvas 还支持缩放、旋转等，基本上 QPaint 有的它都有，其它的东西在需要使用的时候再来了解吧。
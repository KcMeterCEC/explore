---
title: 项目管理扫盲
tags: 
- pm
categories:
- pm
- basic
date: 2022/6/14
updated: 2022/6/14
layout: true
comments: false
---

这是对[网易一千零一夜](https://book.douban.com/subject/26883531/)的读书笔记。

但我本人的职责和喜好也需要长期的做核心的一线开发，所以这也是对团队技术开发的思考。

<!--more-->

# 认识项目经理

## 5 个基本建议

### 方向

项目经理需要有对整个项目的全局观，有了全局观才能够知道整个项目的方向是什么。

所谓的方向就是：
1. 当前项目是为了满足什么需求而发起的？
2. 为了满足这个需求，这个项目最为核心的部分是什么？

有了上面的认识，就需要经常梳理这些问题：
1. 各个小组人员目前进展到哪一步了，他们目前有遇到的难点是什么？
2. 我应该怎么做可以推进项目进度，解决小组人员目前的困境？

### 不要事必躬亲

团队的协作总是会强于个人的英雄主义，作为项目负责人需要：
1. 设计项目架构，并负责该架构的核心部分
2. 与核心部分接口的模块（插件）应该交付于小组其他小伙伴
3. 激励小伙伴高效率的完成模块

这里的核心部分指的是项目的核心业务逻辑（平台），而接口部分则是：
1. 位于平台之下的插件（比如经过单片机控制的板卡），平台为这些插件提供抽象接口，用户的操控最终会通过接口来控制这些插件
2. 增加平台的平级插件（比如数据处理插件），平台通过抽象接口使用这些插件可以增加（增强）功能
3. 位于平台之上的应用，应用（比如 UI）通过调用平台提供的接口，可以满足不同场景的需求

一开始让小组人员从事非平台的模块开发，有助于人员培养。当他们能力增强后，也应该将平台模块交付给他们。

### 不要做监工

约束人员的不应该是项目经理，而应该是合理的制度。项目经过应该站在全局层次，引导人员相互合作完成项目。

> 目前我所理解的，就是需要掌握项目的核心业务逻辑，才能够引导小组人员科学的完成项目。

### 言行一致

答应了小组人员要做的事，就应该在约定时间之内完成，即使对方没有在意，也应该认真对待。

一点点的积累，才会赢得大家的信任。

### 不要强势

做事要对事不对人，不应该因为职位高于小组人员就压制与自己不同的想法。

对于诸多想法要做到求同存异，在不影响核心业务的情况下，可以做到适当的妥协，以换取团队的高效。

## 项目管理境界

### 做项目

对于一个定义十分清楚的项目，可以在满足项目铁三角（范围、时间、成本和质量）的情况下交付项目。

这里境界需要学会使用基本的项目管理技巧（项目计划、会议、进度跟踪工具），就可以比较好的完成任务。

### 懂业务

在做项目的基础之上，需要懂得当前为什么需要这个项目，这就是业务需求是什么。

简单来说就是：
1. 对终端用户需求有深刻的认识
2. 根据该需求可以提出多种解决方案，并根据当前公司内部实际情况制定一个切实可行的方案

有了以上两点的认识，项目经理就可以参与该项目的实现，并且可以避免该项目走错方向。

> 这也是我所理解的，作为团队领导人，需要能够负责核心业务逻辑

### 懂人

参与项目的人员都有各自的诉求，如果在保证项目能够完成的情况下还能尽量平衡他们的诉求，这是个学问。而沟通能力在其中所占的比例不可谓不重要。

## 项目时间的估算

### 基本认识

项目的估算根据项目的内容不同差异很大，对于有经验，踩过坑的项目估算起来就相对比没有经验，需要学习的项目准确得多。大部分时候最终的结果都会超出预期的。

但这并不意味着不需要估算，对整个项目有个大致的时间规划才能够很好的把握项目进度。

### 如何进行估算

估算的方式有“理想人日”、“理想人时”、“故事点”，其中“理想人时”相比“理想人日”相对更好估算，结合“故事点”，简易的方法是：
1. 将项目进行多级拆分，最终形成多个“故事点”，为小组人员分配相应的“故事点”
2. 小组人员根据每个“故事点”，估算需要完成的“理想人时”
3. 根据“理想人时”，反推到工作日，估算出最终的完成日期
4. 根据“故事点”，反推整个项目完成所需要的截止日期
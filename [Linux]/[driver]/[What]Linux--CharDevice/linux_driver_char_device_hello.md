---
title: Linux 字符设备基础
tags: 
- linux
categories:
- linux
- driver
- char
date: 2023/9/10
updated: 2023/9/19
layout: true
comments: true
---

- kernel version : v6.1.x (lts)

整理字符设备的基础操作。

<!--more-->

# cdev(include/linux/cdev.h)

## 数据结构

linux 使用 cdev 来表示一个字符设备：

```c
struct cdev {
    struct kobject kobj;
    struct module *owner;
    const struct file_operations *ops;
    struct list_head list;
    dev_t dev;
    unsigned int count;
} __randomize_layout;

// 初始化 cdev 并复制 ops 成员变量
void cdev_init(struct cdev *, const struct file_operations *);

//动态申请一个cdev
struct cdev *cdev_alloc(void);

//向系统添加一个cdev，完成注册
int cdev_add(struct cdev *, dev_t, unsigned);

//向系统删除一个cdev
void cdev_del(struct cdev *);
```

## 设备号

设备号由 12 位主设备号和 20 位次设备号组成:

- 主设备代表某一类设备，次设备号代表某个具体设备

```c
#define MINORBITS    20
#define MINORMASK    ((1U << MINORBITS) - 1)

#define MAJOR(dev)    ((unsigned int) ((dev) >> MINORBITS))
#define MINOR(dev)    ((unsigned int) ((dev) & MINORMASK))
#define MKDEV(ma,mi)    (((ma) << MINORBITS) | (mi)

/**
* @brief 将已知设备号向系统申请
* @note 在使用 cdev_add 之前需要申请设备号
*/
extern int register_chrdev_region(dev_t, unsigned, const char *);

/**
* @brief 由系统分配一个设备号
* @note 在使用 cdev_add 之前需要申请设备号, 推荐使用此函数
*/
extern int alloc_chrdev_region(dev_t *, unsigned, unsigned, const char *);

//释放设备号
//在使用cdev_del之后需要释放设备号
extern void unregister_chrdev_region(dev_t, unsigned);
```

## 文件操作接口

```c
struct file_operations {
    struct module *owner;
    // 修改文件的当前读写位置，并将新位置返回
    loff_t (*llseek) (struct file *, loff_t, int);
    ssize_t (*read) (struct file *, char __user *, size_t, loff_t *);
    ssize_t (*write) (struct file *, const char __user *, size_t, loff_t *);
    // ...
    __poll_t (*poll) (struct file *, struct poll_table_struct *);
    // 设备相关控制命令的实现
    long (*unlocked_ioctl) (struct file *, unsigned int, unsigned long);
    long (*compat_ioctl) (struct file *, unsigned int, unsigned long);
    int (*mmap) (struct file *, struct vm_area_struct *);
    unsigned long mmap_supported_flags;
    int (*open) (struct inode *, struct file *);
    int (*flush) (struct file *, fl_owner_t id);
    int (*release) (struct inode *, struct file *);
    int (*fsync) (struct file *, loff_t, loff_t, int datasync);
    int (*fasync) (int, struct file *, int);
    int (*lock) (struct file *, int, struct file_lock *);
    // ...
    ssize_t (*splice_write)(struct pipe_inode_info *, struct file *, loff_t *, size_t, unsigned int);
    ssize_t (*splice_read)(struct file *, loff_t *, struct pipe_inode_info *, size_t, unsigned int);
    // ...
} __randomize_layout;
```

抽象字符设备的操作接口为文件操作接口。

# 驱动组成框架

实际情况下，并不会直接用下面这个模块的方式来编写，而是基于驱动框架来编写。

```c
/**
* @brief : 此结构体表示设备需要用到的私有数据，和面向对象中的对象概念一样
*/
typedef struct
{
    struct cdev dev_obj;
    dev_t       dev_no;
//...
}xxx_dev_t;

static int __init xxx_init(void)
{
    int ret = 0;
    //申请该设备的私有数据
    xxx_dev_t *new_dev = kzalloc(sizeof(xxx_dev_t), GFP_KERNEL);
    if(new_dev == NULL)
    {
        ret = -ENOMEM;
        goto out;
    }

    //初始化cdev
    cdev_init(&new_dev->dev_obj, &xxx_fops);
    //申请设备号
    alloc_chrdev_region(&new_dev->dev_no, 0, 1, DEV_NAME);
    //...
    //注册设备
    ret = cdev_add(&new_dev->dev_obj, new_dev->dev_no, 1);
    //...

    out:
    return ret;
}
static void __exit xxx_exit(void)
{
    //注销设备
    cdev_dev(&new_dev->dev_obj);
    //释放占用的设备号
    unregister_chrdev_region(new_dev->dev_no, 1);
}
```

## ioctl() 命令

Linux 中 ioctl() 命令码的组成方式为:

| 方向  | 数据尺寸 | 设备类型 | 序列号 |
| --- | ---- | ---- | --- |
| 2位  | 14位  | 8位   | 8位  |

命令码的设备类型字段为一个"幻数"，取值范围为 0~0xff，文档中的 `ioctl-number.txt` 给出了一些推荐的和已经被使用的幻数，幻数的目的是为了避免 **命令码污染**。

- 命令码方向的值: `_IOC_NONE`(无数据传输),`_IOC_READ`(读),`IOC_WRITE`(写),`_IOC_READ|IOC_WRITE`(双向), **数据方向是从应用程序角度来看的**。

在实际使用中,一般使用宏: `_IO(type,nr)`, `_IOR(type,nr,size)`, `_IOW(type,nr,size)`, `_IOWR(type, nr, size)` 来直接生成命令码。

对应在内核中进行解码的宏有：`_IOC_DIR(nr)`，`_IOC_TYPE(nr)`，`_IOC_NR(nr)`，`_IOC_SIZE(nr)`

由于数据尺寸占用 14 位，那么参数的最大大小为 `16kB - 1` 字节。

# 数据交换

由于用户空间不能直接访问内核空间的内存,因此需要使用函数 `copy_from_user(), copy_to_user()` 来完成数据 **复制**。

```C
//返回不能被复制的字节数,如果完全复制成功则返回0
unsigned long copy_from_user(void *to, const void __user *from, unsigned long count);
unsigned long copy_to_user(void __user *to, const void *from, unsigned long count);
//复制简单类型,比如 char,int,long等使用 put_user 和 get_user
int val;
...
get_user(val, (int *)arg);
..
put_user(val, (int *)arg);
```

以上函数都在内部进行了缓冲区合法性检查.

**注意:**

在内核空间与用户空间的界面处,内核检查用户空间的合法性显得尤为重要, **Linux 内核的许多安全漏洞都是因为遗漏了这一检查造成的**。

侵入者可以伪造一片内核空间的缓冲区地址传入系统调用接口,让内核对这个evil指针指向的内核空间填充数据.参考:[CVE列表](http://www.cvedetails.com/)

# 示例

```c
#include <linux/init.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/slab.h>
#include <linux/uaccess.h>

//! 将一块缓存定义为一个字符设备
#define GLOBALMEM_SIZE          (0x1000)
#define MEM_CLEAR               (0x01)
//! 主设备号，表明一种驱动类
#define GLOBALMEM_MAJOR         (0)

#define DEV_NAME                "globalmem"
#define DEVICE_NUM              (1)

static int globalmem_major = GLOBALMEM_MAJOR;
module_param(globalmem_major, int, S_IRUGO);

struct globalmem_dev
{
    struct cdev cdev;
    unsigned char mem[GLOBALMEM_MAJOR];
    struct mutex mutex;
    wait_queue_head_t r_wait;
    wait_queue_head_t w_wait;
    unsigned int current_len;
};

struct globalmem_dev *globalmem_devp;

static ssize_t globalmem_read(struct file *filp, char __user *buf, size_t size, loff_t *ppos)
{
    unsigned long p = *ppos;
    unsigned int count = size;
    int ret = 0;
    struct globalmem_dev *dev = filp->private_data;
    DECLARE_WAITQUEUE(wait, current);

    mutex_lock(&dev->mutex);
    //!将当前进程加入等待队列
    add_wait_queue(&dev->r_wait, &wait);

    //! 可读数据
    while(dev->current_len == 0)
    {
        //! 如果是以非阻塞方式访问，则直接返回
        if(filp->f_flags & O_NONBLOCK)
        {
                ret = -EAGAIN;
                goto out;
        }
        printk(KERN_INFO "wait for read!\n");
        //! 如果以阻塞访问，则将当前进程挂起
        __set_current_state(TASK_INTERRUPTIBLE);
        //! 释放互斥量，然写函数可以工作
        mutex_unlock(&dev->mutex);
        //! 进程切换
        schedule();
        //! 如果是其他信号唤醒了进程，也直接返回
        if(signal_pending(current))
        {
                ret = -ERESTARTSYS;
                goto out2;
        }
        mutex_lock(&dev->mutex);
    }

    if(p >= GLOBALMEM_SIZE)
    {
        ret = 0;
        goto out;
    }
    if(count > dev->current_len)
    {
        count = dev->current_len;
    }

    if(copy_to_user(buf, dev->mem , count))
    {
        ret = -EFAULT;
    }
    else
    {
        //! 将剩余的数据放在队列首部
        memcpy(dev->mem, dev->mem + count, dev->current_len - count);
        dev->current_len -= count;
        *ppos += count;
        ret = count;
        printk(KERN_INFO "read %u byte(s) from %lu\n", count, p);
        //! 唤醒写进程
        wake_up_interruptible(&dev->w_wait);
        printk(KERN_INFO "wakeup write!\n");
    }

out:
    mutex_unlock(&dev->mutex);
out2:
    //! 移除等待队列
    remove_wait_queue(&dev->r_wait, &wait);
    //! 设置状态为正常
    set_current_state(TASK_RUNNING);
    return ret;
}

static ssize_t globalmem_write(struct file *filp, const char __user * buf, size_t size, loff_t*ppos)
{
    unsigned long p = *ppos;
    unsigned int count = size;
    int ret = 0;
    struct globalmem_dev *dev = filp->private_data;
    DECLARE_WAITQUEUE(wait, current);
    mutex_lock(&dev->mutex);
    add_wait_queue(&dev->w_wait, &wait);

    while(dev->current_len >= GLOBALMEM_SIZE)
    {
        if(filp->f_flags & O_NONBLOCK)
        {
            ret = -EAGAIN;
            goto out;
        }
        printk(KERN_INFO "wait for write!\n");
        __set_current_state(TASK_INTERRUPTIBLE);
        mutex_unlock(&dev->mutex);
        schedule();
        if(signal_pending(current))
        {
            ret = -ERESTARTSYS;
            goto out2;
        }
        mutex_lock(&dev->mutex);
    }

    if(p >= GLOBALMEM_SIZE)
    {
        ret = 0;
        goto out;
    }
    if(count > GLOBALMEM_SIZE - dev->current_len)
    {
        count = GLOBALMEM_SIZE - dev->current_len;
    }

    if(copy_from_user(dev->mem + dev->current_len, buf, count))
    {
        ret = -EFAULT;
    }
    else
    {
        dev->current_len += count;
        *ppos += count;
        ret = count;
        printk(KERN_INFO "written %u byte(s) current_len %lu\n", count, dev->current_len);
        printk(KERN_INFO "wakeup read");
        wake_up_interruptible(&dev->r_wait);
    }

out:
    mutex_unlock(&dev->mutex);
out2:
    remove_wait_queue(&dev->w_wait, &wait);
    set_current_state(TASK_RUNNING);

    return ret;

}

static loff_t globalmem_llseek(struct file *filp, loff_t offset, int orig)
{
        loff_t ret = 0;
        switch(orig)
        {
        case 0:
        {
            if(offset < 0)
            {
                ret= -EINVAL;
                break;
            }
            if((unsigned int)offset > GLOBALMEM_SIZE)
            {
                ret = -EINVAL;
                break;
            }
            filp->f_pos = (unsigned int)offset;
            ret = filp->f_pos;
        }break;
        case 1:
        {
            if((filp->f_pos + offset) > GLOBALMEM_SIZE)
            {
                ret = -EINVAL;
                break;
            }
            if((filp->f_pos + offset) < 0)
            {
                ret = -EINVAL;
                break;
            }
            filp->f_pos += offset;
            ret = filp->f_pos;
        }break;
        default:
        {
            ret = -EINVAL;
        }break;

        }
        return ret;

}
static long globalmem_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
        struct globalmem_dev *dev = filp->private_data;

        switch(cmd)
        {
        case MEM_CLEAR:
        {
            mutex_lock(&dev->mutex);
            memset(dev->mem, 0, GLOBALMEM_SIZE);
            mutex_unlock(&dev->mutex);
            printk(KERN_INFO "globalmem is set to zero\n");
        }break;
        default: return -EINVAL;
        }


        return 0;

}

static int globalmem_open(struct inode *inode, struct file *filp)
{
    struct globalmem_dev *dev = container_of(inode->i_cdev, struct globalmem_dev, cdev);
    filp->private_data = dev;
    return 0;
}
static int globalmem_release(struct inode *inode, struct file *filp)
{
    return 0;
}

static const struct file_operations globalmem_fops =
{
    .owner = THIS_MODULE,
    .llseek = globalmem_llseek,
    .read =globalmem_read,
    .write = globalmem_write,
    .unlocked_ioctl = globalmem_ioctl,
    .open = globalmem_open,
    .release = globalmem_release,
};

static void globalmem_setup_cdev(struct globalmem_dev *dev, int index)
{
    //! 通过主设备号与次设备号生成 设备号
    int err, devno = MKDEV(globalmem_major, index);

    //! 将fops与cdev建立连接
    cdev_init(&dev->cdev, &globalmem_fops);
    dev->cdev.owner = THIS_MODULE;
    //! 向系统注册字符设备
    err = cdev_add(&dev->cdev, devno, 1);
    if(err)
    {
            printk(KERN_NOTICE "Error %d adding globalmem %d\n", err, index);
    }
}

static int __init globalmem_init(void)
{
        int ret;
        int i = 0;
        dev_t devno = MKDEV(globalmem_major, 0);

        if(globalmem_major)
        {
            //! 向系统指定设备号
            ret = register_chrdev_region(devno, DEVICE_NUM, DEV_NAME);
        }
        else
        {
            //! 向系统申请设备号
            ret = alloc_chrdev_region(&devno, 0, DEVICE_NUM, DEV_NAME);
            //! 获取设备号
            globalmem_major = MAJOR(devno);
        }
        if(ret < 0)
        {
            return ret;
        }
        //! 申请设备空间
        globalmem_devp = kzalloc(sizeof(struct globalmem_dev) * DEVICE_NUM, GFP_KERNEL);
        if(globalmem_devp == NULL)
        {
            ret = -ENOMEM;
            goto fail_malloc;
        }
        //! 注册设备
        for(i = 0; i < DEVICE_NUM; i++)
        {
            mutex_init(&(globalmem_devp + i)->mutex);
            globalmem_setup_cdev(globalmem_devp + i, i);
            init_waitqueue_head(&(globalmem_devp + i)->r_wait);
            init_waitqueue_head(&(globalmem_devp + i)->w_wait);
        }
        return 0;

fail_malloc:
        //! 释放申请的设备号
        unregister_chrdev_region(devno, DEVICE_NUM);
        return ret;
}
module_init(globalmem_init);

static void __exit globalmem_exit(void)
{
    //! 卸载设备
    int i  = 0;
    for(i= 0; i < DEVICE_NUM; i++)
    {
            cdev_del(&(globalmem_devp + i)->cdev);
    }
    //! 释放申请的设备号
    unregister_chrdev_region(MKDEV(globalmem_major, 0), DEVICE_NUM);
    //! 释放空间
    kfree(globalmem_devp);
}
module_exit(globalmem_exit);

MODULE_AUTHOR("kcmetercec <kcmeter.cec@gmail.com>");
//! 如果没有许可证声明，加载模块时会收到内核被污染警告(Kernel Tainted)
MODULE_LICENSE("GPL v2");// GPL, GPL v2, GPL and additional rights, Dual BSD/GPL, Dual MPL/GPL
MODULE_DESCRIPTION("A simple example char device ");
MODULE_ALIAS("a simplest module");
MODULE_VERSION("ver1.0");
```

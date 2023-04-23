---
title: 输出 Linux 中所有的 task
tags: 
- linux
categories:
- linux
- ps
- chore
date: 2023/4/11
updated: 2023/4/13
layout: true
comments: true
---

- kernel version : v6.1.x (lts)

进程或线程对于 kernel 来说，都是 `task_struct` 结构体来描述，所以这里指的是输出所有的 task。

<!--more-->

# task_struct 的双向链表

还是继续来看，`task_struct`的结构体定义：

```c
struct task_struct {
#ifdef CONFIG_THREAD_INFO_IN_TASK
    /*
     * For reasons of header soup (see current_thread_info()), this
     * must be the first element of task_struct.
     */
    struct thread_info        thread_info;
    //...
    unsigned int            rt_priority;
    //...

    struct sched_info        sched_info;
    //...
    struct list_head        tasks;
    //...
    /*
     * executable name, excluding path.
     *
     * - normally initialized setup_new_exec()
     * - access it with [gs]et_task_comm()
     * - lock it with task_lock()
     */
    char                comm[TASK_COMM_LEN];
    //...
};
```

该结构体中就具有双向链表节点`tasks`，所以通过它就将所有的 task 都链接了起来，那么问题来了：这个链表的头在哪里？

## 0 号进程

Linux kernel 会以全局变量的方式创建 0 号进程”swapper“，该进程在启动后才会去创建 PID 为 1 的"init"进程，所以该进程便是所有 tasks 的头节点，可以通过它来遍历所有的 task。

> 由于是全局变量，所以该进程是不能被杀死或停止的。

`swapper`进程的精妙之处在于，它的优先级是最低的，当整个系统没有 task 在运行时，便会运行该进程，该进程可以管理一些资源，且可以让 CPU 进入浅度睡眠以省电。

0 号进程的定义位于`init/init_task.c`中。

## 内核模块来输出 tasks

模块代码如下：

```c
#define pr_fmt(fmt) "tasks:" fmt

#include <linux/init.h>
#include <linux/module.h>
#include <linux/list.h>
#include <linux/sched/task.h>
#include <linux/pid.h>
#include <linux/sched.h>

static void print_tasks(void)
{
    struct task_struct* current_entry = NULL;
    struct task_struct* next_entry = NULL;

    pr_info("pid = %d, name = %s\n",
            task_pid_nr(&init_task),
            init_task.comm);

    list_for_each_entry_safe(current_entry, next_entry,
                             &(init_task.tasks), tasks) {
        pr_info("pid = %d, name = %s\n",
                task_pid_nr(current_entry),
                current_entry->comm);
    }
}

static int __init tasks_init(void)
{
    pr_info("Hello world!\n");
    print_tasks();
    return 0;
}
module_init(tasks_init);

static void __exit tasks_exit(void)
{
    pr_info("Bye!\n");
}
module_exit(tasks_exit);

MODULE_AUTHOR("kcmetercec <kcmeter.cec@gmail.com>");
MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("A simple demo which prints tasks");
MODULE_ALIAS("print tasks demo");
MODULE_VERSION("ver1.0");
```

对应的 Makefile 如下：

```makefile
KVERS = $(shell uname -r)

obj-m += print_tasks.o

EXTRA_CFLAGS = -std=gnu99

build: kernel_modules

kernel_modules:
        make -C /lib/modules/$(KVERS)/build M=$(CURDIR) modules

clean:
        make -C /lib/modules/$(KVERS)/build M=$(CURDIR) clean
```

# 哈希表

前面以双向链表的方式组织 tasks 是为了遍历所有的 tasks，而如果要快速通过 PID 来找到一个 tasks 就不能用遍历的方式，而是要使用哈希表的方式，这样时间复杂度就由 O（n）降低到了 O（1）。

## 认识 Linux 中的哈希表实现

### 节点的定义

```c
struct hlist_head {
	struct hlist_node *first;
};

struct hlist_node {
	struct hlist_node *next, **pprev;
};
```

头节点只包含一个指针，是为了在哈希表中节省内存（相比双向链表而言）。



### 节点的定义和初始化

```c
#define HLIST_HEAD_INIT { .first = NULL }
#define HLIST_HEAD(name) struct hlist_head name = {  .first = NULL }
#define INIT_HLIST_HEAD(ptr) ((ptr)->first = NULL)
static inline void INIT_HLIST_NODE(struct hlist_node *h)
{
	h->next = NULL;
	h->pprev = NULL;
}
```

### 相关操作

```c
/**
 * hlist_unhashed - Has node been removed from list and reinitialized?
 * @h: Node to be checked
 *
 * Not that not all removal functions will leave a node in unhashed
 * state.  For example, hlist_nulls_del_init_rcu() does leave the
 * node in unhashed state, but hlist_nulls_del() does not.
 */
static inline int hlist_unhashed(const struct hlist_node *h)
{
	return !h->pprev;
}

/**
 * hlist_unhashed_lockless - Version of hlist_unhashed for lockless use
 * @h: Node to be checked
 *
 * This variant of hlist_unhashed() must be used in lockless contexts
 * to avoid potential load-tearing.  The READ_ONCE() is paired with the
 * various WRITE_ONCE() in hlist helpers that are defined below.
 */
static inline int hlist_unhashed_lockless(const struct hlist_node *h)
{
	return !READ_ONCE(h->pprev);
}

/**
 * 当头节点指向的下一个节点为 NULL 时，则代表当前链表为空
 */
static inline int hlist_empty(const struct hlist_head *h)
{
	return !READ_ONCE(h->first);
}
// 删除当前节点
static inline void __hlist_del(struct hlist_node *n)
{
	struct hlist_node *next = n->next;
	struct hlist_node **pprev = n->pprev;

	WRITE_ONCE(*pprev, next);
	if (next)
		WRITE_ONCE(next->pprev, pprev);
}

/**
 * 删除当前节点，并将后继和前驱节点设定为特定值
 *
 */
static inline void hlist_del(struct hlist_node *n)
{
	__hlist_del(n);
	n->next = LIST_POISON1;
	n->pprev = LIST_POISON2;
}

/**
 * 删除当前节点，并将后继和前驱节点设定为 NULL
 */
static inline void hlist_del_init(struct hlist_node *n)
{
	if (!hlist_unhashed(n)) {
		__hlist_del(n);
		INIT_HLIST_NODE(n);
	}
}

/**
 * 将节点 n 增加到头节点 h 的后面
 *
 */
static inline void hlist_add_head(struct hlist_node *n, struct hlist_head *h)
{
	struct hlist_node *first = h->first;
	WRITE_ONCE(n->next, first);
	if (first)
		WRITE_ONCE(first->pprev, &n->next);
	WRITE_ONCE(h->first, n);
	WRITE_ONCE(n->pprev, &h->first);
}

/**
 * 将节点 n 增加到节点 next 的前面
 */
static inline void hlist_add_before(struct hlist_node *n,
				    struct hlist_node *next)
{
	WRITE_ONCE(n->pprev, next->pprev);
	WRITE_ONCE(n->next, next);
	WRITE_ONCE(next->pprev, &n->next);
	WRITE_ONCE(*(n->pprev), n);
}

/**
 * 将节点 n 增加到节点 prev 的后面
 */
static inline void hlist_add_behind(struct hlist_node *n,
				    struct hlist_node *prev)
{
	WRITE_ONCE(n->next, prev->next);
	WRITE_ONCE(prev->next, n);
	WRITE_ONCE(n->pprev, &prev->next);

	if (n->next)
		WRITE_ONCE(n->next->pprev, &n->next);
}

/**
 * 构建一个环形的链表
 */
static inline void hlist_add_fake(struct hlist_node *n)
{
	n->pprev = &n->next;
}

/**
 * 检查是否是环形链表
 */
static inline bool hlist_fake(struct hlist_node *h)
{
	return h->pprev == &h->next;
}

/**
 * 检查当前链表是否只含有一个节点
 */
static inline bool
hlist_is_singular_node(struct hlist_node *n, struct hlist_head *h)
{
	return !n->next && n->pprev == &h->first;
}

/**
 * 将链表 old 移动到新的 new
 */
static inline void hlist_move_list(struct hlist_head *old,
				   struct hlist_head *new)
{
	new->first = old->first;
	if (new->first)
		new->first->pprev = &new->first;
	old->first = NULL;
}

// 根据节点反推结构体地址
#define hlist_entry(ptr, type, member) container_of(ptr,type,member)

// 正向遍历链表
#define hlist_for_each(pos, head) \
	for (pos = (head)->first; pos ; pos = pos->next)

// 安全的方式正向遍历链表
#define hlist_for_each_safe(pos, n, head) \
	for (pos = (head)->first; pos && ({ n = pos->next; 1; }); \
	     pos = n)

// 安全的方式获取结构体
#define hlist_entry_safe(ptr, type, member) \
	({ typeof(ptr) ____ptr = (ptr); \
	   ____ptr ? hlist_entry(____ptr, type, member) : NULL; \
	})

/**
 * 安全的方式从头遍历结构体
 */
#define hlist_for_each_entry(pos, head, member)				\
	for (pos = hlist_entry_safe((head)->first, typeof(*(pos)), member);\
	     pos;							\
	     pos = hlist_entry_safe((pos)->member.next, typeof(*(pos)), member))

/**
 * 安全的方式继续遍历结构体
 */
#define hlist_for_each_entry_continue(pos, member)			\
	for (pos = hlist_entry_safe((pos)->member.next, typeof(*(pos)), member);\
	     pos;							\
	     pos = hlist_entry_safe((pos)->member.next, typeof(*(pos)), member))

/**
 * 安全的方式从当前位置遍历结构体
 */
#define hlist_for_each_entry_from(pos, member)				\
	for (; pos;							\
	     pos = hlist_entry_safe((pos)->member.next, typeof(*(pos)), member))

/**
 * 安全的方式继续遍历结构体
 */
#define hlist_for_each_entry_safe(pos, n, head, member) 		\
	for (pos = hlist_entry_safe((head)->first, typeof(*pos), member);\
	     pos && ({ n = pos->member.next; 1; });			\
	     pos = hlist_entry_safe(n, typeof(*pos), member))
```

以上的 hlist 其实是一个单链表，为了高效操作插入和删除的操作，所以使用了 `pprev` 二级指针来指向前一个节点。

## 根据 pid 找到 task_struct

```c
struct task_struct *find_get_task_by_vpid(pid_t nr)
{
	struct task_struct *task;

	rcu_read_lock();
	task = find_task_by_vpid(nr);
	if (task)
		get_task_struct(task);
	rcu_read_unlock();

	return task;
}


/*
 * Must be called under rcu_read_lock().
 */
struct task_struct *find_task_by_pid_ns(pid_t nr, struct pid_namespace *ns)
{
	RCU_LOCKDEP_WARN(!rcu_read_lock_held(),
			 "find_task_by_pid_ns() needs rcu_read_lock() protection");
	return pid_task(find_pid_ns(nr, ns), PIDTYPE_PID);
}

struct task_struct *find_task_by_vpid(pid_t vnr)
{
	return find_task_by_pid_ns(vnr, task_active_pid_ns(current));
}

struct pid *find_pid_ns(int nr, struct pid_namespace *ns)
{
	return idr_find(&ns->idr, nr);
}

/**
 * idr_find() - Return pointer for given ID.
 * @idr: IDR handle.
 * @id: Pointer ID.
 *
 * Looks up the pointer associated with this ID.  A %NULL pointer may
 * indicate that @id is not allocated or that the %NULL pointer was
 * associated with this ID.
 *
 * This function can be called under rcu_read_lock(), given that the leaf
 * pointers lifetimes are correctly managed.
 *
 * Return: The pointer associated with this ID.
 */
void *idr_find(const struct idr *idr, unsigned long id)
{
	return radix_tree_lookup(&idr->idr_rt, id - idr->idr_base);
}

struct task_struct *pid_task(struct pid *pid, enum pid_type type)
{
	struct task_struct *result = NULL;
	if (pid) {
		struct hlist_node *first;
		first = rcu_dereference_check(hlist_first_rcu(&pid->tasks[type]),
					      lockdep_tasklist_lock_is_held());
		if (first)
			result = hlist_entry(first, struct task_struct, pid_links[(type)]);
	}
	return result;
}
```





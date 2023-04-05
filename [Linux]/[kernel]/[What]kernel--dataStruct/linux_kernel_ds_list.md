---
title: 认识 Linux 内核中的双向环形链表
tags: 
- linux
categories:
- linux
- kernel
- data_struct
date: 2023/3/26
updated: 2023/4/2
layout: true
comments: true
---

- kernel version : v6.1.x (lts)

Linux 内核中的双向环形链表，巧妙的实现了将对象挂在节点上，而不是传统的将节点挂在对象上。

<!--more-->

linux 在 `include/linux/list.h` 中提供了双向环形链表的操作函数，此代码可以移植到其他应用环境中,方便使用。

> 在内核编程环境中，需要 `#include <linux/list.h>` 来包含该头文件

需要注意的是：

1. linux是通过**将此链表嵌入在其他数据结构中， 从而将很多不同的数据结构链接起来！**（而不是链表中包含数据）。
2. 函数中的参数 `head` 代表的即为链表头！
3. `typeof` 是GCC扩展的关键字, 所以不能在编译选项中添加 `-std=c99` ，而是使用 `-std=gnu99` 。
   - 为了兼容所有编译器，我在[github](https://github.com/KcMeterCEC/common_code/tree/master/c/data_structure/list/circular)中移植了通用版本。

# 认识环形链表

## 认识节点

通过阅读代码来理解实现，那么首先来看链表中的节点是如何定义的：

```c
struct list_head {
    struct list_head *next, *prev;
};
```

`list_head`就代表一个节点，节点包含指向上一个节点和下一个节点的前驱（prev）和后继（next）指针。

## 定义并初始化头节点

在链表中，首先需要创建的便是头节点：

```c
#define LIST_HEAD_INIT(name) { &(name), &(name) }

#define LIST_HEAD(name) \
    struct list_head name = LIST_HEAD_INIT(name)
```

宏`LIST_HEAD`便完成了定义头节点，并对其完成初始化。初始化后的头节点其前驱和后继指针都指向自己，这便形成了最初始的环（也就空链表）。

除了上面的宏完成定义和初始化外，还有函数来单独初始化头节点，相当于将节点初始化为空链表了：

```c
static inline void INIT_LIST_HEAD(struct list_head *list)
{
    WRITE_ONCE(list->next, list);
    WRITE_ONCE(list->prev, list);
}
```

> 由于是在后期对节点的更改，这里使用了`WRITE_ONCE`原子操作来避免 data race。

## 插入节点

### 底层操作

```c
static inline void __list_add(struct list_head *new,
                  struct list_head *prev,
                  struct list_head *next)
{
    if (!__list_add_valid(new, prev, next))
        return;

    next->prev = new;
    new->next = next;
    new->prev = prev;
    WRITE_ONCE(prev->next, new);
}
```

这个函数的目的就是将节点`new`插入到节点`prev`和`next`之间。

其中这里面的`__list_add_valid`则是对参数的正确性做检查：

```c
static inline __must_check bool check_data_corruption(bool v) { return v; }

#define CHECK_DATA_CORRUPTION(condition, fmt, ...)             \
    check_data_corruption(({                     \
        bool corruption = unlikely(condition);             \
        if (corruption) {                     \
            if (IS_ENABLED(CONFIG_BUG_ON_DATA_CORRUPTION)) { \
                pr_err(fmt, ##__VA_ARGS__);         \
                BUG();                     \
            } else                         \
                WARN(1, fmt, ##__VA_ARGS__);         \
        }                             \
        corruption;                         \
    }))

bool __list_add_valid(struct list_head *new, struct list_head *prev,
              struct list_head *next)
{
    if (CHECK_DATA_CORRUPTION(prev == NULL,
            "list_add corruption. prev is NULL.\n") ||
        CHECK_DATA_CORRUPTION(next == NULL,
            "list_add corruption. next is NULL.\n") ||
        CHECK_DATA_CORRUPTION(next->prev != prev,
            "list_add corruption. next->prev should be prev (%px), but was %px. (next=%px).\n",
            prev, next->prev, next) ||
        CHECK_DATA_CORRUPTION(prev->next != next,
            "list_add corruption. prev->next should be next (%px), but was %px. (prev=%px).\n",
            next, prev->next, prev) ||
        CHECK_DATA_CORRUPTION(new == prev || new == next,
            "list_add double add: new=%px, prev=%px, next=%px.\n",
            new, prev, next))
        return false;

    return true;
}
EXPORT_SYMBOL(__list_add_valid);
```

上面这个函数就是为了检查以下几种异常：

1. prev 或 next 节点是空指针

2. prev 和 next 节点并不是相邻的关系，如果继续操作则会跳过中间的节点

3. new 等于 prev 或 next 节点

有了前面的底层操作函数，其它的操作便可以基于此来完成了。

### 用户接口

```c
// 将节点 new 插入到节点 head 的后面，就像是一个压栈的操作
static inline void list_add(struct list_head *new, struct list_head *head)
{
    __list_add(new, head, head->next);
}
```

```c
// 将节点 new 插入到节点 head 的前面，就像是插入到队列尾部
static inline void list_add_tail(struct list_head *new, struct list_head *head)
{
    __list_add(new, head->prev, head);
}
```

## 删除节点

### 底层操作

```c
static inline void __list_del(struct list_head * prev, struct list_head * next)
{
    next->prev = prev;
    WRITE_ONCE(prev->next, next);
}
```

删除`prev`和`next`之间的所有节点，这其实可以删除 0~N 个节点，但一般都用于删除一个节点。

```c
static inline void __list_del_clearprev(struct list_head *entry)
{
    __list_del(entry->prev, entry->next);
    entry->prev = NULL;
}
```

这个函数相当于将节点 entry 从链表中删除了，且 entry 的 prev 指向了空。主要是用于网络代码中使用，以高效的删除一个节点。

```c
static inline void __list_del_entry(struct list_head *entry)
{
    if (!__list_del_entry_valid(entry))
        return;

    __list_del(entry->prev, entry->next);
}
```

这个函数就是删除`entry`这个节点。

### 用户接口

```c
/*
 * These are non-NULL pointers that will result in page faults
 * under normal circumstances, used to verify that nobody uses
 * non-initialized list entries.
 */
#define LIST_POISON1  ((void *) 0x100 + POISON_POINTER_DELTA)
#define LIST_POISON2  ((void *) 0x122 + POISON_POINTER_DELTA)


static inline void list_del(struct list_head *entry)
{
    __list_del_entry(entry);
    entry->next = LIST_POISON1;
    entry->prev = LIST_POISON2;
}
```

这个函数才应该是用户所使用的函数，删除节点后，将节点的前驱和后继指针都指向了一段特殊地址。如果有代码操作该特殊地址便会触发 pagefault。 

## 其它用户操作接口

```c
// 将 old 节点替换为 new 节点
static inline void list_replace(struct list_head *old,
                struct list_head *new)
{
    new->next = old->next;
    new->next->prev = new;
    new->prev = old->prev;
    new->prev->next = new;
}
// 将 old 节点替换为 new 节点，并且将 old 节点初始化一个空链表
static inline void list_replace_init(struct list_head *old,
                     struct list_head *new)
{
    list_replace(old, new);
    INIT_LIST_HEAD(old);
}
```

```cpp
// 交换 entry1 和 entry2 的位置
static inline void list_swap(struct list_head *entry1,
                 struct list_head *entry2)
{
    struct list_head *pos = entry2->prev;

    list_del(entry2);
    list_replace(entry1, entry2);
    if (pos == entry1)
        pos = entry2;
    list_add(entry1, pos);
}
```

```c
// 从链表上删除 entry 并将 entry 初始化为空链表
static inline void list_del_init(struct list_head *entry)
{
    __list_del_entry(entry);
    INIT_LIST_HEAD(entry);
}

// 将节点 list 从其原来的列表删除，然后放到节点 head 的后面
// 那就是说：将 list 节点移动到节点 head 后面
static inline void list_move(struct list_head *list, struct list_head *head)
{
    __list_del_entry(list);
    list_add(list, head);
}
// 将 list 节点移动到节点 head 前面
static inline void list_move_tail(struct list_head *list,
                  struct list_head *head)
{
    __list_del_entry(list);
    list_add_tail(list, head);
}

// 将 first 至 last 节点之间（包含二者）的所有节点，移动到 head 节点之前
static inline void list_bulk_move_tail(struct list_head *head,
                       struct list_head *first,
                       struct list_head *last)
{
    first->prev->next = last->next;
    last->next->prev = first->prev;

    head->prev->next = first;
    first->prev = head->prev;

    last->next = head;
    head->prev = last;
}
```

```c
// 当当前节点的前驱节点是头节点时，那就意味着它是第一个节点
static inline int list_is_first(const struct list_head *list, const struct list_head *head)
{
    return list->prev == head;
}
// 当当前节点的后继节点是头节点时，那就意味着它是最后一个节点
static inline int list_is_last(const struct list_head *list, const struct list_head *head)
{
    return list->next == head;
}
// 当当前节点的地址与头节点一致，那它就是头节点
static inline int list_is_head(const struct list_head *list, const struct list_head *head)
{
    return list == head;
}
// 当头节点的后继节点是自己时，那这就是一个空链表了
static inline int list_empty(const struct list_head *head)
{
    return READ_ONCE(head->next) == head;
}
```

```c
// 内存安全形式的删除节点和置空一个节点
static inline void list_del_init_careful(struct list_head *entry)
{
    __list_del_entry(entry);
    WRITE_ONCE(entry->prev, entry);
    smp_store_release(&entry->next, entry);
}
// 确保在没有其它线程操作该链表时，判断链表是否为空
static inline int list_empty_careful(const struct list_head *head)
{
    struct list_head *next = smp_load_acquire(&head->next);
    return list_is_head(next, head) && (next == READ_ONCE(head->prev));
}
```

```c
// 将头节点右边的节点移动到头节点的左边
static inline void list_rotate_left(struct list_head *head)
{
    struct list_head *first;

    if (!list_empty(head)) {
        first = head->next;
        list_move_tail(first, head);
    }
}

// 移动 head 节点到 list 节点前面，那就是说 list 节点就是第一个节点了
static inline void list_rotate_to_front(struct list_head *list,
                    struct list_head *head)
{
    list_move_tail(head, list);
}
```

```c
// 当前链表仅有一个节点时，返回 true
static inline int list_is_singular(const struct list_head *head)
{
    return !list_empty(head) && (head->next == head->prev);
}
```

## 切割链表

### 底层操作

```c
// 将 head 之后一直到 entry（包含 entry）的节点切割到以 list 为头节点的链表中
static inline void __list_cut_position(struct list_head *list,
        struct list_head *head, struct list_head *entry)
{
    struct list_head *new_first = entry->next;
    list->next = head->next;
    list->next->prev = list;
    list->prev = entry;
    entry->next = list;
    head->next = new_first;
    new_first->prev = head;
}


// 将 list 中的节点插入到节点 prev 和 next 之间
static inline void __list_splice(const struct list_head *list,
                 struct list_head *prev,
                 struct list_head *next)
{
    struct list_head *first = list->next;
    struct list_head *last = list->prev;

    first->prev = prev;
    prev->next = first;

    last->next = next;
    next->prev = last;
}
```

### 用户接口

```c
// 将 head 之后一直到 entry（包含 entry）的节点切割到以 list 为头节点的链表中
static inline void list_cut_position(struct list_head *list,
        struct list_head *head, struct list_head *entry)
{
    if (list_empty(head))
        return;
    if (list_is_singular(head) && !list_is_head(entry, head) && (entry != head->next))
        return;
    if (list_is_head(entry, head))
        INIT_LIST_HEAD(list);
    else
        __list_cut_position(list, head, entry);
}
// 将 head 之后及 entry 之前(不包含 entry)的节点移动到 list 为头节点的链表中
static inline void list_cut_before(struct list_head *list,
                   struct list_head *head,
                   struct list_head *entry)
{
    if (head->next == entry) {
        INIT_LIST_HEAD(list);
        return;
    }
    list->next = head->next;
    list->next->prev = list;
    list->prev = entry->prev;
    list->prev->next = list;
    head->next = entry;
    entry->prev = head;
}


// 将 list 中的节点插入到节点 head 之后
static inline void list_splice(const struct list_head *list,
                struct list_head *head)
{
    if (!list_empty(list))
        __list_splice(list, head, head->next);
}


// 将 list 中的节点插入到节点 head 之前
static inline void list_splice_tail(struct list_head *list,
                struct list_head *head)
{
    if (!list_empty(list))
        __list_splice(list, head->prev, head);
}
// 将 list 中的节点插入到节点 head 之后，并设 list 为空链表
static inline void list_splice_init(struct list_head *list,
                    struct list_head *head)
{
    if (!list_empty(list)) {
        __list_splice(list, head, head->next);
        INIT_LIST_HEAD(list);
    }
}
// 将 list 中的节点插入到节点 head 之前，并设 list 为空链表
static inline void list_splice_tail_init(struct list_head *list,
                     struct list_head *head)
{
    if (!list_empty(list)) {
        __list_splice(list, head->prev, head);
        INIT_LIST_HEAD(list);
    }
}
```

## 宏操作

双向环形链表需要配合宏操作才能够发挥其威力。

### 反推节点的地址

```cpp
/* Are two types/vars the same type (ignoring qualifiers)? */
#define __same_type(a, b) \
 __builtin_types_compatible_p(typeof(a), typeof(b))

// 将 0 地址强行转换为 type 类型，然后便可以得出 member 成员在该结构体中的偏移值
#define offsetof(TYPE, MEMBER) ((size_t) &((TYPE *)0)->MEMBER)

// ptr ：当前数据成员的地址
// type ：当前结构体类型
// member ：该数据成员在结构体的名称
// 最开始经过类型检查后，便使用当前地址减去成员偏移，就可以得到结构体的首地址
#define container_of(ptr, type, member) ({                \
    void *__mptr = (void *)(ptr);                    \
    static_assert(__same_type(*(ptr), ((type *)0)->member) ||    \
              __same_type(*(ptr), void),            \
              "pointer type mismatch in container_of()");    \
    ((type *)(__mptr - offsetof(type, member))); })


#define list_entry(ptr, type, member) \
    container_of(ptr, type, member)
```

其实就是当前成员变量的地址减去其偏移地址，便可以得到结构体的首地址。

> 唯一需要注意的是，减去偏移时指针要转换为 char 型，以进行字节型的运算

示例代码如下：

```c
#include <stdio.h>

#define offsetof(type, member)  ((size_t)&((type*)0)->member)
#define container_of(ptr, type, member) (type*)((char*)ptr - offsetof(type, member))


struct hello {
    char a;
    int b;
    float c;
};

int main(int argc, char* argv[]) {

    printf("Hello world!\n");

    struct hello obj = {
        .a = 1,
        .b = 2,
        .c = 3,
    };

    printf("obj a = %d, b = %d, c = %f\n",
    obj.a, obj.b, obj.c);

    struct hello* ret = container_of(&obj.c, struct hello, c);

    printf("get value of struct, a = %d, b = %d, c = %f\n",

    ret->a, ret->b, ret->c);

    return 0;
}
```

### 相关操作函数

有了前面的认识，再来理解下面的宏就相对容易些了：

```c
/**
 * list_entry - 根据节点的地址及成员名，得出结构体对象的
 * @ptr:    the &struct list_head pointer.
 * @type:    the type of the struct this is embedded in.
 * @member:    the name of the list_head within the struct.
 */
#define list_entry(ptr, type, member) \
    container_of(ptr, type, member)
/**
 * list_first_entry - 根据头节点的地址及成员名，得出链表的第一个结构体对象的地址
 * @ptr:    the list head to take the element from.
 * @type:    the type of the struct this is embedded in.
 * @member:    the name of the list_head within the struct.
 *
 * Note, that list is expected to be not empty.
 */
#define list_first_entry(ptr, type, member) \
    list_entry((ptr)->next, type, member)

/**
 * list_last_entry - 根据头节点的地址及成员名，得出链表的最后一个结构体对象的
 * @ptr:    the list head to take the element from.
 * @type:    the type of the struct this is embedded in.
 * @member:    the name of the list_head within the struct.
 *
 * Note, that list is expected to be not empty.
 */
#define list_last_entry(ptr, type, member) \
    list_entry((ptr)->prev, type, member)

/**
 * list_first_entry_or_null - 从链表头获取第一个对象，如果是空链表则返回 NULL
 * @ptr:    the list head to take the element from.
 * @type:    the type of the struct this is embedded in.
 * @member:    the name of the list_head within the struct.
 *
 * Note that if the list is empty, it returns NULL.
 */
#define list_first_entry_or_null(ptr, type, member) ({ \
    struct list_head *head__ = (ptr); \
    struct list_head *pos__ = READ_ONCE(head__->next); \
    pos__ != head__ ? list_entry(pos__, type, member) : NULL; \
})

/**
 * list_next_entry - 根据当前节点与节点名称，获取下一个节点关联对象的地址
 * @pos:    the type * to cursor
 * @member:    the name of the list_head within the struct.
 */
#define list_next_entry(pos, member) \
    list_entry((pos)->member.next, typeof(*(pos)), member)

/**
 * list_next_entry_circular - 根据当前节点与节点名称，获取下一个节点关联对象的地址
 * 如果当前节点是最后一个节点，则返回第一个节点
 * @pos:    the type * to cursor.
 * @head:    the list head to take the element from.
 * @member:    the name of the list_head within the struct.
 *
 * Wraparound if pos is the last element (return the first element).
 * Note, that list is expected to be not empty.
 */
#define list_next_entry_circular(pos, head, member) \
    (list_is_last(&(pos)->member, head) ? \
    list_first_entry(head, typeof(*(pos)), member) : list_next_entry(pos, member))   

/**
 * list_prev_entry - 根据当前节点与节点名称，获取上一个节点关联对象的地址
 * @pos:    the type * to cursor
 * @member:    the name of the list_head within the struct.
 */
#define list_prev_entry(pos, member) \
    list_entry((pos)->member.prev, typeof(*(pos)), member)

/**
 * list_prev_entry_circular - 根据当前节点与节点名称，获取上一个节点关联对象的地址
 * 如果当前节点是第一个节点，则返回最后一个节点
 * @pos:    the type * to cursor.
 * @head:    the list head to take the element from.
 * @member:    the name of the list_head within the struct.
 *
 * Wraparound if pos is the first element (return the last element).
 * Note, that list is expected to be not empty.
 */
#define list_prev_entry_circular(pos, head, member) \
    (list_is_first(&(pos)->member, head) ? \
    list_last_entry(head, typeof(*(pos)), member) : list_prev_entry(pos, member))

/**
 * list_for_each    -    遍历当前链表，pos 则返回当前的节点
 * @pos:    the &struct list_head to use as a loop cursor.
 * @head:    the head for your list.
 */
#define list_for_each(pos, head) \
    for (pos = (head)->next; !list_is_head(pos, (head)); pos = pos->next)

/**
 * list_for_each_rcu - Iterate over a list in an RCU-safe fashion
 * @pos:    the &struct list_head to use as a loop cursor.
 * @head:    the head for your list.
 */
#define list_for_each_rcu(pos, head)          \
    for (pos = rcu_dereference((head)->next); \
         !list_is_head(pos, (head)); \
         pos = rcu_dereference(pos->next)) 

 /**
 * list_for_each_continue - 从当前节点处继续往后遍历遍历链表
 * @pos:    the &struct list_head to use as a loop cursor.
 * @head:    the head for your list.
 *
 * Continue to iterate over a list, continuing after the current position.
 */
#define list_for_each_continue(pos, head) \
    for (pos = pos->next; !list_is_head(pos, (head)); pos = pos->next)

/**
 * list_for_each_prev    -    从当前节点处，继续往前遍历链表
 * @pos:    the &struct list_head to use as a loop cursor.
 * @head:    the head for your list.
 */
#define list_for_each_prev(pos, head) \
    for (pos = (head)->prev; !list_is_head(pos, (head)); pos = pos->prev)

/**
 * list_for_each_safe - 以安全的方式对链表进行遍历，避免对当前节点执行删除操作后，便无法继续往后遍历了
 * @pos:    the &struct list_head to use as a loop cursor.
 * @n:        another &struct list_head to use as temporary storage
 * @head:    the head for your list.
 */
#define list_for_each_safe(pos, n, head) \
    for (pos = (head)->next, n = pos->next; \
         !list_is_head(pos, (head)); \
         pos = n, n = pos->next)

/**
 * list_for_each_prev_safe - 以安全的方式对链表进行遍历，避免对当前节点执行删除操作后，便无法继续往后遍历了
 * @pos:    the &struct list_head to use as a loop cursor.
 * @n:        another &struct list_head to use as temporary storage
 * @head:    the head for your list.
 */
#define list_for_each_prev_safe(pos, n, head) \
    for (pos = (head)->prev, n = pos->prev; \
         !list_is_head(pos, (head)); \
         pos = n, n = pos->prev)

/**
 * list_entry_is_head - 判断当前对象是否在头节点
 * @pos:    the type * to cursor
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 */
#define list_entry_is_head(pos, head, member)                \
    (&pos->member == (head))

/**
 * list_for_each_entry    -    这个是以对象的形式对链表进行正向遍历
 * @pos:    the type * to use as a loop cursor.
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 */
#define list_for_each_entry(pos, head, member)                \
    for (pos = list_first_entry(head, typeof(*pos), member);    \
         !list_entry_is_head(pos, head, member);            \
         pos = list_next_entry(pos, member))

/**
 * list_for_each_entry_reverse - 这个是以对象的形式对链表进行反向遍历
 * @pos:    the type * to use as a loop cursor.
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 */
#define list_for_each_entry_reverse(pos, head, member)            \
    for (pos = list_last_entry(head, typeof(*pos), member);        \
         !list_entry_is_head(pos, head, member);             \
         pos = list_prev_entry(pos, member))

/**
 * list_prepare_entry - 提取对象，为 list_for_each_entry_continue 做准备
 * @pos:    the type * to use as a start point
 * @head:    the head of the list
 * @member:    the name of the list_head within the struct.
 *
 * Prepares a pos entry for use as a start point in list_for_each_entry_continue().
 */
#define list_prepare_entry(pos, head, member) \
    ((pos) ? : list_entry(head, typeof(*pos), member))

/**
 * list_for_each_entry_continue - 以对象的方式，继续向后遍历
 * @pos:    the type * to use as a loop cursor.
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 *
 * Continue to iterate over list of given type, continuing after
 * the current position.
 */
#define list_for_each_entry_continue(pos, head, member)         \
    for (pos = list_next_entry(pos, member);            \
         !list_entry_is_head(pos, head, member);            \
         pos = list_next_entry(pos, member))

/**
 * list_for_each_entry_continue_reverse - 以对象的方式，继续向前遍历
 * @pos:    the type * to use as a loop cursor.
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 *
 * Start to iterate over list of given type backwards, continuing after
 * the current position.
 */
#define list_for_each_entry_continue_reverse(pos, head, member)        \
    for (pos = list_prev_entry(pos, member);            \
         !list_entry_is_head(pos, head, member);            \
         pos = list_prev_entry(pos, member))

/**
 * list_for_each_entry_from - 从当前节点，继续向后遍历
 * @pos:    the type * to use as a loop cursor.
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 *
 * Iterate over list of given type, continuing from current position.
 */
#define list_for_each_entry_from(pos, head, member)             \
    for (; !list_entry_is_head(pos, head, member);            \
         pos = list_next_entry(pos, member))

/**
 * list_for_each_entry_from_reverse - 从当前节点，继续向前遍历
 * @pos:    the type * to use as a loop cursor.
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 *
 * Iterate backwards over list of given type, continuing from current position.
 */
#define list_for_each_entry_from_reverse(pos, head, member)        \
    for (; !list_entry_is_head(pos, head, member);            \
         pos = list_prev_entry(pos, member))

/**
 * list_for_each_entry_safe - 以安全的方式向后遍历，避免当前对象被删除而无法遍历
 * @pos:    the type * to use as a loop cursor.
 * @n:        another type * to use as temporary storage
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 */
#define list_for_each_entry_safe(pos, n, head, member)            \
    for (pos = list_first_entry(head, typeof(*pos), member),    \
        n = list_next_entry(pos, member);            \
         !list_entry_is_head(pos, head, member);             \
         pos = n, n = list_next_entry(n, member))

/**
 * list_for_each_entry_safe_continue - 以安全的方式，继续向后遍历
 * @pos:    the type * to use as a loop cursor.
 * @n:        another type * to use as temporary storage
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 *
 * Iterate over list of given type, continuing after current point,
 * safe against removal of list entry.
 */
#define list_for_each_entry_safe_continue(pos, n, head, member)         \
    for (pos = list_next_entry(pos, member),                 \
        n = list_next_entry(pos, member);                \
         !list_entry_is_head(pos, head, member);                \
         pos = n, n = list_next_entry(n, member))

/**
 * list_for_each_entry_safe_from - 以安全的方式，从当前节点向后遍历
 * @pos:    the type * to use as a loop cursor.
 * @n:        another type * to use as temporary storage
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 *
 * Iterate over list of given type from current point, safe against
 * removal of list entry.
 */
#define list_for_each_entry_safe_from(pos, n, head, member)             \
    for (n = list_next_entry(pos, member);                    \
         !list_entry_is_head(pos, head, member);                \
         pos = n, n = list_next_entry(n, member))

/**
 * list_for_each_entry_safe_reverse - 以安全的方式向前遍历，避免当前对象被删除而无法遍历
 * @pos:    the type * to use as a loop cursor.
 * @n:        another type * to use as temporary storage
 * @head:    the head for your list.
 * @member:    the name of the list_head within the struct.
 *
 * Iterate backwards over list of given type, safe against removal
 * of list entry.
 */
#define list_for_each_entry_safe_reverse(pos, n, head, member)        \
    for (pos = list_last_entry(head, typeof(*pos), member),        \
        n = list_prev_entry(pos, member);            \
         !list_entry_is_head(pos, head, member);             \
         pos = n, n = list_prev_entry(n, member))

/**
 * list_safe_reset_next - reset a stale list_for_each_entry_safe loop
 * @pos:    the loop cursor used in the list_for_each_entry_safe loop
 * @n:        temporary storage used in list_for_each_entry_safe
 * @member:    the name of the list_head within the struct.
 *
 * list_safe_reset_next is not safe to use in general if the list may be
 * modified concurrently (eg. the lock is dropped in the loop body). An
 * exception to this is if the cursor element (pos) is pinned in the list,
 * and list_safe_reset_next is called after re-taking the lock and before
 * completing the current iteration of the loop body.
 */
#define list_safe_reset_next(pos, n, member)                \
    n = list_next_entry(pos, member)         
```



# 链表的演化

以上是双向环形链表的实现，它还可以很方便的演化为以下几种数据结构：

- 去掉前驱指针，就是单向循环链表

- 对接口进行进一步封装，只允许头的取出和尾的插入操作，就是 FIFO

- 对接口进行进一步封装，只允许头的取出和插入操作，就是栈

由于上面的链表实现方式可以被插入到任意一种数据结构中，还有一种妙用：一个数据结构根据用途插入多个链表节点！

> 相当于是以不同的角度来看这个数据结构



# 示例

下面编写一个简单的内核模块，来简单的使用一下链表，模块代码如下：



```c
#define pr_fmt(fmt) "[list]: " fmt

#include <linux/init.h>
#include <linux/module.h>
#include <linux/list.h>
#include <linux/slab.h>

#define ITEM_COUNT  (10)

struct item {
    int val;
    struct list_head node;
};

LIST_HEAD(item_head);

static void show_list(void)
{
    pr_info("I have these items:\n");

    struct item* get_item;
    list_for_each_entry(get_item, &item_head, node) {
        pr_info("val: %d\n", get_item->val);
    }
    pr_info("\n");
}

static int __init list_init(void)
{
    pr_info("%s -> %d\n", __func__, __LINE__);

    for (int i = 0; i < ITEM_COUNT; ++i) {
        struct item* new_item = (struct item* )kmalloc(sizeof(struct item), GFP_KERNEL);
        if (!new_item) {
            pr_err("Can't malloc memory!\n");
        }
        new_item->val = i;

        list_add(&(new_item->node), &item_head);
    }

    show_list();

    return 0;
}
module_init(list_init);

static void __exit list_exit(void)
{
    pr_info("%s -> %d\n", __func__, __LINE__);

    struct item* get_item;
    struct item* tmp_item;
    list_for_each_entry_safe(get_item, tmp_item, &item_head, node) {
        pr_info("delete item : %d\n", get_item->val);

        list_del(&(get_item->node));
        show_list();

        kfree(get_item);
    }
}
module_exit(list_exit);


MODULE_AUTHOR("kcmetercec <kcmeter.ece@gmail.com>");
MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("A simple demo which uses list");
MODULE_ALIAS("list demo");
MODULE_VERSION("ver1.0");

```



对应的 Makefile 如下：



```c
KVERS = $(shell uname -r)

obj-m += list.o

EXTRA_CFLAGS = -std=gnu99

build: kernel_modules

kernel_modules:
        make -C /lib/modules/$(KVERS)/build M=$(CURDIR) modules

clean:
        make -C /lib/modules/$(KVERS)/build M=$(CURDIR) clean

```



需要注意的是：上面使用了 gnu99 编译选项。

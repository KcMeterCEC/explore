---
title: 初步认识 Linux 内存管理
tags: 
- linux
categories:
- linux
- memory
- overview
date: 2024/8/5
updated: 2024/8/5
layout: true
comments: true
---

| kernel version | arch  |
| -------------- | ----- |
| v5.4.0         | arm32 |

<!--more-->

# CPU 与内存,I/O

## 内存空间与I/O空间的区别

I/O 空间的概念是存在于 X86 架构中的，与内存空间做区分，它通过特定的指令`in`,`out`来访问外设寄存器的地址。

但是在实际使用时，我们也可以将外设设计在 X86 架构的内存空间中，直接访问寄存器地址，所以 **I/O空间是可选的** 。

在大多数嵌入式微控制器中没有I/O空间，仅有内存空间。内存空间可以直接通过地址，指针来访问，程序以及其他数据都是存在于内存空间中的。

```shell
  再次强调：无论是在内核态还是在用户态，CPU 看到的都是虚拟地址！

  无论是内存条还是寄存器的访问，内核都是通过虚拟地址去访问的，内核中所有的指针操作
  都是虚拟地址。

  在内核中，物理地址对于 Linux 来说就是一个整数，如下物理地址在内核中的定义：
  //file: include/linux/types.h
  #ifdef CONFIG_PHYS_ADDR_T_64BIT
  typedef u64 phys_addr_t;
  #else
  typedef u32 phys_addr_t;
  #endif
```

## 内存管理单元MMU

MMU提供虚拟地址和物理地址的映射，内存访问权限保护和 Cache 缓存控制等硬件支持，
用户在编写实际程序时不用考虑实际物理地址有多大，以及是否会与其他程序地址冲突等等。

- 具体MMU工作参考 [MMU基本原理](https://kcmetercec.top/2023/04/06/linux_mm_hardware_mmu/)

### MMU操作原理

MMU中比较重要的两个概念：

- TLB(Translation Lookaside Buffer)
  + 转换旁路缓存，TLB 是 MMU 的核心部件，它缓存少量的虚拟地址与物理地址的转换关系，是转换表的Cache，因此也经常被称为"快表"。
- TTW(Translation Table wale)
  + 转换表漫游，当TLB中没有缓冲对应的地址转换对应关系时，需要通过对内存中转换表的访问来获得虚拟地址和物理地址的对应关系。TTW成功后，结果应写入TLB中。

MMU操作的原则都是以最快的速度来读写 CPU 所需要的数据或指令:

1. 所以它会首先访问 TLB 以保证最快的速度找到映射关系然后进行存取，如果此时打开了Cache并且Cache命中，那也会直接取Cache的数据否则取内存的数据并且更新Cache
2. 如果TLB没有命中那么就会访问 TTW 找到映射关系并反过来更新 TLB。

### MMU的权限管理

MMU的权限管理主要包含以下两个方面：

1. 这段内存是否具有RWX权限(比如代码段只有RX权限，避免被改写)
2. 这段内存是仅有内核才可访问，还是内核和用户都可访问
   - 仅有内核可访问的内存，避免用户获取到内核的数据

权限管理使用下面程序进行体验：

```c
//main.c
#include <stdio.h>

const int a = 1;

extern void access(void);
int main(void)
{
    printf("the value of a is %d\n", a);

    access();
    printf("the value of a is %d\n", a);
    return 0;
}

//access.c
/**
,* @note : 此处新建一个文件，就是让编译器在预编译、编译、汇编的过程中，无法察觉变量 a的类型，
,* 以保证编译通过。
,* 但实际上 a 的内存权限为可读，所以当执行写时，就会触发page fault
,*/
extern int a ;

void access(void)
{
    a = 2;
}
```

### meltdown漏洞

meltdown漏洞使得用户空间可以访问内核空间中的内容，详细解释参考 [格友](https://mp.weixin.qq.com/s/YjKoay39rtKQXGbWN6qfug) 。

简单解释就是：

1. 用户空间先申请一个大数组，这个大数组的每个元素的大小即为内存页表的大小，这是为了每个页可以覆盖整个 cache，便于后期测试不被干扰
2. 用户空间发送读取内核空间中 **一个字节的请求** ，一个字节的值为 0~255，假设该值为 N
3. 由于CPU的分支预测执行功能，将用户空间大数组的第 N 个块进行读取操作（此时 N 的值依然存在于寄存器中）
4. 虽然MMU进行了权限检查，但此时用户空间中数组的第 N 个块的部分数据已经存在于 cache 中了，此时 cache hit
5. 由于读取Cache的速度要远远快于读取内存的速度，用户通过依次扫描 0~255 块的读取速度，识别出读取最快的那个块，便知道这第 N 个块代表内核地址的值为 N

解决方案：

```shell
由于这个漏洞是由硬件造成的，而执行的入口是用户空间和内核空间共用了一个页表（这样用户空间才可以通过虚拟地址去访问内核）。
所以如果将用户空间和内核空间的页表进行分离，大家各用各的页表那么用户空间就无法通过虚拟地址访问到内核了。(无论用户空间如何访问，它都是访问自己的页表，对应自己代码的物理地址或者就干脆是没有命中的地址)

但这样相当于MMU将内核空间和用户空间隔离为了两个进程一样，当用户空间调用内核空间接口函数时，在切换为特权模式的同时还要切换一次页表。同理，内核处理完成后回到用户空间还要切换一次页表。这样就会消耗很多时间，性能损耗比较大。

需要注意的是：
并不是说进程页表一丁点都不覆盖内核空间了，当进程进行正常合法的系统调用时，这部分逻辑是应该正常运行的。
也就是说进程的页表要进程内核空间的系统调用接口部分以实现正常的访问。
- 而进入到内核这部分代码之后，它会切换到内核页表，内核的页表便是覆盖所有空间的。当调用完成后，又切换回用户态的页表。
```

实例体验:实际代码及操作位于 [宋宝华老师github](https://github.com/21cnbao/meltdown-example)

# Linux内存管理

- 在Linux系统中,进程的 **虚拟4GB内存空间** 被分为两个部分---用户空间和内核空间.
- 用户空间的地址一般分布为0~3GB(即PAGE_OFFSET),剩下的3~4GB为内核空间.  
  + **用户进程只有通过系统调用(代表用户进程在内核态执行)等方式才可以访问到内核空间**.
  + 每个进程的用户空间都是完全独立，互不相干的。****用户进程各自有不同的页表**。而内核空间是由内核负责映射，它并不会跟着进程改变,是固定的。
  + **内核空间的虚拟地址到物理地址的映射是被所有进程共享的，内核虚拟空间独立于其他程序****。

在menuconfig中 `Kernel Features -> Memory split(..)` 可以选择设置 `CONFIG_PAGE_OFFSET` ，默认内核空间就是位于3G~4G空间的。

```c
  //file:arch/arm/include/asm/memory.h
  /* PAGE_OFFSET - the virtual address of the start of the kernel image */
  #define PAGE_OFFSET        UL(CONFIG_PAGE_OFFSET)
```

- 由上面代码也可以知道内核中可以使用 `PAGE_OFFSET` 宏来判断内核虚拟空间的起始地址

## 对物理内存条的分配

- 请注意： **这里说的是物理内存条，不是内存空间**

Linux一般将内存条分为DMA_ZONE, NORMAL_ZONE, HIGH_ZONE3个区, 
[阅码场](https://mp.weixin.qq.com/s/5K7rlPXo2yIcoIXXgqqLfQ) 上有清晰的说明, 
[quora](https://www.quora.com/In-reference-to-Linux-Kernel-what-is-the-difference-between-high-memory-and-normal-memory) 上对此也有解释。

![](./mem_area.jpg)

### DMA_ZONE

DMA_ZONE 是为特定 DMA 划分的区域，某些芯片的 DMA 控制器无法访问全部内存条(有些仅能访问有限的十几兆空间)，所以 Linux 为此类 DMA 规划一片内存.

当实际编写内核代码时，申请 DMA 缓存时使用 `GFP_DMA` 标记，以告知 Linux 在那片固定区域申请。

在内核代码中也有关于此标记的注释(提到了还可以作为紧急后备内存来使用):

```shell
   GFP_DMA exists for historical reasons and should be avoided where possible.
   The flags indicates that the caller requires that the lowest zone be
   used (ZONE_DMA or 16M on x86-64). Ideally, this would be removed but
   it would require careful auditing as some users really require it and
   others use the flag to avoid lowmem reserves in ZONE_DMA and treat the
   lowest zone as a type of emergency reserve.
```

DMA_ZONE 的设置一般在构架目录下的Kconfig中设置，比如 `arch/arm/Kconfig` 具有其使能标记，但在设置前一定要搞清楚具体硬件！

### NORMAL_ZONE

前面说过，在虚拟地址中3~4G为内核空间。 **Linux将物理内存的0~1G线性映射到3G~4G虚拟地址空间** ，而这1G的空间减去 DMA_ZONE 剩下的部分就是 NORMAL_ZONE。 

所谓的线性映射指的就是页表的简单映射关系，一般这种情况下仅仅是一个简单的偏移即可转换，内核提供了函数以相互转换：

```c
  /**
   ,* @note ： 在内核中物理地址都是一个数值，它能以指针操作的只有虚拟地址，
   ,* 所以此处物理地址都是 unsigned long 型
   ,*/
  unsigned long virt_to_phys(volatile void *address);
  void *phys_to_virt(unsigned long address);
```

注意： **线性映射并不是内核已经占用了内存，而是提前映射好以便后面操作,而无需使用时再来映射。**

### HIGH_ZONE

当实际的物理内存大于1G时，多于的部分就是HIGH_ZONE.

当内核空间要使用此段内存时，由于没有提前映射，则需要经过以下步骤使用：

1. 映射HIGH_ZONE到 高端页面映射区
2. 使用
3. 释放映射

注意： 内核对HIGH_ZONE 不能使用 `virt_to_phys,phys_to_virt` 来转换，因为它们不是简单的线性映射!

对于用户空间而言，用户申请内存时，Linux搜寻内存的路径为： HIGH_ZONE -> NORMAL_ZONE -> DMA_ZONE.

## 对内核虚拟空间的分配

### x86-32 架构下的分配

Linux中1GB的虚拟内核地址空间又被划分为:

| 区域名称           | 虚拟地址位置                      | 相关代码              |
| -------------- | --------------------------- | ----------------- |
| 保留区            | FIXADDR_TOP ~ 4GB           | 搜索宏 FIXADDR_TOP   |
| 专用页面映射区        | FIXADDR_START ~ FIXADDR_TOP | 搜索宏 FIXADDR_START |
| 高端内存映射区        | PKMAP_BASE ~ FIXADDR_START  | 搜索宏 PKMAP_BASE    |
| 隔离区            |                             |                   |
| vmalloc虚拟内存分配区 | VMALLOC_START ~ VMALLOC_END | 搜索宏 VMALLOC_START |
| 隔离区            |                             |                   |
| 物理内存映射区        | 3GB起始最大长度896M(对应物理内存的896M)  |                   |

```shell
直接映射的最大896M物理内存分为两个区域：
- 0 ~ 16M : ISA设备用作DMA申请
- 16M ~ 896M : 常规区域
```

- 当系统物理内存超过4GB时，必须使用CPU的扩展分页(PAE)模式所提供的64位页目录才能取到4GB以上的物理内存。

由上表可以看出：此片虚拟区域一共1G，但实际物理内存映射区不足1G(还有其他区域占用了地址空间)。
**如果我们将vmalloc分配区设置得大一点，那么对应物理内存映射区就会小一点。对应的反应到物理内存上，那就是可映射的低端内存区变小了，相应的高端内存区就变大了。**

### arm32 linux 下的分配

| 区域名称              | 虚拟地址位置                         | 相关代码                            |
| ----------------- | ------------------------------ | ------------------------------- |
| 向量表               | 0xfff0000~0xfff0fff            | 文档 Documentation/arm/memory.txt |
| 隔离区               |                                |                                 |
| vmalloc和ioremap区域 | VMALLOC_START ~ VMALLOC_END -1 | 宏 VMALLOC_START                 |
| 隔离区               |                                |                                 |
| DMA和常规区域映射区       | PAGE_OFFSET ~ high_memory -1   | 宏 PAGE_OFFSET 以及变量 high_memory  |
| 高端内存映射区           | PKMAP_BASE ~ PAGE_OFFSET -1    | 宏 PKMAP_BASE                    |
| 内核模块              | MODULES_VADDR ~ MODULES_END -1 | 宏 MODULES_VADDR                 |

由上表可以看出: 

- 对于arm32 来说， **从内核模块开始的地方就已经是内核空间了！**
- 此片虚拟区域一共1G，但实际物理内存映射区不足1G(还有其他区域占用了地址空间)。
  + **如果我们将vmalloc分配区设置得大一点，那么对应物理内存映射区就会小一点。对应的反应到物理内存上，那就是可映射的低端内存区变小了，相应的高端内存区就变大了。**

```shell
  在编译内核的时候可以选择：
  - VMSPLIT_3G : 用户空间3G，内核空间1G。内核模块范围为 3GB-16MB ~ 3GB-2MB,高端内存映射 3GB-2MB ~ 3GB
  - VMSPLIT_2G : 用户空间2G，内核空间2G。内核模块范围为 2GB-16MB ~ 2GB-2MB,高端内存映射 2GB-2MB ~ 2GB

  ARM系统的Linux之所以把内核模块放在16MB范围内，是因为ARM指令在32M以内是短跳转。

  而内核代码位于 3G~3G+6M 的位置，所以将内核模块放在3G-2M ~ 3G-16M之间的内存差异在32M以内，
  这样就实现了内核模块和内核本身的代码段之间的短跳转，以最小的开销实现函数的调用.
```

## DMA、常规、高端内存分布

有以下4种可能的情况分布(地址由低到高)：

- DMA区域 | 常规区域 | 高端内存区域 
  + 内存较大，硬件DMA只能访问一部分地址，并且内核映射不完所有的物理内存，剩下的部分就是高端内存区域
- DMA区域(常规区域) | 高端内存区域
  + 内存较大，硬件DMA可以访问全部地址，但内核映射不完所有的物理内存，剩下的部分就是高端内存区域
- DMA区域 | 常规区域
  + 内存较小，硬件DMA只能访问一部分地址，且内核可以完全映射物理内存
- DMA区域(常规区域)
  + 内存较小，硬件DMA可以访问全部地址，且内核可以完全映射物理内存

### buddy 算法

DMA、常规、高端内存分布区 **最底层** 使用的是 `buddy` 算法进行管理，它将空闲 **页** 面以 2 的 n次方进行分配，而内存申请也是也 2 的 n 次方申请。

- buddy 在不断的拆分和合并，其空闲页面以 1,2,4,8,16... 这种形式组织起来
  + 从16个页面中取出一页后，buddy会拆分为 1,2,4,8 空闲页
  + 如果原来是1,2,8的空闲，现在又释放了2页, **如果这2页和原来空闲的2页内存连续** ，buddy会合并为1,4,8空闲页
- 与此同时， **用户每次申请也只能是2的n次方！**

```shell
在 /proc/buddyinfo 会显示这些区域的空闲页面分布情况,依次从左到右显示 1,2,4,8,16 空闲页数量
```

在内核编程时，可以使用以下函数来申请buddy页(一般不会直接使用)：

```c
  /**
   ,* @brief file: /include/linux/gfp.h
   ,* @note 此处的order就代表2的次方
   ,*/
  struct page * alloc_pages(gfp_t gfp_mask, unsigned int order);
  void free_pages(unsigned long addr, unsigned int order);
```

# 内存申请实际操作

## 用户空间内存动态申请

用户空间的内存申请和释放使用标准的c库即可：

```c
#include <stdlib.h>
//申请
void *malloc(size_t size);
//释放
void free(void *ptr);
```

**Linux内核总是采用按需调页(Demand Paging)，因此当malloc()返回的时候，虽然是成功返回，但是内核并没有真正给这个进程内存。这个时候如果去读申请的内存，内容全部是0，这个页面的映射是只读的。只有当写到某个页面的时候，内核才在页错误后，真正把这个页面给这个进程。**

## 内核空间内存动态申请

### 物理内存连续申请

函数 `kmalloc() 和 __get_free_pages()以及类似函数` 申请的区域位于 `DMA和常规区域的映射区` ，在物理上是连续的，与真实物理地址只有一个固定的偏移。

- kmalloc() 底层依赖于 `__get_free_pages()`

```c
/**
 ,* @brief 申请内存地址
 ,* @param size: 要申请的字节数
 ,* @param flags: 申请的内存类型
 ,* @note flags 一般有以下取值：
 ,* GFP_USER -> 为用户空间页分配内存，可能由于阻塞而导致睡眠
 ,* GFP_KERNEL -> 为内核空间申请内存，可能由于阻塞而导致睡眠
 ,* GFP_ATOMIC -> 原子方式申请内存，若不存在则直接返回而不阻塞(用于中断、tasklet、内核定时器等非进程上下文环境中)
 ,* GFP_HIGHUSER -> 从高端区域中为用户空间分配
 ,* GFP_NOIO -> 申请期间，不允许任何 I/O 初始化
 ,* GFP_NOFS -> 申请期间，不允许任何文件系统调用
 ,* GFP_NOWAIT -> 若不存在空闲页则不等待
 ,* GFP_DMA -> 从DMA区域分配内存
 ,* 还有其他取值请参考文件 include/linux/slab.h
 ,*/
void *kmalloc(size_t size, gfp_t flags);

/**
 ,* @brief 在kmalloc 的基础上申请内存并清零内存
 ,*/
void *kzalloc(size_t size, gfp_t flags);

/**
 ,* @brief 释放kmalloc对应申请的内存
 ,*/
void kfree(const void *);

/**
 ,* @brief 内存的申请管理设备，当设备被释放时内存也跟着自动释放
 ,*/
void *devm_kmalloc(struct device *dev, size_t size, gfp_t gfp);
/**
 ,* @brief 在 devm_kmalloc 的基础上申请内存并清零内存
 ,*/
void *devm_kzalloc(struct device *dev, size_t size, gfp_t gfp);
```

### 物理内存不一定连续申请

函数 `vmalloc()` 申请区域位于 `vmalloc区域` ，在物理上不一定是连续的，与真实物理地址转换关系也不简单。

- vmalloc() 一般只为存在于软件中的(没有对应硬件访问)较大的内存分配
- vmalloc() 效率没有 kmalloc() 高，不适合用来分配小内存
  + 在申请时会内存映射并修改页表
- vmalloc() **不能用在原子上下文中** ，因为它内存实现使用了标志为 `GFP_KERNEL` 的 kmalloc，可能会导致睡眠

```c
void *vmalloc(unsigned long size);
void vfree(const void *addr);
```

### slab机制提高少量字节申请效率

slab机制使得内核中的小对象在前后两次被使用时分配在同一块内存或同一类内存空间且保留了基本的数据结构，大大提高分配效率。

- kmalloc() 就是使用 slab 机制实现的
- 使用 slab机制申请的内存与物理内存之间也是简单的线性偏移关系
- 查看 `/proc/slabinfo` 可以得到当前 slab 分配和使用情况

```c
/**
 ,* @brief 创建一个slab缓存，保留任意数据且全部大小相同的后备缓存
 ,* @param name: 缓存名称，最终会映射在 /proc/slabinfo 中
 ,* @param size: 每个数据结构的大小
 ,* @param aligh: 数据的对齐方式
 ,* @param flags: 申请标记：
 ,* - SLAB_POISON
 ,* - SLAB_RED_ZONE : 
 ,* - SLAB_HWCACHE_ALIGH : 每个数据对象被对齐到一个缓存行
 ,* @param ctor: 对象的构造函数
 ,*/
struct kmem_cache *kmem_cache_create(const char *name, size_t size,
                                     size_t align, unsigned long flags,
                                     void (*ctor)(void *));

void *kmem_cache_alloc(struct kmem_cache *cache, gfp_t flags);
void kmem_cache_free(struct kmem_cache *cache,void *objp);

/**
 ,* @brief 释放 slab 缓存
 ,*/
void kmem_cache_destroy(struct kmem_cache *s);
```

使用例子：

```c
static kmem_cache_t *xxx_cachep;

//! 申请slab缓存池
xxx_cachep = kmem_cache_create("xxx", sizeof(struct xxx), 0, SLAB_HWCACHE_ALIGH | SLAB_PANIC,
                               NULL);
//! 分配对象内存
struct xxx *ctx;
ctx = kmem_cache_alloc(xxx_cachep, GFP_KERNEL);
//! 使用对象内存

//! 释放对象内存
kmem_cache_free(xxx_cachep, ctx);

//! 释放slab缓存池
kmem_cache_destroy(xxx_cachep);
```

内存池技术也是用于分配大量小对象的后备缓存技术。

```c
mempool_t *mempool_create(int min_nr, mempool_alloc_t *alloc_fn,
                          mempool_free_t *free_fn, void *pool_data);

void *mempool_alloc(mempool_t *pool, gfp_t gfp_mask);
void mempool_free(void *element, mempool_t *pool);

void mempool_destroy(mempool_t *pool);
```

# 设备 I/O 端口和 I/O 内存的访问

设备通常会提供一组寄存器来控制设备,读写设备和获取设备状态,这些寄存器可能位于 I/O 空间中,也可能位于内存空间中.

- 当位于I/O 空间时,通常被称为 **I/O端口**;
- 当位于内存空间时,对应的内存空间被称为 **I/O内存**.
- 在使用I/O区域时,需要 **申请该区域** ,以表明驱动要访问这片区域.

## I/O 端口

I/O 端口的具体操作流程为：

1. 申请I/O端口资源
2. 使用读写函数操作I/O端口
3. 释放I/O端口资源

### 申请与释放

```c
//! 向内核申请 n 个端口,这些端口从 start开始,name 参数为设备的名称
//! 获得的地址为结构体类型 struct resource
#define request_region(start,n,name) __request_region(&ioport_resource,(start),(n),(name),0)
//! 释放端口
#define release_region(start,n) __release_region(&ioport_resource, (start), (n))
//! 设备资源释放后自动释放端口资源
#define devm_request_region(dev,start,n,name) __devm_request_region(dev,&ioport_resource,(start),(n),(name))
```

### 读写操作

```c
//!读写一字节端口
unsigned inb(unsigned port);
void outb(unsigned char byte, unsigned port);
//!读写16位端口
unsigned inw(unsigned port);
void outw(unsigned short word, unsigned port);
//!读写32位端口
unsigned inl(unsigned port);
void outl(unsigned longword, unsigned port);
//!读写一串字节
void insb(unsigned port, void *addr, unsigned long count);
void outsb(unsigned port, void *addr, unsigned long count);
//!读写一串16位
void insw(unsigned port, void *addr, unsigned long count);
void outsw(unsigned port, void *addr, unsigned long count);
//!读写一串32位
void insl(unsigned port, void *addr, unsigned long count);
void outsl(unsigned port, void *addr, unsigned long count);
```

## I/O 内存

I/O内存的操作流程为：

1. 申请I/O内存资源
2. 将资源地址映射到内核虚拟空间
3. 使用读写函数操作
4. 释放I/O内存资源

### 申请与释放

```c
//! 申请以start为开始的,n字节的I/O内存区域，名字为name
//! 获得的地址为结构体类型 struct resource
#define request_mem_region(start,n,name) __request_region(&iomem_resource, (start),(n),(name),0)
//! 释放申请的内存
#define release_mem_region(start,n) __release_region(&iomem_resource, (start),(n))

//! 设备资源释放后自动释放端口资源
#define devm_request_mem_region(dev,start,n,name) __devm_request_region(dev,&iomem_resource,(start),(n),(name))
```

### 映射

```c
/**
 ,* @brief 从物理地址 offset处映射size字节内存到内核虚拟内存
 ,* @note ioremap() 与 vmalloc() 类似，也需要新建页表，但不进行内存分配行为。
 ,* 所映射的虚拟地址区为 vmalloc 映射区
 ,*/
void __iomem *ioremap(phys_addr_t offset, size_t size);
//! 取消映射关系
void iounmap(void __iomem *addr);
//! 当设备资源释放后自动取消映射关系
void __iomem *devm_ioremap(struct device *dev, resource_size_t offset, resource_size_t size);
```

### 读写操作函数

```c
/**
 ,* @brief 分别读写 8,16,32,64 位
 ,*/
u8  readb(const volatile void _iomem *addr);
u16 readw(const volatile void _iomem *addr);
u32 readl(const volatile void _iomem *addr);
u64 readq(const volatile void _iomem *addr);

void writeb(u8  value, volatile void __iomem *addr);
void writew(u16 value, volatile void __iomem *addr);
void writel(u32 value, volatile void __iomem *addr);
void writeq(u64 value, volatile void __iomem *addr);
```

## 将设备地址映射到用户空间

驱动可以通过mmap()函数来给用户空间提供设备的虚拟地址，以达到间接访问的目的。

mmap()实现这样一个映射的过程：将用户空间的一段内存与设备内存关联，当用户访问用户空间的这段地址范围时，
实际上会转化为对设备的访问。

```shell
一般这样做的目的并不是为了用户空间来直接控制寄存器，因为这就破坏了分层的原则。

一般就用于将内核空间申请的内存映射到用户空间，这样用户可以直接高效的参与内存读写，避免再进行一次数据搬移。
比如：用户空间直接读写DMA收发的数据。
```

### 内存映射与VMA

```c
//! 内核 file_operatoins 中的 mmap()
int (*mmap)(struct file *, struct vm_area_struct *);

//! 用户空间的 mmap()

/**
 ,* @brief 从内核空间映射一段内存到用户空间
 ,* @param addr : 映射到用户空间以 addr 为起始，为NULL则自动分配
 ,* @param length: 映射的字节数
 ,* @param prot: 内存访问权限
 ,* - PROT_NONE : 不可访问
 ,* - PROT_EXEC : 可以执行
 ,* - PROT_READ : 可读
 ,* - PROT_WRITE: 可写
 ,* @param flags : 内存状态
 ,* - MAP_SHARED : 可被进程共享
 ,* - MAP_PRIVATE: 非共享
 ,* @param fd: 打开的文件索引
 ,* @param offset: 从内核的 offset 偏移处开始映射
 ,* @return 申请的地址
 ,*/
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);

/**
 ,* @brief 取消映射
 ,*/
int munmap(void *addr, size_t length);
```

当用户调用 mmap()的时候,内核会进行如下处理.

1. 在进程的虚拟空间查找一块 VMA
2. 将这块VMA进行映射
3. 如果设备驱动程序或者文件系统的file_operations定义了mmap()操作,则调用它
4. 将这个VMA插入进程的VMA链表中

驱动中的mmap()的实现机制是建立页表,并填充VMA结构体中 `vm_operations_struct` 指针.

```C
//! 用于描述一个虚拟内存区域
struct vm_area_struct
{
        /*The first cache line has the info for VMA tree walking.*/
        unsigned long vm_start;/*Our start address within vm_mm.*/
        unsigned long vm_end;/*The first byte after our end address within vm_mm*/
        /* lnked list of VM areas per task, sorted by address*/
        struct vm_area_struct *vm_next,*vm_prev;
        struct rb_node vm_rb;
        ...
};
```

VMA结构体描述的虚拟地址介于 vm_start 和 vm_end之间,其 vm_ops 成员指向这个VMA的操作集, 针对VMA的操作都被包含在 vm_operations_struct 结构体中.

操作范例:

```C
static int xxx_mmap(stuct file *filp, struct vm_area_struct *vma)
{
// 创建页表项
        if(remap_pfn_range(vma, vma->vm_start, vm->vm_pgoff, vma->vm_end -
                           vma->vm_start, vma->vm_page_prot))
                return -EAGAIN;
        vma->vm_ops = &xxx_remap_vm_ops;
        xxx_vma_open(vma);
        return 0;
}

// 在用户空间使用 mmap()的时候被用到
static void xxx_vma_open(struct vm_area_struct *vma)
{
        ...
        printk(KERN_NOTICE "xxx VMA open, virt %lx, phys %lx\n", vma->vm_start, vma->vm_pgoff << PAGE_SHIFT);
}
// 在用户空间使用 munmap()的时候被用到
static void xxx_vma_close(struct vm_area_struct *vma)
{
        ...
        printk(KERN_NOTICE "xxx VMA close.\n");
}
static struct vm_operations_struct xxx_remap_vm_ops =
{
        .open = xxx_vma_open,
        .close = xxx_vma_close,
        ...
};
```

### fault() 函数

fault() 函数可以为设备提供更加灵活的内存映射途径。
当访问的页不在内存时，fault()会被内核自动调用。

当发生缺页时，流程为：

1. 找到缺页的虚拟地址所在的VMA
2. 如果必要分配中间页目录表和页表
3. 如果页表项对应的物理页面不存在，则调用 fault() 函数，它返回物理页面的页描述符
4. 将物理页面地址填充到页表中

# I/O内存静态映射

在将linux移植到目标电路板的过程中,有的会建立外设I/O内存物理地址到虚拟地址的静态映射,这个映射通过在与电路板对应的 map_desc 结构体数组中添加新的成员完成.

```C
struct map_desc{
        unsigned long virtual;  //虚拟地址
        unsigned long pfn;     //__phys_to_pfn(phy_addr)
        unsigned long length;  //内存大小
        unsigned int type;     //内存类型
};
```

# DMA内存

## DMA与硬件Cache一致性

1. 在DMA不工作的情况下或者DMA与Cache相对应的主存没有重叠区, 那么Cache 与主存中的数据具有一致性特点.二者并不会起冲突.
2. ***当DMA与Cache相对应的主存有重叠区时,当DMA更新了重叠区的内容,而Cache并没有对应的更新.此时CPU仍然使用的是陈旧的cache的数据,就会发生Cache与内存之间数据"不一致性"的错误!**
   + 当CPU向内存写数据时，此时也是先写到了cache，DMA传输数据到外设依然是原来陈旧的数据
   + 在发生Cache与内存不一致性错误后,驱动将无法正常运行.
3. Cache的不一致问题并不是只发生在DMA的情况下,实际上,它还存在于Cache使能和关闭的时刻.例如,对于带MMU功能的ARM处理器,在开启 *MMU之前需要先置Cache无效,否则在开启MMU之后,Cache里面有可能保存的还是之前的物理地址,这也会造成不一致性的错误!*.

## Linux 下的DMA编程(*DMA只是一种外设与内存的交互方式*)

内存中用于外设交互数据的一块区域称为 DMA 缓冲区, ***在设备不支持scatter/gather操作的情况下,DMA缓冲区在物理上必须上连续的.***

- 当硬件支持 `IOMMU` 时，缓冲区也可以不连续

### DMA区域

对于大多数现代嵌入式处理器而言,DMA操作可以在整个常规内存区域进行,因此DMA区域就直接覆盖了常规内存.

### 虚拟地址,物理地址,总线地址

- 总线地址： 基于DMA硬件使用的是总线地址而不是物理地址，是从设备角度上看到的内存地址
- 物理地址：是从CPU MMU 控制器外围角度上看到的内存地址
- 虚拟地址：CPU看到的是MMU反映给它的地址

### DMA地址掩码

设备不一定能在所有的内存地址上执行DMA操作,在这种情况下需要设置DMA能够操作的地址总线宽度.

```c
int dma_set_mask(struct device *dev, u64 mask)
```

如果DMA只能操作24位地址,那么就应该调用 `dma_set_mask(dev,0xffffff)`

- 此时内核会为申请增加 `GFP_DMA` 标记，以从 DMA_ZONE 中申请内存
  
  ### 一致性DMA缓冲区
  
  为了能够避免 *DMA与Cache一致性问题*,使用如下函数分配一个DMA一致性的内存区域:

- 操作此函数的过程是不用关心CMA区域设置，这个是内核底层完成的。
  
  ```C
  /*
    申请一致性DMA缓冲区(一般不带cache, 但如果有 cache coherent interconnect 硬件支持，则就可以带cache)
    note: 这段缓存区一般是连续的，但如果硬件带IOMMU,则也可以是不连续的
   ,*/
  //返回申请到的DMA缓冲区的虚拟地址
  //handle 代表总线地址
  void *dma_alloc_coherent(struct device *dev, size_t size, dma_addr_t *handle, gfp_t gfp);
  
  //释放申请的内存
  void dma_free_coherent(struct device *dev,size_t size, void *cpu_addr, dma_addr_t handle);
  
  /*
    分配一个写合并(writecombining)的DMA缓冲区
   ,*/
  void *dma_alloc_writecombine(struct device *dev, size_t size, dma_addr_t *handle, gfp_t gfp);
  
  //释放
  void dma_free_writecombine(struct device *dev,size_t size, void *cpu_addr, dma_addr_t handle);
  
  /*
    PCI设备申请缓冲区
  ,*/
  void *pci_alloc_consistent(struct pci_dev *pdev, size_t size, dma_addr_t *dma_addrp);
  
  //释放
  void pci_free_consisten(struct pci_dev *pdev, size_t size, void *cpu_addr, dma_addr_t dma_addr);
  ```

**注意**:

`dma_alloc_xxx()` 函数虽然是以 dma_alloc_开头, **但是其申请的区域不一定在DMA区域里面**.以32位ARM处理器为例,当conherent_dma_mask小于0xffffffff时,才会设置GFP_DMA标记,并从DMA区域去申请内存.

### 流式DMA映射

在许多情况下缓冲区来自内核的较上层，上层很可能以普通的 kmalloc() 等方式申请内存，
也就是说这段内存是具有硬件cache的，这时就需要使用流式DMA。

流式DMA操作在本质上大多就是进行flush或invalidate Cache操作，以解决一致性问题。

- flush 是指将cache内容写入内存，invalidate是指让CPU再次从内存读取数据来刷新一次cache
- 如果有 `cache coherent interconnect` 硬件，则不需要关闭cache，从应用编程的角度来讲，只要按照规矩来操作即可。

操作步骤为：

1. 进行流式DMA映射
2. 执行DMA操作
3. 取消映射

```c
  //一片内存操作
  #define dma_map_single(d, a, s, r) dma_map_single_attrs(d, a, s, r, NULL)
  #define dma_unmap_single(d, a, s, r) dma_unmap_single_attrs(d, a, s, r, NULL)

  //多片非连续内存操作
  #define dma_map_sg(d, s, n, r) dma_map_sg_attrs(d, s, n, r, NULL)
  #define dma_unmap_sg(d, s, n, r) dma_unmap_sg_attrs(d, s, n, r, NULL)
```

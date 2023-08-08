---
title: Linux内核调试之 initcall_debug
tags: 
 - linux
categories:
 - linux
 - kernel
 - debug
date: 2023/8/4
updated: 2023/8/8
layout: true
comments: true
---

- kernel version : v6.1.x (lts)

初步认识 initcall_debug 的实现机制。

<!--more-->

# u-boot 对 chosen 的修改

当 u-boot 使能设备树功能，且环境变量中具有 `bootargs` 时，u-boot 就会主动将设备树中的`bootargs`参数修改为自己环境变量的值。

一般现在都是使用设备树中的参数，所以需要将该环境变量从 u-boot 中删除，避免造成误导。

关于 u-boot 修改的代码路径如下：

```shell
-> /cmd/bootz.c: do_bootz()
-> /boot/bootm.c: do_bootm_states()
-> /boot/bootm_os.c: bootm_os_get_boot_func()
-> /arch/arm/lib/bootm.c: do_bootm_linux()
-> /arch/arm/lib/bootm.c: boot_prep_linux()
-> /boot/image-borad.c: image_setup_linux()
-> /boot/image-fdt.c: image_setup_libfdt()
-> /common/fdt_support.c: fdt_chosen()
```

```c
int fdt_chosen(void *fdt)
{
	struct abuf buf = {};
	int   nodeoffset;
	int   err;
	char  *str;		/* used to set string properties */

	// 对设备树进行检查
	err = fdt_check_header(fdt);
	if (err < 0) {
		printf("fdt_chosen: %s\n", fdt_strerror(err));
		return err;
	}

	// 查找或创建 chose 节点
	nodeoffset = fdt_find_or_add_subnode(fdt, 0, "chosen");
	if (nodeoffset < 0)
		return nodeoffset;

	if (IS_ENABLED(CONFIG_BOARD_RNG_SEED) && !board_rng_seed(&buf)) {
		err = fdt_setprop(fdt, nodeoffset, "rng-seed",
				  abuf_data(&buf), abuf_size(&buf));
		abuf_uninit(&buf);
		if (err < 0) {
			printf("WARNING: could not set rng-seed %s.\n",
			       fdt_strerror(err));
			return err;
		}
	}

	// 获取 bootargs 环境变量
	str = board_fdt_chosen_bootargs();

	// 如果有该环境变量，则使用环境变量的 bootargs 替代 chosen 节点中的值
	if (str) {
		err = fdt_setprop(fdt, nodeoffset, "bootargs", str,
				  strlen(str) + 1);
		if (err < 0) {
			printf("WARNING: could not set bootargs %s.\n",
			       fdt_strerror(err));
			return err;
		}
	}

	// 增加 u-boot 的版本号
	err = fdt_setprop(fdt, nodeoffset, "u-boot,version", PLAIN_VERSION,
			  strlen(PLAIN_VERSION) + 1);
	if (err < 0) {
		printf("WARNING: could not set u-boot,version %s.\n",
		       fdt_strerror(err));
		return err;
	}

	return fdt_fixup_stdout(fdt, nodeoffset);
}
```


# kernel 获取参数的代码调用路径

以 `arm32` 为例，其调用路径为：

```shell
-> /init/main.c: start_kernel()
-> /arch/arm/kernel/setup.c: setup_arch()
-> /arch/arm/kernel/devtree.c: setup_machine_fdt()
-> /drivers/of/fdt.c: early_init_dt_scan_nodes()
```




# 传入参数的存储位置

设备树的参数最终存储于数组 `boot_command_line` ，而对应的命令参数则存在于设备树的 `/chosen` 中。

> 如果 `/chosen` 不存在则会搜寻节点 `/chosen@0`

``` c
char __initdata boot_command_line[COMMAND_LINE_SIZE];

int __init early_init_dt_scan_chosen(char *cmdline)
{
	int l, node;
	const char *p;
	const void *rng_seed;
	const void *fdt = initial_boot_params;

	node = fdt_path_offset(fdt, "/chosen");
	if (node < 0)
		node = fdt_path_offset(fdt, "/chosen@0");
	if (node < 0)
		/* Handle the cmdline config options even if no /chosen node */
		goto handle_cmdline;

	chosen_node_offset = node;

	early_init_dt_check_for_initrd(node);
	early_init_dt_check_for_elfcorehdr(node);

	rng_seed = of_get_flat_dt_prop(node, "rng-seed", &l);
	if (rng_seed && l > 0) {
		add_bootloader_randomness(rng_seed, l);

		/* try to clear seed so it won't be found. */
		fdt_nop_property(initial_boot_params, node, "rng-seed");

		/* update CRC check value */
		of_fdt_crc32 = crc32_be(~0, initial_boot_params,
				fdt_totalsize(initial_boot_params));
	}

	/* Retrieve command line */
	p = of_get_flat_dt_prop(node, "bootargs", &l);
	if (p != NULL && l > 0)
		strscpy(cmdline, p, min(l, COMMAND_LINE_SIZE));

handle_cmdline:
	/*
	 * CONFIG_CMDLINE is meant to be a default in case nothing else
	 * managed to set the command line, unless CONFIG_CMDLINE_FORCE
	 * is set in which case we override whatever was found earlier.
	 */
#ifdef CONFIG_CMDLINE
#if defined(CONFIG_CMDLINE_EXTEND)
	strlcat(cmdline, " ", COMMAND_LINE_SIZE);
	strlcat(cmdline, CONFIG_CMDLINE, COMMAND_LINE_SIZE);
#elif defined(CONFIG_CMDLINE_FORCE)
	strscpy(cmdline, CONFIG_CMDLINE, COMMAND_LINE_SIZE);
#else
	/* No arguments from boot loader, use kernel's  cmdl*/
	if (!((char *)cmdline)[0])
		strscpy(cmdline, CONFIG_CMDLINE, COMMAND_LINE_SIZE);
#endif
#endif /* CONFIG_CMDLINE */

	pr_debug("Command line is: %s\n", (char *)cmdline);

	return 0;
}

void __init early_init_dt_scan_nodes(void)
{
	int rc;

	/* Initialize {size,address}-cells info */
	early_init_dt_scan_root();

	/* Retrieve various information from the /chosen node */
	rc = early_init_dt_scan_chosen(boot_command_line);
	if (rc)
		pr_warn("No chosen node found, continuing without\n");

	/* Setup memory, calling early_init_dt_add_memory_arch */
	early_init_dt_scan_memory();

	/* Handle linux,usable-memory-range property */
	early_init_dt_check_for_usable_mem_range();
}
```

# 截取 initcall_debug 设置

## 作用

在文档 `Documentation/admin-guide/kernel-parameters.txt` 中说明了 `initcall_debug` 命令参数的作用:

``` shell
	initcall_debug	[KNL] Trace initcalls as they are executed.  Useful
			for working out where the kernel is dying during
			startup.
```

简单来说就是可以展示初始化函数的执行。

## 定义

在 `init/main.c` 中定义了标志位， `initcall_debug` :

``` c
bool initcall_debug;
core_param(initcall_debug, initcall_debug, bool, 0644);
```

将上面的宏 `core_param` 展开为如下代码:

``` c
struct kernel_param {
	const char *name;
	struct module *mod;
	const struct kernel_param_ops *ops;
	const u16 perm;
	s8 level;
	u8 flags;
	union {
		void *arg;
		const struct kparam_string *str;
		const struct kparam_array *arr;
	};
};

// 对 bool 类型的操作
const struct kernel_param_ops param_ops_bool = {
	.flags = KERNEL_PARAM_OPS_FL_NOARG,
	.set = param_set_bool,
	.get = param_get_bool,
};
EXPORT_SYMBOL(param_ops_bool);

//此处指定了命令行的字符串
static const char __param_str_initcall_debug[] = "initcall_debug";

static struct kernel_param __moduleparam_const __param_initcall_debug	
__used __section("__param")					
__aligned(__alignof__(struct kernel_param))			
= 
{ 
	__param_str_initcall_debug, 		// 名称 
	THIS_MODULE, 						// 所属模块
	&param_ops_bool,					// 操作方法
	VERIFY_OCTAL_PERMISSIONS(0644), 	// 权限
	-1, 
	0, 
	{ &initcall_debug } 				// 对象的地址
};	
```

根据以上代码可以推断出:
- 可以查看 `/sys/module/kernel/parameters/initcall_debug` 值的方式以判定此参数是否已经被设置
- 代码中一定有某处通过操作 `__param` 段来获取内核 `param` 的各项设置

## 获取值
注意到此变量以及其对应的链接脚本:

``` c
extern const struct kernel_param __start___param[], __stop___param[];

/* Built-in module parameters. */				\
__param : AT(ADDR(__param) - LOAD_OFFSET) {			\
	__start___param = .;					\
	KEEP(*(__param))					\
	__stop___param = .;					\
}		
```

就可以知道，一定有代码来从 `__start___param` 到 `__stop___param` 中取出 `kernel_param` 依次解析变量。

这就又回到了 `start_kernel` 函数中的一段:
``` c
	pr_notice("Kernel command line: %s\n", saved_command_line);
	/* parameters may set static keys */
	jump_label_init();
	parse_early_param();
	after_dashes = parse_args("Booting kernel",
				  static_command_line, __start___param,
				  __stop___param - __start___param,
				  -1, -1, NULL, &unknown_bootoption);
	print_unknown_bootoptions();
```

- 也可以看出，通过启动时的 "Kernel command line:" 字符串也可以查看命令设置

也一定会有代码，将这些变量加入到 sysfs 中：

```c
/*
 * param_sysfs_builtin - add sysfs parameters for built-in modules
 *
 * Add module_parameters to sysfs for "modules" built into the kernel.
 *
 * The "module" name (KBUILD_MODNAME) is stored before a dot, the
 * "parameter" name is stored behind a dot in kernel_param->name. So,
 * extract the "module" name for all built-in kernel_param-eters,
 * and for all who have the same, call kernel_add_sysfs_param.
 */
static void __init param_sysfs_builtin(void)
{
	const struct kernel_param *kp;
	unsigned int name_len;
	char modname[MODULE_NAME_LEN];

	for (kp = __start___param; kp < __stop___param; kp++) {
		char *dot;

		if (kp->perm == 0)
			continue;

		dot = strchr(kp->name, '.');
		if (!dot) {
			/* This happens for core_param() */
			strcpy(modname, "kernel");
			name_len = 0;
		} else {
			name_len = dot - kp->name + 1;
			strlcpy(modname, kp->name, name_len);
		}
		kernel_add_sysfs_param(modname, kp, name_len);
	}
}
```

# 使用 initcall_debug

在进行初始化执行之前会有对变量 `initcall_debug` 的判断:

``` c

static __init_or_module void
trace_initcall_start_cb(void *data, initcall_t fn)
{
	ktime_t *calltime = data;

	printk(KERN_DEBUG "calling  %pS @ %i\n", fn, task_pid_nr(current));
	*calltime = ktime_get();
}

static __init_or_module void
trace_initcall_finish_cb(void *data, initcall_t fn, int ret)
{
	ktime_t rettime, *calltime = data;

	rettime = ktime_get();
	printk(KERN_DEBUG "initcall %pS returned %d after %lld usecs\n",
		 fn, ret, (unsigned long long)ktime_us_delta(rettime, *calltime));
}

static inline void do_trace_initcall_start(initcall_t fn)
{
	if (!initcall_debug)
		return;
	trace_initcall_start_cb(&initcall_calltime, fn);
}
static inline void do_trace_initcall_finish(initcall_t fn, int ret)
{
	if (!initcall_debug)
		return;
	trace_initcall_finish_cb(&initcall_calltime, fn, ret);
}

int __init_or_module do_one_initcall(initcall_t fn)
{
	int count = preempt_count();
	char msgbuf[64];
	int ret;

	if (initcall_blacklisted(fn))
		return -EPERM;

	do_trace_initcall_start(fn);
	ret = fn();
	do_trace_initcall_finish(fn, ret);

	msgbuf[0] = 0;

	if (preempt_count() != count) {
		sprintf(msgbuf, "preemption imbalance ");
		preempt_count_set(count);
	}
	if (irqs_disabled()) {
		strlcat(msgbuf, "disabled interrupts ", sizeof(msgbuf));
		local_irq_enable();
	}
	WARN(msgbuf[0], "initcall %pS returned with %s\n", fn, msgbuf);

	add_latent_entropy();
	return ret;
}
```

当 `initcall_debug` 为 `true` 时则会打印函数名以及其执行的时间。

需要注意的是: **此处使用的printk 的等级是 KERN_DEBUG,所以为了能够打印信息通常是 "loglevel=8 initcall_debug" 结合使用!**

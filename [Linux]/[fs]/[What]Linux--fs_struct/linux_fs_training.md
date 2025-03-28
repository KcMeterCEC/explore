---
title: Linux文件系统基本脉络
tags: 
- linux
categories:
- linux
- fs
- overview
date: 2024/9/17
updated: 2024/9/17
layout: true
comments: true
---



记录从上层用户操作到底层文件系统之间的调用流程以及数据流。
![](./vfs_fileoperations.jpg)

<!--more-->

# simplefs 实战

[simplefs][https://github.com/psankar/simplefs] 用最少的代码实现了文件系统的基本操作。

## 基本体验

### 创建一个硬盘

目前使用 `dd` 命令创建一个块大小为 4096字节，共100个块的硬盘文件。

```shell
  #bs 指定一个块的大小
  #count 指定块数目
  #if 输入文件内容， /dev/zero 会不断输出0
  #of 输出文件名
  #此命令可以用来测试内存的操作速度
  dd bs=4096 count=100 if=/dev/zero of=image
```

### 格式化并挂载

```shell
make 
./mkfs-simplefs image
mkdir mount
sudo insmod simplefs.ko 
mount -o loop -t simplefs image ./mount
```

### 查看内容

接下来就是以root的身份进入到 `mount` 文件夹，便可以查看其文件及文件内容。

## 格式化代码分析(mkfs-simplefs.c)

其格式化的步骤为：

1. 写入superblock 的内容
2. 写根目录inode
3. 写文件inode
4. 写根目录block
5. 写文件block

### 写 superblock

此函数将一个block来保存superblock的信息。

``` c
#define SIMPLEFS_MAGIC 0x10032013
#define SIMPLEFS_DEFAULT_BLOCK_SIZE 4096
struct simplefs_super_block {
        uint64_t version; //版本号
        uint64_t magic; //魔数
        uint64_t block_size;//super block 信息所占用的块大小

        /* FIXME: This should be moved to the inode store and not part of the sb */
        uint64_t inodes_count;//目前已经使用了多少个inode

        uint64_t free_blocks;//目前还剩下多少个block

        //此部分是为了填充结构体，使整个结构体大小为4096字节
        char padding[SIMPLEFS_DEFAULT_BLOCK_SIZE - (5 * sizeof(uint64_t))];
};
static int write_superblock(int fd)
{
        struct simplefs_super_block sb = {
                .version = 1,
                .magic = SIMPLEFS_MAGIC,
                .block_size = SIMPLEFS_DEFAULT_BLOCK_SIZE,
                /* One inode for rootdirectory and another for a welcome file that we are going to create */
                .inodes_count = 2,//使用一个inode对应根目录，一个inode对应一个文件
                /* FIXME: Free blocks management is not implemented yet */
                .free_blocks = (~0) & ~(1 << WELCOMEFILE_DATABLOCK_NUMBER),
        };
        ssize_t ret;

        ret = write(fd, &sb, sizeof(sb));
        if (ret != SIMPLEFS_DEFAULT_BLOCK_SIZE) {
                printf
                        ("bytes written [%d] are not equal to the default block size\n",
                         (int)ret);
                return -1;
        }

        printf("Super block written succesfully\n");
        return 0;
}
```

### 写根文件inode

根文件的inode紧接着superblock 往后填充，也就是在第2个block中存储inode.

``` c
struct simplefs_inode {
        mode_t mode; //此inode表示的档案类型
        uint64_t inode_no;//inode的索引号
        uint64_t data_block_number;//与inode对应的block的索引号

        union {//文件大小或是目录对应的内容对
                uint64_t file_size;
                uint64_t dir_children_count;
        };
};
const int SIMPLEFS_ROOTDIR_INODE_NUMBER = 1;
const int SIMPLEFS_ROOTDIR_DATABLOCK_NUMBER = 2;
const int SIMPLEFS_INODESTORE_BLOCK_NUMBER = 1;
static int write_inode_store(int fd)
{
        ssize_t ret;

        struct simplefs_inode root_inode;

        root_inode.mode = S_IFDIR;
        root_inode.inode_no = SIMPLEFS_ROOTDIR_INODE_NUMBER;
        root_inode.data_block_number = SIMPLEFS_ROOTDIR_DATABLOCK_NUMBER;
        root_inode.dir_children_count = 1;

        ret = write(fd, &root_inode, sizeof(root_inode));

        if (ret != sizeof(root_inode)) {
                printf
                        ("The inode store was not written properly. Retry your mkfs\n");
                return -1;
        }

        printf("root directory inode written succesfully\n");
        return 0;
}
```

### 写文件inode

通过此函数可以看出：所有的inode都存储在一个block中，而一个inode大小为 `28` 字节。
也就是说，此文件系统最多支持文件和文件夹的总数为 `4096 / 28 = 146 `

``` c
#define SIMPLEFS_DEFAULT_BLOCK_SIZE 4096
const uint64_t WELCOMEFILE_INODE_NUMBER = 2;//文件inode为2号
const uint64_t WELCOMEFILE_DATABLOCK_NUMBER = 3;//文件内容block
char welcomefile_body[] = "Love is God. God is Love. Anbe Murugan.\n";
struct simplefs_inode welcome = {
        .mode = S_IFREG,
        .inode_no = WELCOMEFILE_INODE_NUMBER,
        .data_block_number = WELCOMEFILE_DATABLOCK_NUMBER,
        .file_size = sizeof(welcomefile_body),
};
static int write_inode(int fd, const struct simplefs_inode *i)
{
        off_t nbytes;
        ssize_t ret;

        ret = write(fd, i, sizeof(*i));
        if (ret != sizeof(*i)) {
                printf
                        ("The welcomefile inode was not written properly. Retry your mkfs\n");
                return -1;
        }
        printf("welcomefile inode written succesfully\n");

        //算出需要移动到block尾需要多少字节(依次减去root inode 和 welcome inode)
        nbytes = SIMPLEFS_DEFAULT_BLOCK_SIZE - sizeof(*i) - sizeof(*i);
        ret = lseek(fd, nbytes, SEEK_CUR);
        if (ret == (off_t)-1) {
                printf
                        ("The padding bytes are not written properly. Retry your mkfs\n");
                return -1;
        }

        printf
                ("inode store padding bytes (after the two inodes) written sucessfully\n");
        return 0;
}
```

### 写根目录block

写根目录block就是写文件名以及其inode的索引,一个名称对的大小为 `264` 字节，
也就是说一个目录最多可以存储的名称对为 `4096 / 264 = 15` 个，也就是说一个目录
最多存储15个文件或目录名。

``` c
#define SIMPLEFS_FILENAME_MAXLEN 255 //文件名的最大长度
struct simplefs_dir_record {
        char filename[SIMPLEFS_FILENAME_MAXLEN];
        uint64_t inode_no;//文件名以及其对应的block索引
};
struct simplefs_dir_record record = {
        .filename = "vanakkam",
        .inode_no = WELCOMEFILE_INODE_NUMBER,
};
int write_dirent(int fd, const struct simplefs_dir_record *record)
{
        ssize_t nbytes = sizeof(*record), ret;

        ret = write(fd, record, nbytes);
        if (ret != nbytes) {
                printf
                        ("Writing the rootdirectory datablock (name+inode_no pair for welcomefile) has failed\n");
                return -1;
        }
        printf
                ("root directory datablocks (name+inode_no pair for welcomefile) written succesfully\n");

        nbytes = SIMPLEFS_DEFAULT_BLOCK_SIZE - sizeof(*record);
        ret = lseek(fd, nbytes, SEEK_CUR);//移动到下一个block
        if (ret == (off_t)-1) {
                printf
                        ("Writing the padding for rootdirectory children datablock has failed\n");
                return -1;
        }
        printf
                ("padding after the rootdirectory children written succesfully\n");
        return 0;
}
```

### 写文件block 

写文件block就是把文件内容写进去即可。

``` c
int write_block(int fd, char *block, size_t len)
{
        ssize_t ret;

        ret = write(fd, block, len);
        if (ret != len) {
                printf("Writing file body has failed\n");
                return -1;
        }
        printf("block has been written succesfully\n");
        return 0;
}
```

## 文件系统的结构

根据上面的格式化代码，可以知道其结构如下图：

！[](./simplefs_struct.jpg)

可以看出此文件系统的确是足够的简单：

1. superblock描述极为简单
2. 并不具备block bitmap 和 inode bitmap
3. 最多支持的文件和文件夹总数为146个(因为仅用了一个block来存储inode)
4. 一个文件夹中可以存储的文件和文件夹总数为15个
5. 一个文件的内容不能超过一个block

### 文件系统操作逻辑

根据以上简单结构的分析，可以猜测出其基本的文件操作逻辑：

1. 新建文件夹
  + 从inode table 中填充一个文件夹类型的inode并获取其索引
  + 为此索引的inode分配一个block并写入对应的inode
  + 将新建文件夹的名称和inode索引对应存储在当前文件夹的block中
  + 更新 superblock 中的inode计数
2. 新建文件
  + 从inode table 中填充一个文件类型的inode并获取其索引
  + 为此索引的inode分配一个block并写入对应的inode
  + 将文件内容写入其block中
  + 将新建文件的名称和inode索引对应存储在当前文件夹的block中
  + 更新 superblock 中的inode计数
3. 删除文件或文件夹
  + 去除当前文件夹中对应此文件或文件夹的描述字符串
  + 更新 superblock 中的inode计数
4. 建立硬链接
  + 在当前文件夹下拷贝一份目标文件所在的文件夹中对于此文件的描述字符串
5. 建立符号链接
  + 首先新建一个文件
  + 然后新建文件的内容指向目标文件所在的文件夹的inode

基于这些猜测，接下来分析其文件系统操作代码。

## 操作代码分析(simple.c)

### 挂载
在载入模块时，会首先使用函数 ·kmem_cache_create· ，用于为文件系统的inode申请缓存以便达到快速访问的目的。

``` c
sfs_inode_cachep = kmem_cache_create("sfs_inode_cache",
                                     sizeof(struct simplefs_inode),
                                     0,
                                     (SLAB_RECLAIM_ACCOUNT| SLAB_MEM_SPREAD),
                                     NULL);
```

在挂载文件时，会调用函数 `simplefs_fill_super` 函数，此函数的主要目的就是填充 `super_block` 结构体

``` c
/* This function, as the name implies, Makes the super_block valid and
 ,* fills filesystem specific information in the super block */
int simplefs_fill_super(struct super_block *sb, void *data, int silent)
{
        struct inode *root_inode;
        struct buffer_head *bh;
        struct simplefs_super_block *sb_disk;
        int ret = -EPERM;

        //从存储super block 描述的block(0)中读取数据
        bh = sb_bread(sb, SIMPLEFS_SUPERBLOCK_BLOCK_NUMBER);
        BUG_ON(!bh);

        //得到 simplefs_super_block 具体内容
        sb_disk = (struct simplefs_super_block *)bh->b_data;

        printk(KERN_INFO "The magic number obtained in disk is: [%llu]\n",
               sb_disk->magic);

        if (unlikely(sb_disk->magic != SIMPLEFS_MAGIC)) {
                printk(KERN_ERR
                       "The filesystem that you try to mount is not of type simplefs. Magicnumber mismatch.");
                goto release;
        }

        if (unlikely(sb_disk->block_size != SIMPLEFS_DEFAULT_BLOCK_SIZE)) {
                printk(KERN_ERR
                       "simplefs seem to be formatted using a non-standard block size.");
                goto release;
        }

        printk(KERN_INFO
               "simplefs filesystem of version [%llu] formatted with a block size of [%llu] detected in the device.\n",
               sb_disk->version, sb_disk->block_size);

        /* A magic number that uniquely identifies our filesystem type */
        sb->s_magic = SIMPLEFS_MAGIC;

        /* For all practical purposes, we will be using this s_fs_info as the super block */
        //设为私有地址，以便后面使用
        sb->s_fs_info = sb_disk;

        //最大的文件大小就是为一个block
        sb->s_maxbytes = SIMPLEFS_DEFAULT_BLOCK_SIZE;
        //super block 操作
        sb->s_op = &simplefs_sops;

        root_inode = new_inode(sb);
        //跟目录的inode位置
        root_inode->i_ino = SIMPLEFS_ROOTDIR_INODE_NUMBER;
        inode_init_owner(root_inode, NULL, S_IFDIR);
        root_inode->i_sb = sb;
        //根目录inode操作
        root_inode->i_op = &simplefs_inode_ops;
        //根目录操作
        root_inode->i_fop = &simplefs_dir_operations;
        root_inode->i_atime = root_inode->i_mtime = root_inode->i_ctime =
                CURRENT_TIME;

        //得到根目录的inode内容(并且会将此inode放入inode cache 中)
        root_inode->i_private =
                simplefs_get_inode(sb, SIMPLEFS_ROOTDIR_INODE_NUMBER);

        /* TODO: move such stuff into separate header. */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 3, 0)
        sb->s_root = d_make_root(root_inode);
        #else
        sb->s_root = d_alloc_root(root_inode);
        if (!sb->s_root)
                iput(root_inode);
        #endif

        if (!sb->s_root) {
                ret = -ENOMEM;
                goto release;
        }

        ret = 0;
release:
        brelse(bh);

        return ret;
}
```

其数据填充结果如下图：

![](./struct_super_block.jpg)

在 `super.h` 中有以下两个操作,对照上图就可以看出其意义：

``` c
//获取 simplefs_super_block 结构体地址
static inline struct simplefs_super_block *SIMPLEFS_SB(struct super_block *sb)
{
        return sb->s_fs_info;
}

//获取文件或目录 inode的地址
static inline struct simplefs_inode *SIMPLEFS_INODE(struct inode *inode)
{
        return inode->i_private;
}
```

### 读取文件夹内容

为了获取文件夹的内容得先从目录inode找到其对应的block。

当在 `mount` 文件夹下使用命令 `ls` 时，其执行路径依次为：
- simplefs_iterate : 用于扫描目录中的文件或文件夹名称以及其对应的inode

``` c
#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 11, 0)
static int simplefs_iterate(struct file *filp, struct dir_context *ctx)
#else
static int simplefs_readdir(struct file *filp, void *dirent, filldir_t filldir)
#endif
{
        loff_t pos;
        struct inode *inode;
        struct super_block *sb;
        struct buffer_head *bh;
        struct simplefs_inode *sfs_inode;
        struct simplefs_dir_record *record;
        int i;

#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 11, 0)
        pos = ctx->pos;
        #else
        pos = filp->f_pos;
        #endif
        inode = filp->f_dentry->d_inode;
        sb = inode->i_sb;

        if (pos) {
                /* FIXME: We use a hack of reading pos to figure if we have filled in all data.
                 ,* We should probably fix this to work in a cursor based model and
                 ,* use the tokens correctly to not fill too many data in each cursor based call */
                return 0;
        }

        //得到目录的inode
        sfs_inode = SIMPLEFS_INODE(inode);

        if (unlikely(!S_ISDIR(sfs_inode->mode))) {
                printk(KERN_ERR
                       "inode [%llu][%lu] for fs object [%s] not a directory\n",
                       sfs_inode->inode_no, inode->i_ino,
                       filp->f_dentry->d_name.name);
                return -ENOTDIR;
        }

        //得到目录的block
        bh = sb_bread(sb, sfs_inode->data_block_number);
        BUG_ON(!bh);

        //获取目录blockc内容
        record = (struct simplefs_dir_record *)bh->b_data;
        //根据目录中含有的条目进行扫描
        for (i = 0; i < sfs_inode->dir_children_count; i++) {
#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 11, 0)
                //返回文件名以及其对应的inode
                dir_emit(ctx, record->filename, SIMPLEFS_FILENAME_MAXLEN,
                         record->inode_no, DT_UNKNOWN);
                ctx->pos += sizeof(struct simplefs_dir_record);
                #else
                filldir(dirent, record->filename, SIMPLEFS_FILENAME_MAXLEN, pos,
                        record->inode_no, DT_UNKNOWN);
                filp->f_pos += sizeof(struct simplefs_dir_record);
                #endif
                pos += sizeof(struct simplefs_dir_record);
                record++;
        }
        brelse(bh);

        return 0;
}
```

- simplefs_lookup : 得到文件或文件夹的inode内容并初始化系统的 inode结构体

``` c
struct dentry *simplefs_lookup(struct inode *parent_inode,
                               struct dentry *child_dentry, unsigned int flags)
{
        //获取目录inode
        struct simplefs_inode *parent = SIMPLEFS_INODE(parent_inode);
        struct super_block *sb = parent_inode->i_sb;
        struct buffer_head *bh;
        struct simplefs_dir_record *record;
        int i;

        //读取目录的block
        bh = sb_bread(sb, parent->data_block_number);
        BUG_ON(!bh);

        //读取目录的blockå����
        record = (struct simplefs_dir_record *)bh->b_data;
        for (i = 0; i < parent->dir_children_count; i++) {
                if (!strcmp(record->filename, child_dentry->d_name.name)) {
                        /* FIXME: There is a corner case where if an allocated inode,
                         ,* is not written to the inode store, but the inodes_count is
                         ,* incremented. Then if the random string on the disk matches
                         ,* with the filename that we are comparing above, then we
                         ,* will use an invalid uninitialized inode */

                        struct inode *inode;
                        struct simplefs_inode *sfs_inode;

                        //根据文件inode号获取其内容
                        sfs_inode = simplefs_get_inode(sb, record->inode_no);

                        //初始化inode结构体以及其对应的文件或文件夹操作
                        inode = new_inode(sb);
                        inode->i_ino = record->inode_no;
                        inode_init_owner(inode, parent_inode, sfs_inode->mode);
                        inode->i_sb = sb;
                        inode->i_op = &simplefs_inode_ops;

                        if (S_ISDIR(inode->i_mode))
                                inode->i_fop = &simplefs_dir_operations;
                        else if (S_ISREG(inode->i_mode))
                                inode->i_fop = &simplefs_file_operations;
                        else
                                printk(KERN_ERR
                                       "Unknown inode type. Neither a directory nor a file");

                        /* FIXME: We should store these times to disk and retrieve them */
                        inode->i_atime = inode->i_mtime = inode->i_ctime =
                                CURRENT_TIME;

                        inode->i_private = sfs_inode;

                        d_add(child_dentry, inode);
                        return NULL;
                }
                record++;
        }

        printk(KERN_ERR
               "No inode found for the filename [%s]\n",
               child_dentry->d_name.name);

        return NULL;
}
```

- simplefs_get_inode : 得到请求的inode号码的内容

``` c
/* This functions returns a simplefs_inode with the given inode_no
 ,* from the inode store, if it exists. */
struct simplefs_inode *simplefs_get_inode(struct super_block *sb,
                                          uint64_t inode_no)
{
        //获取super block
        struct simplefs_super_block *sfs_sb = SIMPLEFS_SB(sb);
        struct simplefs_inode *sfs_inode = NULL;
        struct simplefs_inode *inode_buffer = NULL;

        int i;
        struct buffer_head *bh;

        /* The inode store can be read once and kept in memory permanently while mounting.
         ,* But such a model will not be scalable in a filesystem with
         ,* millions or billions of files (inodes) */
        //读取inode table
        bh = sb_bread(sb, SIMPLEFS_INODESTORE_BLOCK_NUMBER);
        BUG_ON(!bh);

        sfs_inode = (struct simplefs_inode *)bh->b_data;

        #if 0
        if (mutex_lock_interruptible(&simplefs_inodes_mgmt_lock)) {
                printk(KERN_ERR "Failed to acquire mutex lock %s +%d\n",
                       __FILE__, __LINE__);
                return NULL;
        }
        #endif
        //扫描inode table 是否有与要求的序号匹配的Inode
        for (i = 0; i < sfs_sb->inodes_count; i++) {
                if (sfs_inode->inode_no == inode_no) {
                        //申请cache
                        inode_buffer = kmem_cache_alloc(sfs_inode_cachep, GFP_KERNEL);
                        memcpy(inode_buffer, sfs_inode, sizeof(*inode_buffer));

                        break;
                }
                sfs_inode++;
        }
        //      mutex_unlock(&simplefs_inodes_mgmt_lock);

        brelse(bh);
        return inode_buffer;
}
```

- simplefs_iterate

可以看出其基本思路是：
1. 通过文件夹的inode获取其block
2. 扫描block有哪些文件或文件夹
3. 获取这些扫描到的文件或文件夹的inode内容，为其操作做好准备

### 读取文件内容

可以猜测为了读取文件内容，首先要获取其inode才能找到其block.

当执行 `cat vanakkam` 时，执行的函数依次是：
- simplefs_iterate : 重复执行了8次
- simplefs_read

``` c
ssize_t simplefs_read(struct file * filp, char __user * buf, size_t len,
                      loff_t * ppos)
{
        /* After the commit dd37978c5 in the upstream linux kernel,
         ,* we can use just filp->f_inode instead of the
         ,* f->f_path.dentry->d_inode redirection */
        //获取inode内容
        struct simplefs_inode *inode =
                SIMPLEFS_INODE(filp->f_path.dentry->d_inode);
        struct buffer_head *bh;

        char *buffer;
        int nbytes;

        if (*ppos >= inode->file_size) {
                /* Read request with offset beyond the filesize */
                return 0;
        }

        //读取block
        bh = sb_bread(filp->f_path.dentry->d_inode->i_sb,
                      inode->data_block_number);

        if (!bh) {
                printk(KERN_ERR "Reading the block number [%llu] failed.",
                       inode->data_block_number);
                return 0;
        }

        //获取block内容
        buffer = (char *)bh->b_data;
        nbytes = min((size_t) inode->file_size, len);

        if (copy_to_user(buf, buffer, nbytes)) {
                brelse(bh);
                printk(KERN_ERR
                       "Error copying file contents to the userspace buffer\n");
                return -EFAULT;
        }

        brelse(bh);

        ,*ppos += nbytes;

        return nbytes;
}
```

- simplefs_read

可以看出其思路为：
1. 从目录inode获取目录block，进而获取到文件的inode
  + 所以当你对一个目录都没有读权限时，是无法通过其inode来获取文件内容的
2. 从文件inode找到其对应block再读取其内容

### 写文件内容

可以猜测其与读文件内容的思路是一样的：
1. 从目录inode获取目录block，进而获取到文件的inode
2. 从文件inode找到其对应block再写入对应的内容
3. 更新inode描述(因为inode中具有文件信息)

执行 echo "Hello world!" > vanakkam 其执行路径为：
- simplefs_iterate : 重复执行了12次，没看懂为什么
- simplefs_write : 写入数据并同步

``` c
ssize_t simplefs_write(struct file * filp, const char __user * buf, size_t len,
                       loff_t * ppos)
{
        /* After the commit dd37978c5 in the upstream linux kernel,
         ,* we can use just filp->f_inode instead of the
         ,* f->f_path.dentry->d_inode redirection */
        struct inode *inode;
        struct simplefs_inode *sfs_inode;
        struct buffer_head *bh;
        struct super_block *sb;

        char *buffer;

        int retval;

        retval = generic_write_checks(filp, ppos, &len, 0);
        if (retval) {
                return retval;
        }

        inode = filp->f_path.dentry->d_inode;
        //获取inode内容
        sfs_inode = SIMPLEFS_INODE(inode);
        sb = inode->i_sb;
        //获取block地址
        bh = sb_bread(filp->f_path.dentry->d_inode->i_sb,
                      sfs_inode->data_block_number);

        if (!bh) {
                printk(KERN_ERR "Reading the block number [%llu] failed.",
                       sfs_inode->data_block_number);
                return 0;
        }
        //获取block内容
        buffer = (char *)bh->b_data;

        /* Move the pointer until the required byte offset */
        buffer += *ppos;

        if (copy_from_user(buffer, buf, len)) {
                brelse(bh);
                printk(KERN_ERR
                       "Error copying file contents from the userspace buffer to the kernel space\n");
                return -EFAULT;
        }
        ,*ppos += len;

        //同步数据到硬盘
        mark_buffer_dirty(bh);
        sync_dirty_buffer(bh);
        brelse(bh);

        /* Set new size
         ,* sfs_inode->file_size = max(sfs_inode->file_size, *ppos);
         ,*
         ,* FIXME: What to do if someone writes only some parts in between ?
         ,* The above code will also fail in case a file is overwritten with
         ,* a shorter buffer */
        if (mutex_lock_interruptible(&simplefs_inodes_mgmt_lock)) {
                sfs_trace("Failed to acquire mutex lock\n");
                return -EINTR;
        }
        sfs_inode->file_size = *ppos;
        retval = simplefs_inode_save(sb, sfs_inode);
        if (retval) {
                len = retval;
        }
        mutex_unlock(&simplefs_inodes_mgmt_lock);

        return len;
}
```

- simplefs_inode_save : 更新inode

``` c
int simplefs_inode_save(struct super_block *sb, struct simplefs_inode *sfs_inode)
{
        struct simplefs_inode *inode_iterator;
        struct buffer_head *bh;

        //读取inode table
        bh = sb_bread(sb, SIMPLEFS_INODESTORE_BLOCK_NUMBER);
        BUG_ON(!bh);

        if (mutex_lock_interruptible(&simplefs_sb_lock)) {
                sfs_trace("Failed to acquire mutex lock\n");
                return -EINTR;
        }

        //从inode table 起始遍历出对应inode的内容
        inode_iterator = simplefs_inode_search(sb,
                                               (struct simplefs_inode *)bh->b_data,
                                               sfs_inode);

        if (likely(inode_iterator)) {
                //更新 inode
                memcpy(inode_iterator, sfs_inode, sizeof(*inode_iterator));
                printk(KERN_INFO "The inode updated\n");

                //与硬盘同步
                mark_buffer_dirty(bh);
                sync_dirty_buffer(bh);
        } else {
                mutex_unlock(&simplefs_sb_lock);
                printk(KERN_ERR
                       "The new filesize could not be stored to the inode.");
                return -EIO;
        }

        brelse(bh);

        mutex_unlock(&simplefs_sb_lock);

        return 0;
}
```

- simplefs_inode_search : 从inode table 中找到对应序列的inode

### 新建文件夹

先来猜测新建文件夹的步骤：

1. 根据文件夹inode找到其block
2. 为新建的文件夹在inode table 中获取一个inode
3. 为新建的文件夹分配一个block
4. 将新申请到的文件夹名称以及其inode号写入父文件夹的block中
5. 更新父文件夹inode
6. 与硬盘同步

执行命令 `mkdir hello` 其调用函数依次为：

- simplefs_iterate : 浏览目录获取其档案及对应inode
- simplefs_lookup : 查看当前目录是否已有此档案名
- simplefs_mkdir : 新建文件夹
- simplefs_create_fs_object : 新建档案

``` c
static int simplefs_create_fs_object(struct inode *dir, struct dentry *dentry,
                                     umode_t mode)
{
        struct inode *inode;
        struct simplefs_inode *sfs_inode;
        struct super_block *sb;
        struct simplefs_inode *parent_dir_inode;
        struct buffer_head *bh;
        struct simplefs_dir_record *dir_contents_datablock;
        uint64_t count;
        int ret;

        if (mutex_lock_interruptible(&simplefs_directory_children_update_lock)) {
                sfs_trace("Failed to acquire mutex lock\n");
                return -EINTR;
        }
        sb = dir->i_sb;

        //获取 super block 中记录的 inode 数目
        ret = simplefs_sb_get_objects_count(sb, &count);
        if (ret < 0) {
                mutex_unlock(&simplefs_directory_children_update_lock);
                return ret;
        }

        if (unlikely(count >= SIMPLEFS_MAX_FILESYSTEM_OBJECTS_SUPPORTED)) {
                /* The above condition can be just == insted of the >= */
                printk(KERN_ERR
                       "Maximum number of objects supported by simplefs is already reached");
                mutex_unlock(&simplefs_directory_children_update_lock);
                return -ENOSPC;
        }

        if (!S_ISDIR(mode) && !S_ISREG(mode)) {
                printk(KERN_ERR
                       "Creation request but for neither a file nor a directory");
                mutex_unlock(&simplefs_directory_children_update_lock);
                return -EINVAL;
        }

        inode = new_inode(sb);
        if (!inode) {
                mutex_unlock(&simplefs_directory_children_update_lock);
                return -ENOMEM;
        }

        inode->i_sb = sb;
        inode->i_op = &simplefs_inode_ops;
        inode->i_atime = inode->i_mtime = inode->i_ctime = CURRENT_TIME;
        inode->i_ino = (count + SIMPLEFS_START_INO - SIMPLEFS_RESERVED_INODES + 1);

        sfs_inode = kmem_cache_alloc(sfs_inode_cachep, GFP_KERNEL);
        sfs_inode->inode_no = inode->i_ino;
        inode->i_private = sfs_inode;
        sfs_inode->mode = mode;

        if (S_ISDIR(mode)) {
                printk(KERN_INFO "New directory creation request\n");
                sfs_inode->dir_children_count = 0;
                inode->i_fop = &simplefs_dir_operations;
        } else if (S_ISREG(mode)) {
                printk(KERN_INFO "New file creation request\n");
                sfs_inode->file_size = 0;
                inode->i_fop = &simplefs_file_operations;
        }

        /* First get a free block and update the free map,
         ,* Then add inode to the inode store and update the sb inodes_count,
         ,* Then update the parent directory's inode with the new child.
         ,*
         ,* The above ordering helps us to maintain fs consistency
         ,* even in most crashes
         ,*/
        //申请一个空闲的block
        ret = simplefs_sb_get_a_freeblock(sb, &sfs_inode->data_block_number);
        if (ret < 0) {
                printk(KERN_ERR "simplefs could not get a freeblock");
                mutex_unlock(&simplefs_directory_children_update_lock);
                return ret;
        }

        //申请一个空闲的inode
        simplefs_inode_add(sb, sfs_inode);

        parent_dir_inode = SIMPLEFS_INODE(dir);
        bh = sb_bread(sb, parent_dir_inode->data_block_number);
        BUG_ON(!bh);

        //得到父目录的block
        dir_contents_datablock = (struct simplefs_dir_record *)bh->b_data;


        /* Navigate to the last record in the directory contents */
        dir_contents_datablock += parent_dir_inode->dir_children_count;
        //在父目录的blockä������������������inode对
        dir_contents_datablock->inode_no = sfs_inode->inode_no;
        strcpy(dir_contents_datablock->filename, dentry->d_name.name);

        mark_buffer_dirty(bh);
        sync_dirty_buffer(bh);
        brelse(bh);

        if (mutex_lock_interruptible(&simplefs_inodes_mgmt_lock)) {
                mutex_unlock(&simplefs_directory_children_update_lock);
                sfs_trace("Failed to acquire mutex lock\n");
                return -EINTR;
        }

        //保存父目录inode
        parent_dir_inode->dir_children_count++;
        ret = simplefs_inode_save(sb, parent_dir_inode);
        if (ret) {
                mutex_unlock(&simplefs_inodes_mgmt_lock);
                mutex_unlock(&simplefs_directory_children_update_lock);

                /* TODO: Remove the newly created inode from the disk and in-memory inode store
                 ,* and also update the superblock, freemaps etc. to reflect the same.
                 ,* Basically, Undo all actions done during this create call */
                return ret;
        }

        mutex_unlock(&simplefs_inodes_mgmt_lock);
        mutex_unlock(&simplefs_directory_children_update_lock);

        inode_init_owner(inode, dir, mode);
        d_add(dentry, inode);

        return 0;
}
```

- simplefs_sb_get_object_count ： 获取当前super block 中记录的inode数量
- simplefs_sb_get_a_freeblock : 获取空闲block

``` c
int simplefs_sb_get_a_freeblock(struct super_block *vsb, uint64_t * out)
{
        //获取super block
        struct simplefs_super_block *sb = SIMPLEFS_SB(vsb);
        int i;
        int ret = 0;

        if (mutex_lock_interruptible(&simplefs_sb_lock)) {
                sfs_trace("Failed to acquire mutex lock\n");
                ret = -EINTR;
                goto end;
        }

        /* Loop until we find a free block. We start the loop from 3,
         ,* as all prior blocks will always be in use */
        //从第三个block 开始寻找，前两个分别是(super block 和 inode table)
        for (i = 3; i < SIMPLEFS_MAX_FILESYSTEM_OBJECTS_SUPPORTED; i++) {
                //通过位与的方式来获取空位，这也就是为什么最多支持64个block(free_blocks 是64位)
                if (sb->free_blocks & (1 << i)) {
                        break;
                }
        }

        if (unlikely(i == SIMPLEFS_MAX_FILESYSTEM_OBJECTS_SUPPORTED)) {
                printk(KERN_ERR "No more free blocks available");
                ret = -ENOSPC;
                goto end;
        }

        ,*out = i;

        //更新super block 中记录的空闲blockå��
        /* Remove the identified block from the free list */
        sb->free_blocks &= ~(1 << i);

        //同步super block 与硬盘
        simplefs_sb_sync(vsb);

end:
        mutex_unlock(&simplefs_sb_lock);
        return ret;
}
```

- simplefs_sb_sync : 同步super block 与硬盘
- simplefs_inode_add : 获取一个inode

``` c
void simplefs_inode_add(struct super_block *vsb, struct simplefs_inode *inode)
{
        struct simplefs_super_block *sb = SIMPLEFS_SB(vsb);
        struct buffer_head *bh;
        struct simplefs_inode *inode_iterator;

        if (mutex_lock_interruptible(&simplefs_inodes_mgmt_lock)) {
                sfs_trace("Failed to acquire mutex lock\n");
                return;
        }

        bh = sb_bread(vsb, SIMPLEFS_INODESTORE_BLOCK_NUMBER);
        BUG_ON(!bh);

        //获取inode table 内容
        inode_iterator = (struct simplefs_inode *)bh->b_data;

        if (mutex_lock_interruptible(&simplefs_sb_lock)) {
                sfs_trace("Failed to acquire mutex lock\n");
                return;
        }

        /* Append the new inode in the end in the inode store */
        //移动到inode table 的第一个空闲处
        inode_iterator += sb->inodes_count;

        memcpy(inode_iterator, inode, sizeof(struct simplefs_inode));
        //更新super block 计数
        sb->inodes_count++;

        mark_buffer_dirty(bh);
        //同步super block 到硬盘
        simplefs_sb_sync(vsb);
        brelse(bh);

        mutex_unlock(&simplefs_sb_lock);
        mutex_unlock(&simplefs_inodes_mgmt_lock);
}
```
- simplefs_sb_sync 
- simplefs_inode_save 
- simplefs_inode_search 

### 新建文件

还是先来猜测一下新建文件的步骤：
1. 根据文件夹inode找到对应的block
2. 从inode table 中为新建文件获取一个inode
3. 从block 中为新建文件获取一个block，并填充其内容
4. 更新文件的inode
5. 更新文件夹的inode,以及block
6. 更新super block 的 inode

下面执行 `echo "hello world!" > hello/hello.txt` 其条用函数依次为：

- simplefs_iterate : 首先通过根目录扫描其所包含的条目
- simplefs_iterate : 然后通过扫描 =hello= 目录扫描其所包含的条目
- simplefs_lookup : 查找是否存在 =hello.txt= 的inode
- simplefs_create_fs_object: 新建文件
- simplefs_sb_get_object_count ： 获取当前super block 中记录的inode数量
- simplefs_sb_get_a_freeblock : 获取空闲block
- simplefs_sb_sync : 同步super block 与硬盘
- simplefs_inode_add : 获取一个inode
- simplefs_sb_sync 
- simplefs_inode_save 
- simplefs_inode_search 
- simplefs_write : 写入文件内容
- simplefs_inode_save : 更新inode
- simplefs_inode_search 

## 功能实现

通过查看其代码可以发现，此文件系统还有以下功能未能实现：
- 删除文件
- 删除文件夹
- 建立符号链接
- 建立硬链接

下面来尝试一一实现：

### 删除文件
前面已经新建了文件 `/hello/hello.txt` ，下面尝试将它删除。

根据已有的知识先来猜测一下如何以最简单的方式删除一个文件，
为了能够使得操作步骤尽量的少，其实没有必要去擦除文件block的内容，而只需要对其inode操作即可。

也就是说涉及以下几个部分：
1. 文件夹block的字符串和inode对擦除
2. 文件夹inode中的描述修改
3. inode table 修改
4. super block 修改
   
通过 `strace rm -f hello.txt` 观察到有这么一行输出：

```shell
unlinkat(AT_FDCWD, "hello.txt", 0)      = -1 EPERM (Operation not permitted)
```

对应驱动的调用接口应该是 `struct inode_operations` 下的 `unlink`
``` c
  int (*unlink) (struct inode *,struct dentry *);
```

- 在实现的过程中发现，其在增加inode 和 dir content 时是直接简单粗暴的在尾部增加，很明显在删除文件时会产生漏洞，所以此bug也需要修复。

# FUSE

![](./fuse.jpg)

如上图所示，FUSE仅仅在内核中实现了一个简单的模块，用于接口VFS和用户空间，文件系统的操作细节则存在于用户空间中。
- 这种方式导致操作效率低但便于调试

# 比较重要的数据结构

``` c
/**
 ,* @brief 文件系统总览
 ,*/
struct file_system_type {
        const char *name;
        int fs_flags;
#define FS_REQUIRES_DEV1
#define FS_BINARY_MOUNTDATA2
#define FS_HAS_SUBTYPE4
#define FS_USERNS_MOUNT8/* Can be mounted by userns root */
#define FS_USERNS_DEV_MOUNT16 /* A userns mount does not imply MNT_NODEV */
#define FS_USERNS_VISIBLE32/* FS must already be visible */
#define FS_RENAME_DOES_D_MOVE32768/* FS will handle d_move() during rename() internally. */
        struct dentry *(*mount) (struct file_system_type *, int,
                                 const char *, void *);
        void (*kill_sb) (struct super_block *);
        struct module *owner;
        struct file_system_type * next;
        struct hlist_head fs_supers;

        struct lock_class_key s_lock_key;
        struct lock_class_key s_umount_key;
        struct lock_class_key s_vfs_rename_key;
        struct lock_class_key s_writers_key[SB_FREEZE_LEVELS];

        struct lock_class_key i_lock_key;
        struct lock_class_key i_mutex_key;
        struct lock_class_key i_mutex_dir_key;
};
/**
 ,* @brief super block 信息及操作结构体
 ,*/
struct super_block {
        struct list_heads_list;/* Keep this first */
        dev_ts_dev;/* search index; _not_ kdev_t */
        unsigned chars_blocksize_bits;
        unsigned longs_blocksize;
        loff_ts_maxbytes;/* Max file size */
        struct file_system_type*s_type;
        const struct super_operations*s_op;
        const struct dquot_operations*dq_op;
        const struct quotactl_ops*s_qcop;
        const struct export_operations *s_export_op;
        unsigned longs_flags;
        unsigned longs_iflags;/* internal SB_I_* flags */
        unsigned longs_magic;
        struct dentry*s_root;
        struct rw_semaphores_umount;
        ints_count;
        atomic_ts_active;
        #ifdef CONFIG_SECURITY
        void                    *s_security;
        #endif
        const struct xattr_handler **s_xattr;

        struct hlist_bl_heads_anon;/* anonymous dentries for (nfs) exporting */
        struct list_heads_mounts;/* list of mounts; _not_ for fs use */
        struct block_device*s_bdev;
        struct backing_dev_info *s_bdi;
        struct mtd_info*s_mtd;
        struct hlist_nodes_instances;
        unsigned ints_quota_types;/* Bitmask of supported quota types */
        struct quota_infos_dquot;/* Diskquota specific options */

        struct sb_writerss_writers;

        char s_id[32];/* Informational name */
        u8 s_uuid[16];/* UUID */

        void *s_fs_info;/* Filesystem private info */
        unsigned ints_max_links;
        fmode_ts_mode;

        /* Granularity of c/m/atime in ns.
           Cannot be worse than a second */
        u32   s_time_gran;

        /*
         ,* The next field is for VFS *only*. No filesystems have any business
         ,* even looking at it. You had been warned.
         ,*/
        struct mutex s_vfs_rename_mutex;/* Kludge */

        /*
         ,* Filesystem subtype.  If non-empty the filesystem type field
         ,* in /proc/mounts will be "type.subtype"
         ,*/
        char *s_subtype;

        /*
         ,* Saved mount options for lazy filesystems using
         ,* generic_show_options()
         ,*/
        char __rcu *s_options;
        const struct dentry_operations *s_d_op; /* default d_op for dentries */

        /*
         ,* Saved pool identifier for cleancache (-1 means none)
         ,*/
        int cleancache_poolid;

        struct shrinker s_shrink;/* per-sb shrinker handle */

        /* Number of inodes with nlink == 0 but still referenced */
        atomic_long_t s_remove_count;

        /* Being remounted read-only */
        int s_readonly_remount;

        /* AIO completions deferred from interrupt context */
        struct workqueue_struct *s_dio_done_wq;
        struct hlist_head s_pins;

        /*
         ,* Keep the lru lists last in the structure so they always sit on their
         ,* own individual cachelines.
         ,*/
        struct list_lrus_dentry_lru ____cacheline_aligned_in_smp;
        struct list_lrus_inode_lru ____cacheline_aligned_in_smp;
        struct rcu_headrcu;
        struct work_structdestroy_work;

        struct mutexs_sync_lock;/* sync serialisation lock */

        /*
         ,* Indicates how deep in a filesystem stack this SB is
         ,*/
        int s_stack_depth;

        /* s_inode_list_lock protects s_inodes */
        spinlock_ts_inode_list_lock ____cacheline_aligned_in_smp;
        struct list_heads_inodes;/* all inodes */
};

/*
 ,* Keep mostly read-only and often accessed (especially for
 ,* the RCU path lookup and 'stat' data) fields at the beginning
 ,* of the 'struct inode'
 ,*/
struct inode {
        umode_t                i_mode;
        unsigned               shorti_opflags;
        kuid_t                 i_uid;
        kgid_t                 i_gid;
        unsigned int           i_flags;

        #ifdef CONFIG_FS_POSIX_ACL
        struct posix_acl       *i_acl;
        struct posix_acl       *i_default_acl;
        #endif

        const struct inode_operations  *i_op;
        struct super_block             *i_sb;
        struct address_space           *i_mapping;

        #ifdef CONFIG_SECURITY
        void                           *i_security;
        #endif

        /* Stat data, not accessed from path walking */
        unsigned long                  i_ino;
        /*
         ,* Filesystems may only read i_nlink directly.  They shall use the
         ,* following functions for modification:
         ,*
         ,*    (set|clear|inc|drop)_nlink
         ,*    inode_(inc|dec)_link_count
         ,*/
        union {
                const unsigned int i_nlink;
                unsigned int __i_nlink;
        };
        dev_t                  i_rdev;
        loff_t                 i_size;
        struct timespec        i_atime;
        struct timespec        i_mtime;
        struct timespec        i_ctime;
        spinlock_ti_lock;/* i_blocks, i_bytes, maybe i_size */
        unsigned short         i_bytes;
        unsigned int           i_blkbits;
        blkcnt_t               i_blocks;

        #ifdef __NEED_I_SIZE_ORDERED
        seqcount_t             i_size_seqcount;
        #endif

        /* Misc */
        unsigned long          i_state;
        struct mutex           i_mutex;

        unsigned long          dirtied_when;/* jiffies of first dirtying */
        unsigned long          dirtied_time_when;

        struct hlist_node      i_hash;
        struct list_head       i_io_list;/* backing dev IO list */
        #ifdef CONFIG_CGROUP_WRITEBACK
        struct bdi_writeback   *i_wb;/* the associated cgroup wb */

        /* foreign inode detection, see wbc_detach_inode() */
        int                     i_wb_frn_winner;
        u16                     i_wb_frn_avg_time;
        u16                     i_wb_frn_history;
        #endif
        struct list_head        i_lru;/* inode LRU list */
        struct list_head        i_sb_list;
        union {
                struct hlist_head  i_dentry;
                struct rcu_head    i_rcu;
        };
        u64                        i_version;
        atomic_t                   i_count;
        atomic_t                   i_dio_count;
        atomic_t                   i_writecount;
        #ifdef CONFIG_IMA
        atomic_t                   i_readcount; /* struct files open RO */
        #endif
        const struct file_operations   *i_fop;/* former ->i_op->default_file_ops */
        struct file_lock_context       *i_flctx;
        struct address_space           i_data;
        struct list_head               i_devices;
        union {
                struct pipe_inode_info *i_pipe;
                struct block_device    *i_bdev;
                struct cdev            *i_cdev;
                char                   *i_link;
        };

        __u32                          i_generation;

        #ifdef CONFIG_FSNOTIFY
        __u32                          i_fsnotify_mask; /* all events this inode cares about */
        struct hlist_head              i_fsnotify_marks;
        #endif

        void                           *i_private; /* fs or device private pointer */
};
struct inode_operations {
        struct dentry * (*lookup) (struct inode *,struct dentry *, unsigned int);
        const char * (*follow_link) (struct dentry *, void **);
        int (*permission) (struct inode *, int);
        struct posix_acl * (*get_acl)(struct inode *, int);

        int (*readlink) (struct dentry *, char __user *,int);
        void (*put_link) (struct inode *, void *);

        int (*create) (struct inode *,struct dentry *, umode_t, bool);
        int (*link) (struct dentry *,struct inode *,struct dentry *);
        int (*unlink) (struct inode *,struct dentry *);
        int (*symlink) (struct inode *,struct dentry *,const char *);
        int (*mkdir) (struct inode *,struct dentry *,umode_t);
        int (*rmdir) (struct inode *,struct dentry *);
        int (*mknod) (struct inode *,struct dentry *,umode_t,dev_t);
        int (*rename) (struct inode *, struct dentry *,
                       struct inode *, struct dentry *);
        int (*rename2) (struct inode *, struct dentry *,
                        struct inode *, struct dentry *, unsigned int);
        int (*setattr) (struct dentry *, struct iattr *);
        int (*getattr) (struct vfsmount *mnt, struct dentry *, struct kstat *);
        int (*setxattr) (struct dentry *, const char *,const void *,size_t,int);
        ssize_t (*getxattr) (struct dentry *, const char *, void *, size_t);
        ssize_t (*listxattr) (struct dentry *, char *, size_t);
        int (*removexattr) (struct dentry *, const char *);
        int (*fiemap)(struct inode *, struct fiemap_extent_info *, u64 start,
                      u64 len);
        int (*update_time)(struct inode *, struct timespec *, int);
        int (*atomic_open)(struct inode *, struct dentry *,
                           struct file *, unsigned open_flag,
                           umode_t create_mode, int *opened);
        int (*tmpfile) (struct inode *, struct dentry *, umode_t);
        int (*set_acl)(struct inode *, struct posix_acl *, int);
} ____cacheline_aligned;

/**
 ,* @brief 代表的是一个路径
 ,*/
struct dentry {
        /* RCU lookup touched fields */
        unsigned int d_flags;/* protected by d_lock */
        seqcount_t d_seq;/* per dentry seqlock */
        struct hlist_bl_node d_hash;/* lookup hash list */
        struct dentry *d_parent;/* parent directory */
        struct qstr d_name;
        struct inode *d_inode;/* Where the name belongs to - NULL is
                               ,* negative */
        unsigned char d_iname[DNAME_INLINE_LEN];/* small names */

        /* Ref lookup also touches following */
        struct lockref d_lockref;/* per-dentry lock and refcount */
        const struct dentry_operations *d_op;
        struct super_block *d_sb;/* The root of the dentry tree */
        unsigned long d_time;/* used by d_revalidate */
        void *d_fsdata;/* fs-specific data */

        struct list_head d_lru;/* LRU list */
        struct list_head d_child;/* child of parent list */
        struct list_head d_subdirs;/* our children */
        /*
         ,* d_alias and d_rcu can share memory
         ,*/
        union {
                struct hlist_node d_alias;/* inode alias list */
                struct rcu_head d_rcu;
        } d_u;
};
/**
 ,* @brief 代表一个文件的引用（一个文件可以被打开多次就有多个引用，但inode却是仅有一个）
 ,*/
struct file {
        union {
                struct llist_node     fu_llist;
                struct rcu_head       fu_rcuhead;
        } f_u;
        struct path                   f_path;
        struct inode                  *f_inode;/* cached value */
        const struct file_operations  *f_op;

        /*
         ,* Protects f_ep_links, f_flags.
         ,* Must not be taken from IRQ context.
         ,*/
        spinlock_t                    f_lock;
        atomic_long_t                 f_count;
        unsigned int                  f_flags;
        fmode_t                       f_mode;
        struct mutex                  f_pos_lock;
        loff_t                        f_pos;
        struct fown_struct            f_owner;
        const struct cred             *f_cred;
        struct file_ra_state          f_ra;

        u64                           f_version;
        #ifdef CONFIG_SECURITY
        void                          *f_security;
        #endif
        /* needed for tty driver, and maybe others */
        void                          *private_data;

        #ifdef CONFIG_EPOLL
        /* Used by fs/eventpoll.c to link all the hooks to this file */
        struct list_head              f_ep_links;
        struct list_head              f_tfile_llink;
#endif /* #ifdef CONFIG_EPOLL */
        struct address_space          *f_mapping;
} __attribute__((aligned(4)));/* lest something weird decides that 2 is OK */
```

inode Tab 存在于硬盘中，如果每次CPU从硬盘中读取那么效率会比较低下，
所以内核会为inode Table 申请一段内存以作为缓存，称为 **对应文件系统的 inode cache**.

``` c
static int __init init_inodecache(void)
{
        ext4_inode_cachep = kmem_cache_create("ext4_inode_cache",
                                              sizeof(struct ext4_inode_info),
                                              0, (SLAB_RECLAIM_ACCOUNT|
                                                  SLAB_MEM_SPREAD),
                                              init_once);
        if (ext4_inode_cachep == NULL)
                return -ENOMEM;
        return 0;
}
```

同样在VFS层面上，也会对抽象出来的 inode 和 路径进行缓存(dentry), 分别称为 icache 和 dcache.

``` c
static void __init dcache_init(void)
{
        unsigned int loop;

        /*
         ,* A constructor could be added for stable state like the lists,
         ,* but it is probably not worth it because of the cache nature
         ,* of the dcache.
         ,*/
        dentry_cache = KMEM_CACHE(dentry,
                                  SLAB_RECLAIM_ACCOUNT|SLAB_PANIC|SLAB_MEM_SPREAD);

        /* Hash may have been set up in dcache_init_early */
        if (!hashdist)
                return;

        dentry_hashtable =
                alloc_large_system_hash("Dentry cache",
                                        sizeof(struct hlist_bl_head),
                                        dhash_entries,
                                        13,
                                        0,
                                        &d_hash_shift,
                                        &d_hash_mask,
                                        0,
                                        0);

        for (loop = 0; loop < (1U << d_hash_shift); loop++)
                INIT_HLIST_BL_HEAD(dentry_hashtable + loop);
}
void __init inode_init(void)
{
        unsigned int loop;

        /* inode slab cache */
        inode_cachep = kmem_cache_create("inode_cache",
                                         sizeof(struct inode),
                                         0,
                                         (SLAB_RECLAIM_ACCOUNT|SLAB_PANIC|
                                          SLAB_MEM_SPREAD),
                                         init_once);

        /* Hash may have been set up in inode_init_early */
        if (!hashdist)
                return;

        inode_hashtable =
                alloc_large_system_hash("Inode-cache",
                                        sizeof(struct hlist_head),
                                        ihash_entries,
                                        14,
                                        0,
                                        &i_hash_shift,
                                        &i_hash_mask,
                                        0,
                                        0);

        for (loop = 0; loop < (1U << i_hash_shift); loop++)
                INIT_HLIST_HEAD(&inode_hashtable[loop]);
}
```

最终这些申请的缓存都是内核通过LRU算法进行回收的(内核通过 shrink方法来回收slab内存)
- shrink 方法需要驱动编写者来主动实现

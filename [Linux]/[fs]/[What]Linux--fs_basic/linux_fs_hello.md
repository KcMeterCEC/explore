---
title: Linux文件系统基本操作
tags: 
- linux
categories:
- linux
- userspace
- fs
date: 2024/9/10
updated: 2024/9/10
layout: true
comments: true
---

| kernel version | arch  |
| -------------- | ----- |
| v5.4.0         | arm32 |

<!--more-->

# 编程接口

此节只列出 Linux 和 c 库操作接口，具体的详细信息还是要找 `man` 。

- 其实在实际应用中，还是尽量使用标准的 c/c++ 库便于以后移植。

需要注意的是：标准的ISOC库的I/O操作默认是带有缓存的，也就是填充一定的缓存后才会去调用系统接口。
而如果直接使用POSIX标准的系统接口，相当于上层没有做缓存，但实际上 **内核为了尽量批量化的操作I/O，其内部也会做缓存。**

## 常用接口

### 文件的创建

```c
  /**
    * @brief 设置文件在创建时需要去掉的权限
    * @note : 此设置仅影响此进程的umask，不会影响 shell 默认的 umask
    * 使用shell命令 umask 
    * 可以查看 shell 设置输出依次为: <special bits><user><group><other> 
    */
  int umask(int newmask);
  /**
    * @brief 创建文件并设置权限
    * @note 权限与 umask 相与决定最终的权限
    * 
    * 此函数使用较少，一般使用 open(path, O_RDWR | O_CREAT | O_TRUNC, mode);
    */
  int creat(const char *pathname, mode_t mode);
```

| mode value | 含义         |
| ---------- | ---------- |
| S_IRUSR    | 用户可读       |
| S_IWUSR    | 用户可写       |
| S_IXUSR    | 用户可执行      |
| S_IRWXU    | 用户可读、写、执行  |
| S_IRGRP    | 组可读        |
| S_IWGRP    | 组可写        |
| S_IXGRP    | 组可执行       |
| S_IRWXG    | 组可读、写、执行   |
| S_IROTH    | 其他人可读      |
| S_IWOTH    | 其他人可写      |
| S_IXOTH    | 其他人可执行     |
| S_IRWXO    | 其他人可读、写、执行 |
| S_ISUID    | 设置用户执行ID   |
| S_ISGID    | 设置组执行ID    |

### 创建及打开

```c
FILE *fopen( const char *filename, const char *mode );
```

```c
  /**
   * @brief 以flags指定的方式打开 pathname 指定的文件
   * @note
   * 1. 当 flags 为 O_CREAT 时，需要指定其 mode
   * 2. 当pathname为相对路径时，可以使用 openat 为其指定一个 dirfd，以此dir为相对路径
   */
  int open(const char *pathname, int flags, .../*mode_t mode*/);
  int openat(int dirfd, const char *pathname, int flags, .../*mode_t mode*/);
```

| flags value | 含义                        |
| ----------- | ------------------------- |
| O_RDONLY    | 只读方式打开                    |
| O_WRONLY    | 只写方式打开                    |
| O_RDWR      | 读写方式打开                    |
| O_APPEND    | 追加方式打开                    |
| O_CREAT     | 创建                        |
| O_EXCL      | 如果使用了O_CREATE且文件存在，就会发生错误 |
| O_NOBLOCK   | 以非阻塞的方式打开                 |
| O_TRUNC     | 如果文件存在则删除其内容              |
| ...         | ...                       |

- 在POSIX标准中的标准输入、输出、错误对应的宏依次为 `STDIN_FILENO,STDOUT_FILENO,STDERR_FILENO` 位于头文件 `<unistd.h>` 中

### 文件读写

进行 read 和 write 大量数据读写时，需要考虑单次读写的字节数，取文件系统的block大小(比如4096字节)，能在尽量减小系统调用的同时保证较高的写入效率。

```c
 ssize_t read(int fd, void *buf, size_t count);
 ssize_t write(int fd, const void *buf, size_t count);
```

```c
size_t fread( void          *buffer, size_t size, size_t count,
              FILE          *stream );
size_t fwrite( const void *buffer, size_t size, size_t count,
               FILE *stream );
```

### 文件定位

```c
  /**
   * @brief 以 whence 为起始移动 offset 字节
   * @note
   * 1. 获取当前文件位置使用 currpos = lseek(fd, 0, SEEK_CUR);
   * 当返回负数代表此文件对象不能做移动操作，比如FIFO，SOCKET
   */
  off_t lseek(int fd, off_t offset, int whence);
```

| whence value | 含义   |
| ------------ | ---- |
| SEEK_SET     | 文件开头 |
| SEEK_CUR     | 当前位置 |
| SEEK_END     | 文件尾  |

```c
int fseek( FILE *stream, long offset, int origin );
```

### 截断文件

```c
  /**
   * @brief : 从文件末尾到文件头的顺序截断length字节
   */
  int truncate(const char *path, off_t length);
  int ftruncate(int fd, off_t length);
```

### 文件关闭

```c
  int close(int fd);
```

```c
int fclose( FILE *stream );
```

### 文件夹操作

- 新建

```c
  int mkdir(const char *pathname, mode_t mode);
  int mkdirat(int dirfd, const char *pathname, mode_t mode);
```

- 移除

```c
  int rmdir(const char *pathname);
```

### 实例

```c
  /*!
   * ### 文件操作
   * 1. 创建
   * > int create(const char *filename, mode_t mode);
   * > mode 与 umask (mode & umask)共同决定文件的最终权限
   * > int umask(int newmask);
   *
   * > FILE *fopen(const char *path, const char *mode);
   * > mode --> "r"/"rb"/"w"/"wb"/"a"/"ab"/"r+"/"r+b"/"rb+"/"w+"/"w+b"/"wb+"/"a+"/"a+b"/"ab+"
   * 2. 打开
   * > int open(const char *pathname, int flags);
   * > int open(const char *pathname, int flags, mode_t mode);
   * > flag --> O_RDONLY / O_WRONLY / O_RDWR / O_APPEND / O_CREAT / O_EXEC / O_NOBLOCK / O_TRUNC;
   * > mode --> S_IRUSR / S_IWUSR/ S_IXUSR / S_IRWXU / S_IRGRP / S_IWGRP / S_IXGRP / S_IRWXGRP / S_IROTH / S_IWOTH / S_IXOTH / S_IRWXO / S_ISUID / S_ISGID;
   *
   * 3. 读写
   * > int read(int fd, const void *buf, size_t length);
   * > int write(int fd, const void *buf, size_t length);
   *
   * > int fgetc(FILE *stream);
   * > int fputc(int c, FILE *stream);
   * > char *fgets(char *s, int n, FILE *stream);
   * > int fputs(const char *s, FILE *stream);
   * > int fprintf(FILE *stream, const char *format, ...);
   * > int fscanf(FILE *stream, const char *format, ...);
   * > size_t fread(void *ptr, size_t size, size_t n, FILE *stream);
   * > size_t fwrite(const void *ptr, size_t size, size_t n, FILE *stream);
   *
   * 4. 定位
   * > int lseek(int fd, offset_t offset, int whence);
   * > whence --> SEEK_SET / SEEK_CUR / SEEK_END;
   * > 得到文件长度 lseek(fd, 0, SEEK_END);
   *
   * > int fgetpos(FILE *stream, fpos_t *pos);
   * > int fsetpos(FILE *stream, const fpos_t *pos);
   * > int fseek(FILE *stream, long offset, int whence);
   *
   * 5. 关闭
   * > int close(int fd);
   *
   * > int fclose(FILE *stream);
   *
   */
  #include <sys/types.h>
  #include <sys/stat.h>
  #include <fcntl.h>
  #include <unistd.h>
  #include <stdio.h>
  #include <string.h>

  #define LENGTH      (100)

  int main(int argc, char *argv[])
  {
        int fd, len;
        char str[LENGTH];
        FILE *p_fd;

        fd = open("hello.txt", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR);
        if(fd)
        {
              write(fd, "Hello world", strlen("Hello world"));
              close(fd);
        }
        p_fd = fopen("hello_lib.txt", "w+");
        if(p_fd)
        {
              fputs("Hello world! ^_^ \n", p_fd);
              fclose(p_fd);
        }

        fd = open("hello.txt", O_RDWR);
        len = read(fd, str, LENGTH);
        str[len] = '\0';
        printf("%s\n", str);
        close(fd);

        p_fd = fopen("hello_lib.txt", "r");
        fgets(str, LENGTH, p_fd);
        printf("%s\n", str);
        fclose(p_fd);
  }
```

## 多个进程打开同一个文件

多个进程打开同一个文件时，每个进程的 `task_struct` 都会包含此文件的资源描述，但是最终它们都是指向同一个 `inode` 。

- 每个文件资源描述都包含对该文件的操作状态，位置偏移等信息
- 当进行 `lseek` 这种操作时，如果没有造成文件的扩大，其实是直接操作的资源描述结构体，而没有去操作inode。

### 互斥操作

如果有多个进程在操作同一个文件，则很有可能会造成竞态，有以下方式来避免此问题的发生：

- pread , pwrite

```c
  /**
   * @brief : 在文件为起始的 offset 字节处开始读或者写
   * @note :
   * 1. 这两个函数的操作是原子性的
   * 2. 此函数并不会改变对应进程本身所保存的 offset
   */
  ssize_t pread(int fd, void *buf, size_t count, off_t offset);

  ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset);
```

## 文件索引的复制

使用以下函数可以完成文件索引的复制(也就是两个不同的索引指向同一个文件描述资源，它们具有联动的偏移位置)

```c
  int dup(int oldfd);
  int dup2(int oldfd, int newfd);
```

## 主动写回数据到硬盘

一般的文件读写数据都会被存在 page cache 中，待内核在合适的时间写入硬盘，为了强制同步，可以使用下面函数:

```c
  /**
   * @brief 以阻塞的方式等待某个文件同步
   */
  int fsync(int fd);

  /**
   * @brief 以阻塞的方式同步文件数据，文件的元数据不一定会同步
   * @note : 只有一些重要的修改才会同步元数据，比如文件大小改变了
   * 但文件的方式文件改变了，是不会同步元数据的
   */
  int fdatasync(int fd);

  /**
   * @brief 给内核发送同步消息，并不会等待内核操作完成
   * @note shell 中的 sync 命令 也是调用的此函数
   */
  void sync(void);
```

## 文件运行时控制

当一个文件已经打开，要修改它的一些属性时，可以使用函数 `fcntl` 。

```c
  int fcntl(int fd, int cmd, ... /* arg */ );
```

此函数具有以下用途：

1. 生成一个文件描述符的副本
2. 获取或设置文件描述符标记
3. 获取或设置文件状态
4. 获取或设置文件拥有者关系
5. 获取或设置文件锁

**需要注意的是：** 当要修改某个文件状态时，应该像操作寄存器位那样通过 `读-修改-写` 的方式操作（也就是先读取当前设置值，然后写入新设置的那一位，再回写回去）。

```c
  #include <stdio.h>
  #include <unistd.h>
  #include <fcntl.h>

  int main(void)
  {
      int status = 0;
      int fd = open("./test", O_CREAT | O_WRONLY);
      if(fd == -1)
      {
          perror("open file failed:");
          goto quick_out;
      }
      if((status = fcntl(fd, F_GETFL, 0)) == -1)
      {
          perror("can not get file status:");
          goto close_out;
      }
      switch(status & O_ACCMODE)
      {
          case O_RDONLY:
              {
                  printf("read only\n");
              }break;
          case O_WRONLY:
              {
                  printf("write only\n");
              }break;
          case O_RDWR:
              {
                  printf("read write\n");
              }break;
          default:
              printf("can not get file mode!\n");
      }
      if(status & O_APPEND)
      {
          printf("append\n");
      }
      if(status & O_NONBLOCK)
      {
          printf("nonblocking\n");
      }
      if(status & O_SYNC)
      {
          printf("synchronous writes\n");
      }
  close_out:
      close(fd);
      remove("./test");
  quick_out:
      return 0;
  }
```

另外的一个控制函数便是 `ioctl` ，这个在驱动的操作中经常使用：

```c
  int ioctl(int fd, unsigned long request, ...);
```

## 文件的权限与属性

### 获取文件属性

平时使用最多的 shell 命令 `ls -al` 就是提取的文件属性来显示。

```c
  struct stat {
      dev_t     st_dev;         /* ID of device containing file */
      ino_t     st_ino;         /* inode number */
      mode_t    st_mode;        /* file type */
      nlink_t   st_nlink;       /* number of hard links */
      uid_t     st_uid;         /* user ID of owner */
      gid_t     st_gid;         /* group ID of owner */
      dev_t     st_rdev;        /* device ID (if special file) */
      off_t     st_size;        /* total size, in bytes */
      blksize_t st_blksize;     /* blocksize for filesystem I/O */
      blkcnt_t  st_blocks;      /* number of 512B blocks allocated */

      /* Since Linux 2.6, the kernel supports nanosecond
        precision for the following timestamp fields.
        For the details before Linux 2.6, see NOTES. */

      struct timespec st_atim;  /* time of last access */
      struct timespec st_mtim;  /* time of last modification */
      struct timespec st_ctim;  /* time of last status change */

  #define st_atime st_atim.tv_sec      /* Backward compatibility */
  #define st_mtime st_mtim.tv_sec
  #define st_ctime st_ctim.tv_sec
  };

  /**
   * @brief 获取文件的属性并存储于结构 stat 中
   */
  //如果文件是符号链接，那么获取被链接文件的属性
  int stat(const char *pathname, struct stat *buf);
  //获取已打开文件的属性
  int fstat(int fd, struct stat *buf);
  //如果文件是符号链接，那么获取该符号链接的属性
  int lstat(const char *pathname, struct stat *buf);

  //根据用户指定的 dirfd 和提供的路径 pathname 来获取文件属性，
  //flags 用于控制是否读取符号链接本身
  int fstatat(int dirfd, const char *pathname, struct stat *buf,
              int flags);

  /**
   * @brief 也可以使用下面的函数修改时间戳
   */
  int futimes(int fd, const struct timeval tv[2]);

  int lutimes(const char *filename, const struct timeval tv[2]);

  int utimensat(int dirfd, const char *pathname,
                const struct timespec times[2], int flags);

  int futimens(int fd, const struct timespec times[2]);
```

如下代码所示，使用 lstat 来判断文件类型:

```c
  #include <stdio.h>
  #include <sys/types.h>
  #include <sys/stat.h>
  #include <unistd.h>

  int main(int argc, char *argv[])
  {
      struct stat file_stat = {0};

      if(argc != 2)
      {
          printf("usage: ./a.out <file_path>\n");
          goto quick_out;
      }
      if(lstat(argv[1], &file_stat) == -1)
      {
          perror("can not get file status:");
          goto quick_out;
      }
      printf("The file type is : ");
      if(S_ISREG(file_stat.st_mode))
      {
          printf("regular file");
      }
      else if(S_ISDIR(file_stat.st_mode))
      {
          printf("directory");
      }
      else if(S_ISSOCK(file_stat.st_mode))
      {
          printf("socket");
      }
      else if(S_ISCHR(file_stat.st_mode))
      {
          printf("character device");
      }
      else if(S_ISBLK(file_stat.st_mode))
      {
          printf("block device");
      }
      else if(S_ISFIFO(file_stat.st_mode))
      {
          printf("FIFO");
      }
      else if(S_ISLNK(file_stat.st_mode))
      {
          printf("symbolic link");
      }
      else
      {
          printf("unknown!");
      }

      printf("\n");

  quick_out:
      return 0;
  }
```

### 操作文件的权限

与操作文件相关的 ID 具有下面几类：

| 类型                 | 说明                                               |
| ------------------ | ------------------------------------------------ |
| 真实用户ID和真实组ID       | 表示当前是哪个用户位于哪个组正在访问此文件                            |
| 有效用户ID，有效组ID和补充组ID | 表示该文件允许的用户和组(在没有suid,sgid的情况下，此值与真实用户和真实组ID是一个值) |
| suid               | 当文件user的可执行权限打开并设置了suid后，其他用户可以以该文件所有者的权限来运行此文件  |
| sgid               | 当文件group的可执行权限打开并设置了sgid后，其他用户可以以该文件组成员的权限来运行此文件 |

- 对于权限方面还有一个(sticky bit):当文件other的可执行权限打开并设置了sticky后，用户都可以在此文件夹下新建文件和文件夹(类似于共享文件夹)
  + 但用户不能删除其他用户所新建的文件或文件夹
- 对于普通权限 `rwx` 不得不提的是：
  + 要进入基本的目录，至少要具有 `x` 权限，要读取目录内容列表信息，至少要具有 `rx` 权限。
  + 对一个文件是否具有新建或删除的权限，要看用户对此目录是否具有 `rw` 权限。
    - 这与文件自身的权限无关， **自身权限只关联其内容的操作权限**

可以使用下面的函数来判断当前进程是否有权限访问某个文件:

```c
  int access(const char *pathname, int mode);
  int faccessat(int dirfd, const char *pathname, int mode, int flags);
```

### 修改权限

```c
  //修改文件权限
  int chmod(const char *pathname, mode_t mode);
  int fchmod(int fd, mode_t mode);
  int fchmodat(int dirfd, const char *pathname, mode_t mode, int flags);
  //改变用户id和组id
  int chown(const char *pathname, uid_t owner, gid_t group);
  int fchown(int fd, uid_t owner, gid_t group);
  int lchown(const char *pathname, uid_t owner, gid_t group);
  int fchownat(int dirfd, const char *pathname,
               uid_t owner, gid_t group, int flags);
```

## 硬链接

  每增加一个硬链接，文件的链接数量加1，以表示有多少个文件引用到同一个inode.

```c
  int link(const char *oldpath, const char *newpath);
  int linkat(int olddirfd, const char *oldpath,
             int newdirfd, const char *newpath, int flags);
```

  每取消一个硬链接，文件的链接数量减1，当一个文件的链接数量减至0 **并且没有进程打开此文件时** ，文件既被删除。

- 当有进程打开了文件，那么当进程退出或关闭文件时，内核检查引用计数为0，才删除文件。

```c
  int unlink(const char *pathname);
  int unlinkat(int dirfd, const char *pathname, int flags);
  //移除文件时，与 unlink 一致，移除文件夹时，与 rmdir 一致
  int remove(const char *pathname);
```

## 符号链接

- 创建

```c
  int symlink(const char *target, const char *linkpath);
  int symlinkat(const char *target, int newdirfd, const char *linkpath);
```

- 读取符号链接本身内容(可以看到其block内容为其引用文件路径)

```c
  ssize_t readlink(const char *pathname, char *buf, size_t bufsiz);
  ssize_t readlinkat(int dirfd, const char *pathname,
                     char *buf, size_t bufsiz);
```

## 名称

```c
  int rename(const char *oldpath, const char *newpath);
  int renameat(int olddirfd, const char *oldpath,
               int newdirfd, const char *newpath);

  int renameat2(int olddirfd, const char *oldpath,
                int newdirfd, const char *newpath, unsigned int flags);
```

# 文件系统与设备驱动(include/linux/fs.h)

在设备驱动中，会关心 file 和 inode 这两个结构体。

- 每打开一个文件，在内核空间中就有与之关联的 file 结构体
  + 设备驱动通过此结构体判断用户操作模式(比如是阻塞还是非阻塞等)
    - 判断阻塞还是非阻塞使用 `f_flags` 
  + `private_data` 保存该设备驱动申请的数据地址
- inode 则包含了一个文件的详细信息，比如权限、生成时间、访问时间、最后修改时间等

## file

```c
struct file {
    union {
        struct llist_node    f_llist;
        struct rcu_head     f_rcuhead;
        unsigned int         f_iocb_flags;
    };
    struct path        f_path;
    struct inode        *f_inode;    /* cached value */
    const struct file_operations    *f_op; // 和文件关联的操作

    /*
     * Protects f_ep, f_flags.
     * Must not be taken from IRQ context.
     */
    spinlock_t        f_lock;
    atomic_long_t        f_count;
    unsigned int         f_flags; // 文件标志，如 O_RDONLY、O_NONBLOCK 
    fmode_t            f_mode;// 文件读/写模式，FMODE_READ 和 FMODE_WRITE
    struct mutex        f_pos_lock;
    loff_t            f_pos; // 当前读写的位置
    struct fown_struct    f_owner;
    const struct cred    *f_cred;
    struct file_ra_state    f_ra;

    u64            f_version;
#ifdef CONFIG_SECURITY
    void            *f_security;
#endif
    /* needed for tty driver, and maybe others */
    void            *private_data; // 文件私有数据

#ifdef CONFIG_EPOLL
    /* Used by fs/eventpoll.c to link all the hooks to this file */
    struct hlist_head    *f_ep;
#endif /* #ifdef CONFIG_EPOLL */
    struct address_space    *f_mapping;
    errseq_t        f_wb_err;
    errseq_t        f_sb_err; /* for syncfs */
} __randomize_layout
  __attribute__((aligned(4)));    /* lest something weird decides that 2 is OK */
```

## inode

```c
/*
 * Keep mostly read-only and often accessed (especially for
 * the RCU path lookup and 'stat' data) fields at the beginning
 * of the 'struct inode'
 */
struct inode {
    umode_t            i_mode; // inode 权限
    unsigned short        i_opflags;
    kuid_t            i_uid; // inode 拥有者 id
    kgid_t            i_gid; // inode 所属群组 id
    unsigned int        i_flags;

#ifdef CONFIG_FS_POSIX_ACL
    struct posix_acl    *i_acl;
    struct posix_acl    *i_default_acl;
#endif

    const struct inode_operations    *i_op;
    struct super_block    *i_sb;
    struct address_space    *i_mapping;

#ifdef CONFIG_SECURITY
    void            *i_security;
#endif

    /* Stat data, not accessed from path walking */
    unsigned long        i_ino;
    /*
     * Filesystems may only read i_nlink directly.  They shall use the
     * following functions for modification:
     *
     *    (set|clear|inc|drop)_nlink
     *    inode_(inc|dec)_link_count
     */
    union {
        const unsigned int i_nlink;
        unsigned int __i_nlink;
    };
    dev_t            i_rdev; // 若是设备文件，此字段记录设备的设备号
    loff_t            i_size; // inode 所代表的文件大小
    struct timespec64    i_atime; // 最近一次的存取时间
    struct timespec64    i_mtime; // 最近一次的修改时间
    struct timespec64    i_ctime; // inode 的产生时间
    spinlock_t        i_lock;    /* i_blocks, i_bytes, maybe i_size */
    unsigned short          i_bytes;
    u8            i_blkbits;
    u8            i_write_hint;
    blkcnt_t        i_blocks; // inode 所使用的 block 数

#ifdef __NEED_I_SIZE_ORDERED
    seqcount_t        i_size_seqcount;
#endif

    /* Misc */
    unsigned long        i_state;
    struct rw_semaphore    i_rwsem;

    unsigned long        dirtied_when;    /* jiffies of first dirtying */
    unsigned long        dirtied_time_when;

    struct hlist_node    i_hash;
    struct list_head    i_io_list;    /* backing dev IO list */
#ifdef CONFIG_CGROUP_WRITEBACK
    struct bdi_writeback    *i_wb;        /* the associated cgroup wb */

    /* foreign inode detection, see wbc_detach_inode() */
    int            i_wb_frn_winner;
    u16            i_wb_frn_avg_time;
    u16            i_wb_frn_history;
#endif
    struct list_head    i_lru;        /* inode LRU list */
    struct list_head    i_sb_list;
    struct list_head    i_wb_list;    /* backing dev writeback list */
    union {
        struct hlist_head    i_dentry;
        struct rcu_head        i_rcu;
    };
    atomic64_t        i_version;
    atomic64_t        i_sequence; /* see futex */
    atomic_t        i_count;
    atomic_t        i_dio_count;
    atomic_t        i_writecount;
#if defined(CONFIG_IMA) || defined(CONFIG_FILE_LOCKING)
    atomic_t        i_readcount; /* struct files open RO */
#endif
    union {
        const struct file_operations    *i_fop;    /* former ->i_op->default_file_ops */
        void (*free_inode)(struct inode *);
    };
    struct file_lock_context    *i_flctx;
    struct address_space    i_data;
    struct list_head    i_devices;
    union {
        struct pipe_inode_info    *i_pipe;
        struct cdev        *i_cdev; // 若是字符设备，为其对应的 cdev 结构体指针
        char            *i_link;
        unsigned        i_dir_seq;
    };

    __u32            i_generation;

#ifdef CONFIG_FSNOTIFY
    __u32            i_fsnotify_mask; /* all events this inode cares about */
    struct fsnotify_mark_connector __rcu    *i_fsnotify_marks;
#endif

#ifdef CONFIG_FS_ENCRYPTION
    struct fscrypt_info    *i_crypt_info;
#endif

#ifdef CONFIG_FS_VERITY
    struct fsverity_info    *i_verity_info;
#endif

    void            *i_private; /* fs or device private pointer */
} __randomize_layout;
```

- `i_rdev` 表示设备编号，由高12位主设备号和低20位次设备号组成，使用下面的函数获取主次设备号
  + 主设备号代表同一类设备，次设备号表示使用该设备的实例对象

```c
#define MINORBITS    20
#define MINORMASK    ((1U << MINORBITS) - 1)

#define MAJOR(dev)    ((unsigned int) ((dev) >> MINORBITS))
#define MINOR(dev)    ((unsigned int) ((dev) & MINORMASK))
#define MKDEV(ma,mi)    (((ma) << MINORBITS) | (mi))

static inline unsigned iminor(const struct inode *inode)
{
    return MINOR(inode->i_rdev);
}

static inline unsigned imajor(const struct inode *inode)
{
    return MAJOR(inode->i_rdev);
}
```

- 也可以在 `/proc/devices` 中得到注册设备的主设备号和设备名

```shell
cat /proc/devices
```

- 可以在 `/dev/` 下得到注册设备的主次设备号

# udev 用户空间设备管理

```shell
Linux设计中强调的一个基本观点是机制和策略分离。
机制是做某样事情的固定步骤、方法，而策略是每一个步骤所采取的不同方式。
机制是固定的，而每个步骤采用的策略是不固定的。机制是稳定的，而策略是灵活的。
因此，在Linux内核中，不应该实现策略。
```

udev完全在用户态工作，利用设备加入或移出时内核所发送的热拔插事件(Hotplug Event)来工作。
在热拔插时，设备的详细信息会由内核通过netlink套接字发送出来，发出的事件叫uevent。
udev的设备命名策略、权限控制和事件处理都是在用户态下完成的，它利用从内核收到的信息来进行创建设备文件节点等工作。

udev的工作过程：

1. 当内核检测到系统中出现了新设备后，内核会通过netlink套接字发送uevent
2. udev获取内核发送的信息，进行规则的匹配。匹配的事物包括SUBSYSTEM、ACTION、attribute，内核提供的名称(通过KERNEL=)以及其他的环境变量

使用下面的代码就可以接收 netlink 消息：

```c
#include <stdio.h>
#include <assert.h>
#include <string.h>

#include <unistd.h>
#include <poll.h>
#include <linux/netlink.h>
#include <sys/types.h>
#include <sys/socket.h>


int main(int argc, char* argv[]) {
    struct sockaddr_nl nls;
    struct pollfd pfd;
    char buf[512];

    memset(&nls, 0, sizeof(nls));

    nls.nl_family = AF_NETLINK;
    nls.nl_pid = getpid();
    nls.nl_groups = -1;

    pfd.events = POLLIN;
    pfd.fd = socket(PF_NETLINK, SOCK_DGRAM, NETLINK_KOBJECT_UEVENT);
    assert(pfd.fd != -1);

    int ret = bind(pfd.fd, (void *)&nls, sizeof(nls));
    assert(ret == 0);

    while (poll(&pfd, 1, -1) != -1) {
        int len = recv(pfd.fd, buf, sizeof(buf), MSG_DONTWAIT);
        assert(len != -1);

        int i = 0;
        while (i < len) {
            printf("%s\n", buf + i);
            i += strlen(buf + i) + 1;
        }
    }

    return 0;
}
```

如果想要让内核主动发出一次 uevent，则可以对 `/sys/module` 中的模块主动写 `add` 命令：

```shell
 echo add > /sys/module/psmouse/uevent
```

会输出类似以下的消息:

```shell
add@/module/psmouse
ACTION=add
DEVPATH=/module/psmouse
SUBSYSTEM=module
SYNTH_UUID=0
SEQNUM=739
```

# sysfs

sysfs是内核设备模型的一个全局概览，此目录下的多个顶层文件是站在不同的角度来查看设备模型的：

- `bus` 是以总线的视角来看待。
  + 首先，总线有很多种类型，所以在bus目录下会有多个代表不同总线类型的文件
  + 其次，每种总线相对应的就包含设备和驱动，所以就会有 `devices,drivers` 文件夹
    + 设备下的文件是 `/sys/devices` 中文件的符号链接
- `devices` 是以设备的视角看待
  + 首先，设备是以层级的方式拓扑的，所以目录也是以此层级进行排列的
  + 其次，当设备与驱动匹配以后，对应设备目录就会有 `driver` 目录
- `class` 是以设备种类的视角看待设备
  + 此目录下都是以种类区分各种设备
  + 设备下的文件是 `/sys/devices` 中文件的符号链接
- `block` 是单独列出块设备文件
- `dev` 是块设备和字符设备文件

在代码实现中，分别使用 `bus_type,device_driver,device` 来描述总线、驱动和设备:

```c
struct bus_type {
    const char        *name;
    const char        *dev_name;
    struct device        *dev_root;
    const struct attribute_group **bus_groups;
    const struct attribute_group **dev_groups;
    const struct attribute_group **drv_groups;

    int (*match)(struct device *dev, struct device_driver *drv);
    int (*uevent)(struct device *dev, struct kobj_uevent_env *env);
    int (*probe)(struct device *dev);
    void (*sync_state)(struct device *dev);
    void (*remove)(struct device *dev);
    void (*shutdown)(struct device *dev);

    int (*online)(struct device *dev);
    int (*offline)(struct device *dev);

    int (*suspend)(struct device *dev, pm_message_t state);
    int (*resume)(struct device *dev);

    int (*num_vf)(struct device *dev);

    int (*dma_configure)(struct device *dev);
    void (*dma_cleanup)(struct device *dev);

    const struct dev_pm_ops *pm;

    const struct iommu_ops *iommu_ops;

    struct subsys_private *p;
    struct lock_class_key lock_key;

    bool need_parent_lock;
};
```

```c
struct device_driver {
    const char        *name;
    struct bus_type        *bus;

    struct module        *owner;
    const char        *mod_name;    /* used for built-in modules */

    bool suppress_bind_attrs;    /* disables bind/unbind via sysfs */
    enum probe_type probe_type;

    const struct of_device_id    *of_match_table;
    const struct acpi_device_id    *acpi_match_table;

    int (*probe) (struct device *dev);
    void (*sync_state)(struct device *dev);
    int (*remove) (struct device *dev);
    void (*shutdown) (struct device *dev);
    int (*suspend) (struct device *dev, pm_message_t state);
    int (*resume) (struct device *dev);
    const struct attribute_group **groups;
    const struct attribute_group **dev_groups;

    const struct dev_pm_ops *pm;
    void (*coredump) (struct device *dev);

    struct driver_private *p;
};
```

```c
struct device {
    struct kobject kobj;
    struct device        *parent;

    struct device_private    *p;

    const char        *init_name; /* initial name of the device */
    const struct device_type *type;

    struct bus_type    *bus;        /* type of bus device is on */
    struct device_driver *driver;    /* which driver has allocated this
                       device */
    void        *platform_data;    /* Platform specific data, device
                       core doesn't touch it */
    void        *driver_data;    /* Driver data, set and get with
                       dev_set_drvdata/dev_get_drvdata */
    //...
};
```

device_driver 和 device 都依附于总线，所以都包含了 `bus_type` 指针。而 device 又由 driver 驱动，所以它还包含了 `device_driver` 指针。

设备和驱动都是分开被注册的，总线的`match`函数来进行对应的匹配，匹配成功后驱动的`probe()`函数就会被调用。

总线、设备和驱动都会映射在 `sysfs` 中，其中的目录来源于 `bus_type,device_driver,device` ，而目录中的文件来源于 `attribute` 。

```c
struct attribute {
    const char        *name;
    umode_t            mode;
#ifdef CONFIG_DEBUG_LOCK_ALLOC
    bool            ignore_lockdep:1;
    struct lock_class_key    *key;
    struct lock_class_key    skey;
#endif
};

struct bus_attribute {
    struct attribute    attr;
    ssize_t (*show)(struct bus_type *bus, char *buf);
    ssize_t (*store)(struct bus_type *bus, const char *buf, size_t count);
};

struct device_attribute {
    struct attribute    attr;
    ssize_t (*show)(struct device *dev, struct device_attribute *attr,
            char *buf);
    ssize_t (*store)(struct device *dev, struct device_attribute *attr,
             const char *buf, size_t count);
}
```

对于以上结构，内核提供了快捷的操作宏：

```c
#define DEVICE_ATTR(_name, _mode, _show, _store) \
    struct device_attribute dev_attr_##_name = __ATTR(_name, _mode, _show, _store)
#define DEVICE_ATTR_PREALLOC(_name, _mode, _show, _store) \
    struct device_attribute dev_attr_##_name = \
        __ATTR_PREALLOC(_name, _mode, _show, _store)
#define DEVICE_ATTR_RW(_name) \
    struct device_attribute dev_attr_##_name = __ATTR_RW(_name)
#define DEVICE_ATTR_ADMIN_RW(_name) \
    struct device_attribute dev_attr_##_name = __ATTR_RW_MODE(_name, 0600)
#define DEVICE_ATTR_RO(_name) \
    struct device_attribute dev_attr_##_name = __ATTR_RO(_name)
#define DEVICE_ATTR_ADMIN_RO(_name) \
    struct device_attribute dev_attr_##_name = __ATTR_RO_MODE(_name, 0400)
#define DEVICE_ATTR_WO(_name) \
    struct device_attribute dev_attr_##_name = __ATTR_WO(_name)
#define DEVICE_ULONG_ATTR(_name, _mode, _var) \
    struct dev_ext_attribute dev_attr_##_name = \
        { __ATTR(_name, _mode, device_show_ulong, device_store_ulong), &(_var) }
#define DEVICE_INT_ATTR(_name, _mode, _var) \
    struct dev_ext_attribute dev_attr_##_name = \
        { __ATTR(_name, _mode, device_show_int, device_store_int), &(_var) }
#define DEVICE_BOOL_ATTR(_name, _mode, _var) \
    struct dev_ext_attribute dev_attr_##_name = \
        { __ATTR(_name, _mode, device_show_bool, device_store_bool), &(_var) }
#define DEVICE_ATTR_IGNORE_LOCKDEP(_name, _mode, _show, _store) \
    struct device_attribute dev_attr_##_name =        \
        __ATTR_IGNORE_LOCKDEP(_name, _mode, _show, _store)

#define BUS_ATTR_RW(_name) \
    struct bus_attribute bus_attr_##_name = __ATTR_RW(_name)
#define BUS_ATTR_RO(_name) \
    struct bus_attribute bus_attr_##_name = __ATTR_RO(_name)
#define BUS_ATTR_WO(_name) \
    struct bus_attribute bus_attr_##_name = __ATTR_WO(_name)
```

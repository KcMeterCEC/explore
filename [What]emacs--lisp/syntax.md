[What]emacs --> lisp
=======================

elisp 实际上是函数式的调用方式，和 c/c++ 一样都具有函数名和参数。而 emacs 就相当于是一个操作系统，对 emacs 的设置就是调用函数并设置参数，来达到改变当前应用环境的目的。

### 进入elisp 测试模式

在进入 emacs 后，按下 `q` 便可进入。在函数后的括号输入 `C - j` 或者 `C - x C - e` 便可执行当前函数，

### 注释：

使用两个分号 `;;`

### 函数 ：

函数的基本形式 `(functionName var1 var2)`

当然，函数也可以嵌套，嵌套函数在括号处返回结果

#### 常用函数

- setq 给变量赋值

> (setq name "Bastien")

- insert 在光标处插入字符串

> (insert "Hello")

> (insert "Hello" "world")

> (insert "Hello, I am" name)

- switch-to-buffer-other-window 新建一个buffer

> (switch-to-buffer-other-window "\*test\*") ;; 新建一个名为 "\*test\*" 的buffer

- progn 顺序执行函数

> (progn (switch-to-buffer-other-window "\*test\*") (hello "you")) ;; 新建 buffer 并且执行 hello 函数

- format 格式化字符串

> (format "Hello %s!\n" "visitor")


### 定义函数

> (defun hello () (insert "Hello, I am" name))

> (hello)

> (defun hello (name) (insert "Hello" name))

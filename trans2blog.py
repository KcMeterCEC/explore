#! /usr/bin/env python3
# -*- coding: utf-8 -*-

# 将符合格式　xxx.org /xxx.md 文件复制一份出来并移动到博客的　_post 目录中
#　1. 读取　xxx.org 中的　"#+NAME:" 字段，并新建此字段所指定的文件
#  2. 将 xxx.org 中的内容复制一份到新建文件中
#　3. 将文件中的图片文件地址重定向到github中的地址去

import re
import os
import shutil
import filecmp

blog_source = "/home/cec/github/blog/source/_posts";
html_str = "https://github.com/KcMeterCEC/explore/blob/master"

def get_real_name(file_path, pwd_path):
    with open(file_path, 'r') as f_readme:
        lines = f_readme.readlines()
        flen = len(lines)
        sweep = 0
        name_file = ''
        for i in range(flen):
            check_file = 0
            if '#+NAME:' in lines[i]: #this is org mod file
                name_file = re.search('<(.+)>',lines[i]).group(1)
                # check_file = 1
            if 'comments: true' in lines[i]: #this is markdown file
                name_file = os.path.basename(file_path)
                check_file = 1
            if check_file == 1:
                blog_file = blog_source + name_file;
                if os.path.exists(blog_file) == False or filecmp.cmp(file_path, blog_file) == False:
                    sweep = 1
                else:
                    break
            if sweep == 1:
                redir_pic = 0
                pic_str = ''
                if '.jpg]]' in lines[i]:
                    pic_str = re.search('\[\[\.\/(.+)\]\]',lines[i]).group(1)
                    redir_pic = 1
                if '.jpg)' in lines[i] or '.gif)' in lines[i]:
                    if '![]' in lines[i]:
                        pic_str = re.search('\(\.\/(.+)\)',lines[i]).group(1)
                        redir_pic = 2

                if redir_pic:
                    temp_str = html_str + pwd_path.lstrip('.') + "/"
                    temp_str += pic_str
                    temp_str += "?raw=true"
                    new_str = "#+HTML:<img src=\"%s\" alt=\"%s\">" %(temp_str,pic_str)
                    if redir_pic == 2:
                        new_str = "![](%s)" %(temp_str)
                    lines[i] = new_str
                if '#+BEGIN_HTML' in lines[i]:
                    lines[i] = "\n#+BEGIN_EXPORT html\n"
                if '#+END_HTML' in lines[i]:
                    lines[i] = "#+END_EXPORT\n\n"
        if sweep == 1:
            with open(name_file,'w') as f_new:
                f_new.writelines(lines)
            if os.path.exists(blog_file) == False or filecmp.cmp(name_file, blog_file) == False:
                print("%s \n ==> \n %s" %(file_path, blog_file))
                print("---------->update\n")
                shutil.copy(name_file, blog_source)
            os.remove(name_file)

def sweep_dir(root_dir):
    for list in os.listdir(root_dir):
        path = os.path.join(root_dir, list)
        if os.path.splitext(path)[1] == '.org' or os.path.splitext(path)[1] == '.md':
            get_real_name(path, root_dir)
        if os.path.isdir(path):
            sweep_dir(path)

sweep_dir('./')


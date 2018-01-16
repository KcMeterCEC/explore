#! /usr/bin/env python3
# -*- coding: utf-8 -*-

# 将　README.org 文件复制一份出来并移动到博客的　_post 目录中
#　1. 读取　xxx.org 中的　"#+NAME:" 字段，并新建此字段所指定的文件
#  2. 将 xxx.org 中的内容复制一份到新建文件中
#　3. 将文件中的图片文件地址重定向到github中的地址去

import re
import os
import shutil

raw_file_name = input("Please input the file name:")

html_str = "https://github.com/KcMeterCEC/explore/blob/master"
pwd_str = os.path.abspath(".")
new_str = re.search('/home/cec/github/explore(.+)', pwd_str).group(1)
html_str += new_str
html_str += "/"
print("The prefix of picture:",html_str)


with open(raw_file_name, 'r') as f_readme:
    lines = f_readme.readlines()
    flen = len(lines)
    for i in range(flen):
        if '#+NAME:' in lines[i]:
            name_file = re.search('<(.+)>',lines[i]).group(1)
            print("new file name is ", name_file)
        if '.jpg]]' in lines[i]:
            pic_str = re.search('\[\[\.\/(.+)\]\]',lines[i]).group(1)
            temp_str = html_str
            temp_str += pic_str
            temp_str += "?raw=true"
            new_str = "#+HTML:<img src=\"%s\" alt=\"%s\">" %(temp_str,pic_str)
            lines[i] = new_str
            print(lines[i])

    with open(name_file,'w') as f_new:
        f_new.writelines(lines)

shutil.copy(name_file,"/home/cec/github/kcmetercec.github.io/hexo/source/_posts/")
os.remove(name_file)

---
title: '[What] 现代 cmake 速览'
tags:
- cmake
date:  2021/6/10
categories: 
- linux
- make
- cmake
layout: true
---

- 学习书籍：
  + [《Modern CMake》](https://cliutils.gitlab.io/modern-cmake/)
  + [Effective Modern CMake](https://gist.github.com/mbinna/c61dbb39bca0e4fb7d1f73b0d66a4fd1)
- CMake 版本：3.18.2 

在看了 GNU Radio 3.8 系列的 cmake 文件后，发现现在的 cmake 已经变化了挺多。
而我还停留在 cmake 2.8 的时代，有必要来了解一下现代 cmake 构建方式，以提高构建工程的搭建速度。

<!--more-->

# 概览
## 运行 CMake
如果要屏蔽掉不同构建工具的差异，那么在 build 目录外运行 cmake 命令可以少打一些字……
### 构建
平常在 linux 下最常用的构建命令就是：
``` shell
mkdir build
cd build
cmake ../
make
```

但在其他系统上，最终的构建工具不一定是 make，为了屏蔽掉不同构建工具的差异，应该使用下面的方式：
``` shell
# 以当前目录为顶层源目录，创建 build 文件夹
cmake -S ./ -B build
# 在 build 文件夹中运行构建
cmake --build build
# 如果想要多核并行编译，那么可以加上 -j N 参数指定核心数
cmake --build build -j 4
```


### 安装

``` shell
# 在 build 目录中，以前是使用 make 进行 install
make install

# 现在在 build 目录中，可以使用下面的命令以屏蔽掉构建工具的差异
cmake --install ./
# 如果在 build 目录外，使用下面的指令
cmake --install build
```


### 设置构建工具及编译器

CMake 默认的构建工具是 `make` ，默认的编译器是 `gcc` 和 `g++` 。

可以在**首次生成构建目录时**，通过：
- 指定 `CMAKE_GENERATOR` 来设定构建工具
- 指定 `CC` , `CXX` 来分别指定 c 和 c++ 编译器

``` shell
# 配置编译器为 clang 构建系统为 Ninja
CC=clang CXX=clang++ CMAKE_GENERATOR=Ninja cmake -S ./ -B build
```


### 设定选项

对于当前构建工程的可设选项，可以通过 `cmake -L <build_path>` 来输出，通过 `cmake -D<option>` 来设置选项的值。

以下是一些常用的选项：
- `-DCMAKE_BUILD_TYPE` ：指定编译的类型，其值常用的是 `Release` , `RelWithDebInfo` , `Debug` 
- `-DCMAKE_INSTALL_PREFIX` ：指定安装路径，在 UNIX 中的默认路径是 `/usr/local` 
- `-DBUILD_SHARED_LIBS` : 设置 `ON` 或 `OFF` 来设置是否以共享库的形式编译
- `-DBUILD_TESTING` : 测试构建



### 调试

调试 CMake 时，可以在生成构建时使用 `--trace` 选项以输出详细信息



## CMake 的一些使用习惯

养成下面这些 CMake 的使用习惯，可以高效稳定的完成构建。
- 不要使用全局函数：比如 `link_directories,include_libraries` 这类函数
- 不要对使用该 cmake 的用户设定一些不必要的规则：比如必须用户输入一些不必要的选项才能够正常工作
  + 这些东西应该尽量在 cmake 中尽量私有化的设定好
- 不要在 cmake 构建系统外添加全局文件：一般都是在添加一个文件到工程中后，重新执行一次 cmake 构建即可
- 直接链接到构建的文件：如果有多个依赖，直接链接到构建文件，可以在构建文件更新后，使用依赖方也实时生效
- 在链接的时候，不要跳过 `PUBILC/PRIVATE` 
- 将 CMake 文件当作编码一样对待，也需要尽量保证简洁和可读性
- 将 targets 作为 INTERFACE 以保证及高内聚低耦合的特性
- 保证能正常的构建和安装
- 编写 `Config.cmake` 文件以正常的配置
- 使用 ALIAS targets 以保证使用的一致性：使用 `add_subdirectory` 和 `find_package` 需要提供相同的 targets 和名称空间
- 将频繁使用的函数组合用函数或宏来包裹
- 函数名和宏名都使用小写形式，只有变量名才使用大写
- 使用 `cmake_policy`



# 基础速览



## 基础结构

以下是绝大部分顶层 `CMakeLists.txt` 所含有的部分。



### 最小版本需求

```cmake
cmake_minimum_required(VERSION 3.1)
#starting in 3.12
cmake_minimum_required(VERSION 3.7...3.18)
```
- 虽然 `cmake_minimum_required` 是不区分大小写的，但是函数还是按照习惯使用小写为好
- 后面的版本号表明了构建的策略，即使使用最新版本的 CMake，它也会按照该版本要求来执行对应版本的策略
- 在 CMake 3.12 及以后，可以表明一个版本范围。以说明该构建项目在这些版本上都经过了测试。

对于一些特定场合下的构建策略，可以这样：
```cmake
# 默认支持 3.7~3.18 版本
cmake_minimum_required(VERSION 3.7...3.18)

# 如果当前系统 CMake 版本低于 3.12，那就使用当前 CMake 版本的策略
# 否则就使用 3.7 策略
if(${CMAKE_VERSION} VERSION_LESS 3.12)
  cmake_policy(VERSION${CMAKE_MAJOR_VERSION}.${CMAKE_MINOR_VERSION})
endif()
```


### 设置工程

``` cmake
# 工程的名称为 MyProject，之后的选项都是可选的
project(MyProject VERSION 1.0 DESCRIPTION "Very nice project" LANGUAGES CXX)
```


### 创建可执行文件

``` cmake
# one 是可执行文件的名称，后面跟文件列表
add_executable(one two.cpp three.h)
```


### 创建库

``` cmake
# 创建一个名称为 one 的静态库
# 库类型通常为 STATIC, SHARED, MODULE
add_library(one STATIC two.cpp three.h)
```
当需要将一个静态库链接至动态库中时，需要使用  "-Wl,--whole-archive" 选项才行：

```cmake
# 首先将已有的源文件链接为一个动态链接库，相当于创建了一个 target SHARED_LIB_NAME
add_library(${SHARED_LIB_NAME} SHARED ${DIGITAL_SOURCES})
# 然后再对该 target 链接其他的静态库
target_link_libraries(${SHARED_LIB_NAME} PUBLIC 
# 告诉连接器要链接所有文件
"-Wl,--whole-archive"
${STATIC_LIBRARIES}
# 静态链接完毕，需要恢复到默认
"-Wl,--no-whole-archive"
)
```




### 增加配置
``` cmake
# 将 include 文件夹加入头文件路径
target_include_directories(one PUBLIC include)
# 为 target another 增加库 one
target_link_libraries(another PUBLIC one)
```



### 最终文件

``` cmake
cmake_minimum_required(VERSION 3.8)

project(Calculator LANGUAGES CXX)

add_library(calclib STATIC src/calclib.cpp include/calc/lib.hpp)
target_include_directories(calclib PUBLIC include)
# 使能 c++11 特性
target_compile_features(calclib PUBLIC cxx_std_11)

add_executable(calc apps/calc.cpp)
target_link_libraries(calc PUBLIC calclib)
```



## 变量

### 本地变量
虽然说变量的值在不含空格的情况下，也可以不用引号包含，但还是建议加上以提高可读性
``` cmake
# 定义一个本地变量，变量的名称统一使用大写加下划线
set(MY_VARIABLE "value")
# 定义一个本地列表变量
set(MY_LIST "one" "two")
# 与上面的效果一致
set(MY_LIST "one;two")
```

并且在引用变量的时候，也要为其加上双引号以正确处理变量中包含空格的情况：

``` cmake
  "${MY_PATH}"
```


### cache 变量

``` cmake
# 当变量本来就有值时，这种方式定义的缓存变量不会覆盖原来的值
set(MY_CACHE_VARIABLE "VALUE" CACHE STRING "Description")

# 如果希望 cmake -L 可以搜寻到该变量的话，需要使用如下方式
# 当然这种方式便会强行设置值
set(MY_CACHE_VARIABLE "VALUE" CACHE STRING "" FORCE)
mark_as_advanced(MY_CACHE_VARIABLE)
```

在构建输出目录中， `CMakeCache.txt` 文件便保存了用户的命令行输入设置，以避免每次用户运行 CMake 时都要重新运行这些设置。



### 环境变量

通常应该避免环境变量
``` cmake
# 设置
set(ENV{variable_name} value)
# 获取
$ENV{variable_name}
```



## CMake 编程

CMake 常用下面这些编程模板：



### 流程控制

``` cmake
# 就如同之前提到过的一样，引用变量加上双引号是个好习惯
if("${variable}")
  # True if variable is not false-like
else()
  # Note that undefined variables would be `""` thus false
endif()
```


### 宏与函数

函数与宏的区别在于：函数中对变量的操作是默认不对外部可见的，要想可见需要使用 `PARENT_SCOPE` 
``` cmake
function(SIMPLE REQUIRED_ARG)
    message(STATUS "Simple arguments: ${REQUIRED_ARG}, followed by ${ARGV}")
    # 为了让 REQUIRED_ARG 的值为外部所见，需要使用 PARENT_SCOPE
    set(${REQUIRED_ARG} "From SIMPLE" PARENT_SCOPE)
endfunction()

simple(This)
message("Output: ${This}")
```

函数中可以批量的处理输入的参数：

``` cmake
function(COMPLEX)
    cmake_parse_arguments(
    COMPLEX_PREFIX
    "SINGLE;ANOTHER"
    "ONE_VALUE;ALSO_ONE_VALUE"
    "MULTI_VALUES"
    ${ARGN}
    )
endfunction()

complex(SINGLE ONE_VALUE value MULTI_VALUES some other values)
​``` cmake
最终在函数中得到的变量列表就是：
​``` cmake
  COMPLEX_PREFIX_SINGLE = TRUE
  COMPLEX_PREFIX_ANOTHER = FALSE
  COMPLEX_PREFIX_ONE_VALUE = "value"
  COMPLEX_PREFIX_ALSO_ONE_VALUE = <UNDEFINED>
  COMPLEX_PREFIX_MULTI_VALUES = "some;other;values"
```



## 与代码的交互

### 代码获取 CMake 配置
代码中通常会有预编译宏，而 CMake 中可以定义这些宏。
``` cmake
#增加宏定义 define_var
add_definitions(-Ddefine_var)
```
> 但是这种方式在代码编译器中不可见，所以对于程序员不是那么的直观。

更为推荐的做法是，CMake 通过配置文件来批量的导入，这些配置文件通常以 `.in` 作为后缀。

假设有文件 `Version.h.in` :
``` cmake
#cmakedefine VAR
#cmakedefine01 VAR
#define MY_VERSION_MAJOR "@PROJECT_VERSION_MAJOR@"
#define MY_VERSION_MINOR "@PROJECT_VERSION_MINOR@"
#define MY_VERSION_PATCH "@PROJECT_VERSION_PATCH@"
#define MY_VERSION_TWEAK "@PROJECT_VERSION_TWEAK@"
#define MY_VERSION "@PROJECT_VERSION@"
```

CMake 中包含这个文件:
``` cmake
configure_file (
    "${PROJECT_SOURCE_DIR}/include/My/Version.h.in"
    "${PROJECT_BINARY_DIR}/include/My/Version.h"
)
```
最终在 build 目录中就会出现 Version.h 文件

当 CMakeLists 中定义了这些变量时，对应的宏就会被替换，比如假设定义了变量 `VAR` 那么最终的头文件就就会有：
``` cpp
#define VAR
#define VAR 1
```

**注意：`configure_file` 这个语句需要放在被定义变量的后面！** 

### CMake 获取代码配置
这种方式看起来好别扭啊……
``` cmake
  # Assuming the canonical version is listed in a single line
  # This would be in several parts if picking up from MAJOR, MINOR, etc.
  set(VERSION_REGEX "#define MY_VERSION[ \t]+\"(.+)\"")

  # Read in the line containing the version
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/include/My/Version.hpp"
      VERSION_STRING REGEX ${VERSION_REGEX})

  # Pick out just the version
  string(REGEX REPLACE ${VERSION_REGEX} "\\1" VERSION_STRING "${VERSION_STRING}")

  # Automatically getting PROJECT_VERSION_MAJOR, My_VERSION_MAJOR, etc.
  project(My LANGUAGES CXX VERSION ${VERSION_STRING})
```



### CMake 工程目录结构

``` shell
  - project
    - .gitignore        # gitignore 文件用于过滤不需要加入版本控制的文件
    - README.md         # 对工程的简要说明
    - LICENCE.md        # 如果是开源项目，那么版权还是需要明确注明
    - CMakeLists.txt    # 顶层构建文件
    - cmake             # 封装好的脚本
      - FindSomeLib.cmake
      - something_else.cmake
    - include           # 头文件单独存放，这个是用于公开给用户的头文件
      - project
        - lib.hpp
    - src               # 源文件层以库的形式组织
      - CMakeLists.txt
      - lib.cpp
    - apps              # 应用代码单独分离
      - CMakeLists.txt
      - app.cpp
    - tests             # 单独对库的测试用例
      - CMakeLists.txt
      - testlib.cpp
    - docs              # 生成对项目的说明文档
      - CMakeLists.txt
    - extern            # 第三方工具包，一般使用 gitsubmodule 开引用，这样便于后期升级维护
      - googletest
    - scripts           # 在 CMake 之上的脚本
      - helper.py
```

- 添加包含 `CMakeLists.txt` 的文件夹，使用 `add_subdirectory` 函数
- 添加包含 cmake 模块的文件夹，使用 `set(CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})`

## 运行其它程序
使用 `execute_process` 可以在配置期间运行外部程序。

一般不直接指定外部程序的运行路径，而是通过 `${CMAKE_COMMAND}` , `find_package()` , `find_program()` 来获取程序。

使用 `RESULT_VARIABLE` 来获取返回值， `OUTPUT_VARIABLE` 来获取程序输出。

如下为更新 git submodules:
``` cmake
  find_package(Git QUIET)

  if(GIT_FOUND AND EXISTS "${PROJECT_SOURCE_DIR}/.git")
      execute_process(COMMAND ${GIT_EXECUTABLE} submodule update --init --recursive
                      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                      RESULT_VARIABLE GIT_SUBMOD_RESULT)
      if(NOT GIT_SUBMOD_RESULT EQUAL "0")
          message(FATAL_ERROR "git submodule update --init failed with ${GIT_SUBMOD_RESULT}, please checkout submodules")
      endif()
  endif()
```



## 一个简单的示例

``` cmake
  # Almost all CMake files should start with this
  # You should always specify a range with the newest
  # and oldest tested versions of CMake. This will ensure
  # you pick up the best policies.
  cmake_minimum_required(VERSION 3.1...3.16)

  # This is your project statement. You should always list languages;
  # Listing the version is nice here since it sets lots of useful variables
  project(
    ModernCMakeExample
    VERSION 1.0
    LANGUAGES CXX)

  # If you set any CMAKE_ variables, that can go here.
  # (But usually don't do this, except maybe for C++ standard)

  # Find packages go here.

  # You should usually split this into folders, but this is a simple example

  # This is a "default" library, and will match the *** variable setting.
  # Other common choices are STATIC, SHARED, and MODULE
  # Including header files here helps IDEs but is not required.
  # Output libname matches target name, with the usual extensions on your system
  add_library(MyLibExample simple_lib.cpp simple_lib.hpp)

  # Link each target with other targets or add options, etc.

  # Adding something we can run - Output name matches target name
  add_executable(MyExample simple_example.cpp)

  # Make sure you link your targets with this command. It can also link libraries and
  # even flags, so linking a target that does not exist will not give a configure-time error.
  target_link_libraries(MyExample PRIVATE MyLibExample)
```



# 增加特定的配置

## 设置构建类型
``` cmake
  set(default_build_type "Release")
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    message(STATUS "Setting build type to '${default_build_type}' as none was specified.")
    set(CMAKE_BUILD_TYPE "${default_build_type}" CACHE
        STRING "Choose the type of build." FORCE)
    # Set the possible values of build type for cmake-gui
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Release" "MinSizeRel" "RelWithDebInfo")
  endif()
```



## 设置 c++ 标准

对整个 CMake 工程进行全局设置：
``` cmake
  set(CMAKE_CXX_STANDARD 11)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)
  set(CMAKE_CXX_EXTENSIONS OFF)
```

对单独一个 target 的设置：
``` cmake
  set_target_properties(myTarget PROPERTIES
      CXX_STANDARD 11
      CXX_STANDARD_REQUIRED YES
      CXX_EXTENSIONS NO
  )
```


## 其它编译器配置

### PIC 标记
默认情况下 `-fPIC` 标记会被自动使能，如果要显示的指定的话，可以：
``` cmake
  # 全局设置
  set(CMAKE_POSITION_INDEPENDENT_CODE ON)

  # 仅对指定的 target 进行设置
  set_target_properties(lib1 PROPERTIES POSITION_INDEPENDENT_CODE ON)
```


### 链接其他的库

有些库是 cmake 本身就自带了的，比如 `${CMAKE_DL_LIBS}` 就指定了 dl 库的路径。

而有些库是需要编写对应的 Find*.cmake 文件，使用 `find_library` 来查找库：
``` cmake
  find_library(MATH_LIBRARY m)
  if(MATH_LIBRARY)
      target_link_libraries(MyTarget PUBLIC ${MATH_LIBRARY})
  endif()
```


### 过程优化 

``` cmake
  include(CheckIPOSupported)
  check_ipo_supported(RESULT result)
  # 如果编译器支持过程优化，则打开该功能
  if(result)
    set_target_properties(foo PROPERTIES INTERPROCEDURAL_OPTIMIZATION TRUE)
  endif()
```

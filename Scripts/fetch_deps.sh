#!/bin/bash
# 拉取第三方依赖：imgui、libkfd、xpf
set -e
cd "$(dirname "$0")/../Deps"

if [ ! -d imgui ]; then
  git clone --depth 1 https://github.com/ocornut/imgui.git imgui
fi
# imgui 源文件（imgui*.cpp + backends/imgui_impl_metal.mm）已由 project.yml 自动纳入 target，
# 无需手动拖文件

if [ ! -d libkfd ]; then
  git clone --depth 1 https://github.com/pure2357/libkfd.git libkfd || \
  git clone --depth 1 https://github.com/opa334/libkfd.git libkfd
fi
# libkfd 全部实现集中在 libkfd.h，libkfd.c 单文件编译即可（project.yml 已纳入）

if [ ! -d xpf ]; then
  git clone --depth 1 https://github.com/opa334/XPF.git xpf || true
fi
# xpf 提供 libxpf（漏洞分发/内核符号解析，原版 libxpf.dylib 同款）。
# 交叉编译产物 libxpf.dylib 放 App 包内，可执行程序按 @loader_path 链接。

echo "deps ready"

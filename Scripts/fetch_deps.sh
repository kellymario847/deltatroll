#!/bin/bash
# 拉取第三方依赖：imgui、libkfd、xpf
set -e
mkdir -p "$(dirname "$0")/../Deps"
cd "$(dirname "$0")/../Deps"

if [ ! -d imgui ]; then
  git clone --depth 1 https://github.com/ocornut/imgui.git imgui
fi

if [ ! -d libkfd ]; then
  git clone --depth 1 https://github.com/pure2357/libkfd.git libkfd || \
  git clone --depth 1 https://github.com/opa334/libkfd.git libkfd
fi

if [ ! -d xpf ]; then
  git clone --depth 1 https://github.com/opa334/XPF.git xpf || true
fi

echo "deps ready"

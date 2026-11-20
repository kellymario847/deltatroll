#!/bin/bash
# 拉取第三方依赖：imgui、libkfd、xpf（多镜像容错版）
set -e
mkdir -p "$(dirname "$0")/../Deps"
cd "$(dirname "$0")/../Deps"

clone() {
  local dest="$1"; shift
  if [ -d "$dest" ]; then echo ">> $dest 已存在，跳过"; return 0; fi
  for url in "$@"; do
    echo ">> try $url"
    if git clone --depth 1 "$url" "$dest" 2>&1; then return 0; fi
    rm -rf "$dest"
  done
  echo "!! $dest 所有镜像均失败"
  return 1
}

clone imgui \
  https://github.com/ocornut/imgui.git \
  https://gitclone.com/github.com/ocornut/imgui.git

clone libkfd \
  https://github.com/pure2357/libkfd.git \
  https://github.com/opa334/libkfd.git \
  https://github.com/felix-pb/kfd.git \
  https://gitclone.com/github.com/felix-pb/kfd.git

if [ -d libkfd ] && [ ! -f libkfd/libkfd.c ]; then
  printf '#include "libkfd.h"\n' > libkfd/libkfd.c
fi

clone xpf \
  https://github.com/opa334/XPF.git \
  https://gitclone.com/github.com/opa334/XPF.git || true

echo "deps ready"
ls -la

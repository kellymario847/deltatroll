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

if [ -d libkfd ]; then
  libroot=""
  for f in $(find libkfd -maxdepth 3 -name "libkfd.h"); do
    d=$(dirname "$f")
    if [ -d "$d/libkfd" ]; then libroot="$d"; break; fi
  done
  if [ -n "$libroot" ] && [ "$libroot" != "libkfd" ]; then
    cp "$libroot/libkfd.h" libkfd/libkfd.h
    rm -rf libkfd/libkfd
    cp -R "$libroot/libkfd" libkfd/libkfd
    echo ">> libkfd 布局归一自: $libroot"
  fi
  if [ ! -f libkfd/libkfd.c ]; then
    printf '#include "libkfd.h"\n' > libkfd/libkfd.c
  fi
  echo ">> libkfd 头文件清单:"
  find libkfd -maxdepth 3 -name "*.h" | head -30
  echo ">> libkfd.h 前 80 行:"
  sed -n '1,80p' libkfd/libkfd.h
fi

clone xpf \
  https://github.com/opa334/XPF.git \
  https://gitclone.com/github.com/opa334/XPF.git || true

echo "deps ready"
ls -la

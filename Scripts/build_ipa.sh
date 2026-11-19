#!/bin/bash
# 构建 + 打 TrollStore 可装 IPA（macOS 上执行；Windows 可在 WSL/macOS CI 跑）
# 产物: build/DeltaTroll.trollstore.ipa —— 设备上用 TrollStore 安装即可永久签
set -e
cd "$(dirname "$0")/.."

SCHEME="DeltaTroll"
WORK="build"

echo "[1/5] xcodegen"
xcodegen generate

echo "[2/5] xcodebuild archive (unsigned)"
rm -rf "$WORK"
xcodebuild -project DeltaTroll.xcodeproj -scheme "$SCHEME" \
  -configuration Release -derivedDataPath "$WORK/dd" \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  archive -archivePath "$WORK/$SCHEME.xcarchive"

APP="$WORK/$SCHEME.xcarchive/Products/Applications/$SCHEME.app"
BIN="$APP/$SCHEME"

echo "[3/5] ldid 伪签 + entitlements"
# 等价原版内嵌 entitlements：TrollStore 安装后 entitlement 全部生效
ldid -SDeltaTroll.entitlements "$BIN"

echo "[4/5] 打 IPA"
PAYLOAD="$WORK/Payload"
mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/"
# 附带 libxpf（若存在）
if [ -f Deps/xpf/dist/libxpf.dylib ]; then
  cp Deps/xpf/dist/libxpf.dylib "$PAYLOAD/$SCHEME.app/"
  install_name_tool -change @rpath/libxpf.dylib @loader_path/libxpf.dylib "$BIN" 2>/dev/null || true
  ldid -SDeltaTroll.entitlements "$BIN"
fi
cd "$WORK"
zip -qr "DeltaTroll.trollstore.ipa" Payload
cd ..
echo "[5/5] 完成: $WORK/DeltaTroll.trollstore.ipa"
echo "安装: 设备打开 TrollStore -> Settings -> Install IPA File"

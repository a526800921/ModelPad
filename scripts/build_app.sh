#!/bin/bash
#
# build_app.sh — ModelPad .app 构建脚本
#
# 用法:
#   ./scripts/build_app.sh          构建并测试
#   ./scripts/build_app.sh --run     构建后自动启动 App
#   ./scripts/build_app.sh --skip-tests  跳过测试
#
# 参考: TranslateBar/scripts/build_and_run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_NAME="ModelPad"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ARCH="$(uname -m)"
BUILD_TRIPLE="${ARCH}-apple-macosx"
INFO_PLIST_SRC="$PROJECT_ROOT/App/Resources/Info.plist"
ICON_SRC="$PROJECT_ROOT/App/Resources/ModelPad.icns"

SKIP_TESTS=false
DO_RUN=false

for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=true ;;
        --run)        DO_RUN=true ;;
        --debug)      BUILD_CONFIG="debug" ;;
        *)            echo "未知参数: $arg"; exit 1 ;;
    esac
done

BUILD_CONFIG="${BUILD_CONFIG:-release}"

echo "==> 项目: $PROJECT_ROOT"
echo "==> 架构: $ARCH"
echo "==> 配置: $BUILD_CONFIG"

# Step 1: 测试
if $SKIP_TESTS; then
    echo "==> 跳过测试"
else
    echo "==> 运行测试..."
    cd "$PROJECT_ROOT"
    swift test
    echo "✓ 测试通过"
fi

# Step 2: Release 构建
echo "==> SwiftPM 构建 ($BUILD_CONFIG)..."
cd "$PROJECT_ROOT"
BUILD_FLAG=""
if [ "$BUILD_CONFIG" = "release" ]; then
    BUILD_FLAG="-c release"
fi
# 使用 --product 确保最终链接产物被生成
swift build $BUILD_FLAG --product ModelPad
echo "✓ 构建完成"

# Step 3: 准备 .app 目录结构
echo "==> 生成 $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Step 4: 复制二进制
BINARY_SRC="$PROJECT_ROOT/.build/$BUILD_TRIPLE/$BUILD_CONFIG/$APP_NAME"
cp "$BINARY_SRC" "$APP_BUNDLE/Contents/MacOS/"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo "  ✓ 二进制: $BINARY_SRC → Contents/MacOS/"

# Step 5: 复制 Info.plist
cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"
echo "  ✓ Info.plist"

# Step 6: 复制 App 图标
cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/ModelPad.icns"
echo "  ✓ App 图标: ModelPad.icns"

# Step 6b: 复制 Python 脚本
SCRIPTS_SRC="$PROJECT_ROOT/App/Resources/Scripts"
if [ -d "$SCRIPTS_SRC" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Resources/Scripts"
    cp "$SCRIPTS_SRC"/*.py "$APP_BUNDLE/Contents/Resources/Scripts/"
    echo "  ✓ Python 脚本: $(ls "$SCRIPTS_SRC"/*.py 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
fi

# Step 6c: 复制 README（用于 GET / 根路径响应）
README_SRC="$PROJECT_ROOT/README.md"
if [ -f "$README_SRC" ]; then
    cp "$README_SRC" "$APP_BUNDLE/Contents/Resources/"
    echo "  ✓ README: README.md"
fi

# Step 7: 写入 PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"
echo "  ✓ PkgInfo"

# Step 8: Ad-hoc 签名
echo "==> 签名..."
codesign --force --deep --sign - "$APP_BUNDLE"
echo "  ✓ Ad-hoc 签名完成"

# Step 9: 验证
echo "==> 验证..."
echo "  Bundle 结构:"
find "$APP_BUNDLE" -type f | sed "s|$APP_BUNDLE||" | sort
echo ""
echo "  签名信息:"
codesign -dvvv "$APP_BUNDLE" 2>&1 | grep -E "Signature|TeamIdentifier|Authority" || true
echo ""
echo "  Info.plist 验证:"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"

echo ""
echo "====== 构建完成 ======"
echo "App: $APP_BUNDLE"
echo ""
echo "启动方式:"
echo "  open '$APP_BUNDLE'"
echo ""
echo "若从网络下载后被 Gatekeeper 阻止:"
echo "  xattr -cr '$APP_BUNDLE'"
echo "  open '$APP_BUNDLE'"

# Step 10: 可选启动
if $DO_RUN; then
    echo ""
    echo "==> 启动 App..."
    open "$APP_BUNDLE"
fi

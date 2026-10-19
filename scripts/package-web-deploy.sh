#!/usr/bin/env bash
# package-web-deploy.sh — 用上游发布的「预构建产物」拼装 Web 静态站点（不编译）
#
# 上游 v1.4.0-content 已提供现成的界面（web-app.zip）与转好的音频（audio-web-mp3.tar.gz），
# 因此这里直接下载 + 校验 + 拼装，跳过 next build 与 opus→mp3 转码，几分钟即可出包。
#
# 用法:
#   bash scripts/package-web-deploy.sh                # 默认 tag v1.4.0-content
#   bash scripts/package-web-deploy.sh v1.4.0-content # 指定上游资源 tag
#
# 产出:
#   dist/china-study-free-web.tar.gz
#   dist/china-study-free-web.tar.gz.part-*  （900MB 分片，便于上传 Release）
#
# 需要: curl, python3 (解压 zip 并修正 Windows 反斜杠路径), tar, split, sha256sum

set -euo pipefail

REPO="wuwangzhang1216/ChinaTextbookStudyFree"
TAG="${1:-v1.4.0-content}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$DIST_DIR/.work"
SITE_DIR="$WORK_DIR/site"
BASE_URL="https://github.com/$REPO/releases/download/$TAG"

# 拼装成静态站点所需的全部资源（extract_to 见上游 manifest.json）
ZIP_TO_SITE=(web-app.zip)                 # → 站点根目录
ZIP_ASSETS=(data.zip story-images.zip textbook-pages.zip)  # → 见下方 target 映射
TAR_TO_SITE=(audio.tar.gz audio-web-mp3.tar.gz)            # 包内含 audio/ 顶层目录 → 站点根目录

echo "=== ChinaStudyFree Web 预构建拼装 ==="
echo "上游: $REPO @ $TAG"
echo "站点: $SITE_DIR"

rm -rf "$WORK_DIR"
mkdir -p "$SITE_DIR" "$DIST_DIR"

# ---- 下载 ----
echo ""
echo "--- 1/3 下载资源 ---"
for name in "${ZIP_TO_SITE[@]}" "${ZIP_ASSETS[@]}" "${TAR_TO_SITE[@]}"; do
  echo "  下载 $name ..."
  curl -fL --retry 3 --progress-bar -o "$WORK_DIR/$name" "$BASE_URL/$name"
done
curl -fL --retry 3 -fsS -o "$WORK_DIR/SHA256SUMS" "$BASE_URL/SHA256SUMS"
echo "  校验 SHA256SUMS ..."
(cd "$WORK_DIR" && sha256sum -c SHA256SUMS --ignore-missing)

# ---- 解压 ----
# zip 内的路径可能是 Windows 反斜杠，按上游 install-release.py 的方式归一化后再落盘。
extract_zip() {
  local zip_path="$1" dest="$2"
  mkdir -p "$dest"
  python3 - "$zip_path" "$dest" <<'PY'
import os, sys, zipfile
from pathlib import PurePosixPath
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as z:
    for name in z.namelist():
        parts = PurePosixPath(name.replace('\\', '/'))
        if parts.is_absolute() or '..' in parts.parts:
            raise ValueError(f'Unsafe archive path: {name}')
        target = os.path.join(dst, *parts.parts)
        if name.endswith('/'):
            os.makedirs(target, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with z.open(name) as sf, open(target, 'wb') as df:
            while True:
                chunk = sf.read(1 << 20)
                if not chunk:
                    break
                df.write(chunk)
PY
}

echo ""
echo "--- 2/3 解压并拼装 ---"
for name in "${ZIP_TO_SITE[@]}"; do
  echo "  $name → 站点根目录"
  extract_zip "$WORK_DIR/$name" "$SITE_DIR"
  rm -f "$WORK_DIR/$name"
done

declare -A ZIP_TARGET=(
  [data.zip]="$SITE_DIR/data"
  [story-images.zip]="$SITE_DIR/story-images"
  [textbook-pages.zip]="$SITE_DIR/textbook-pages"
)
for name in "${ZIP_ASSETS[@]}"; do
  dest="${ZIP_TARGET[$name]}"
  echo "  $name → $dest"
  extract_zip "$WORK_DIR/$name" "$dest"
  rm -f "$WORK_DIR/$name"
done

for name in "${TAR_TO_SITE[@]}"; do
  echo "  $name → 站点根目录"
  tar -xzf "$WORK_DIR/$name" -C "$SITE_DIR"
  rm -f "$WORK_DIR/$name"
done

[[ -f "$SITE_DIR/index.html" ]] || { echo "拼装失败: 站点根目录缺少 index.html"; exit 1; }
[[ -f "$SITE_DIR/data/index.json" ]] || { echo "拼装失败: 缺少 data/index.json"; exit 1; }

# ---- 打包 ----
echo ""
echo "--- 3/3 打 tar.gz 并分片 ---"
TAR_PATH="$DIST_DIR/china-study-free-web.tar.gz"
rm -f "$TAR_PATH" "${TAR_PATH}".part-*
tar -czf "$TAR_PATH" -C "$SITE_DIR" .
ls -lh "$TAR_PATH"

# 900MB 分片，低于 GitHub Release 2GB 限制且更稳
split -b 900M -d -a 2 "$TAR_PATH" "${TAR_PATH}.part-"
echo "分片:"
ls -lh "${TAR_PATH}".part-*

# 释放拼装目录（只保留 dist 下的产物）
rm -rf "$WORK_DIR"

echo ""
echo "=== 完成 ==="
echo "产物: $TAR_PATH"

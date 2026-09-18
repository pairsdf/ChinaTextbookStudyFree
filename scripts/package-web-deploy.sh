#!/usr/bin/env bash
# package-web-deploy.sh — 构建并打包 Web 静态站点（Linux / GitHub Actions）
#
# 用法:
#   bash scripts/package-web-deploy.sh
#
# 产出:
#   dist/china-study-free-web.tar.gz
#   dist/china-study-free-web.tar.gz.part-*  （900MB 分片，便于上传 Release）

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$ROOT_DIR/apps/web"
PUBLIC_DIR="$WEB_DIR/public"
OUT_DIR="$WEB_DIR/out"
DIST_DIR="$ROOT_DIR/dist"
HEAVY_DIRS=(audio story-images textbook-pages)
SKIP_SUFFIX=".__build_skip__"

hide_heavy() {
  for name in "${HEAVY_DIRS[@]}"; do
    if [[ -d "$PUBLIC_DIR/$name" && ! -d "$PUBLIC_DIR/${name}${SKIP_SUFFIX}" ]]; then
      mv "$PUBLIC_DIR/$name" "$PUBLIC_DIR/${name}${SKIP_SUFFIX}"
      echo "  暂移出构建: $name"
    fi
  done
}

restore_heavy() {
  for name in "${HEAVY_DIRS[@]}"; do
    if [[ -d "$PUBLIC_DIR/${name}${SKIP_SUFFIX}" && ! -d "$PUBLIC_DIR/$name" ]]; then
      mv "$PUBLIC_DIR/${name}${SKIP_SUFFIX}" "$PUBLIC_DIR/$name"
      echo "  已恢复: $name"
    fi
  done
}

copy_heavy_to_out() {
  for name in "${HEAVY_DIRS[@]}"; do
    src="$PUBLIC_DIR/$name"
    [[ -d "$src" ]] || src="$PUBLIC_DIR/${name}${SKIP_SUFFIX}"
    if [[ ! -d "$src" ]]; then
      echo "  跳过缺失资源: $name"
      continue
    fi
    echo "  复制 $name → out/ ..."
    rm -rf "$OUT_DIR/$name"
    mkdir -p "$OUT_DIR/$name"
    cp -a "$src/." "$OUT_DIR/$name/"
  done
}

split_archive() {
  local src="$1"
  local prefix="${src}.part-"
  rm -f "${prefix}"*
  # 900MB 分片，低于 GitHub Release 2GB 限制且更稳
  split -b 900M -d -a 2 "$src" "$prefix"
  echo "分片:"
  ls -lh "${prefix}"*
}

echo "=== ChinaStudyFree Web 部署打包 ==="
echo "Web: $WEB_DIR"

cd "$WEB_DIR"
echo ""
echo "--- 1/4 生成 data ---"
npm run build:data

echo ""
echo "--- 2/4 暂移大型静态资源后执行 next build ---"
hide_heavy
trap restore_heavy EXIT
rm -rf "$OUT_DIR" "$WEB_DIR/.next"
export NODE_OPTIONS="--max-old-space-size=8192"
npx next build
restore_heavy
trap - EXIT

[[ -d "$OUT_DIR" ]] || { echo "构建未产出 out/"; exit 1; }

echo ""
echo "--- 3/4 把音频/配图/课本页拷入 out/ ---"
copy_heavy_to_out

echo ""
echo "--- 4/4 打 tar.gz 并分片 ---"
mkdir -p "$DIST_DIR"
TAR_PATH="$DIST_DIR/china-study-free-web.tar.gz"
rm -f "$TAR_PATH"
tar -czf "$TAR_PATH" -C "$OUT_DIR" .
ls -lh "$TAR_PATH"
split_archive "$TAR_PATH"

echo ""
echo "=== 完成 ==="
echo "产物: $TAR_PATH"

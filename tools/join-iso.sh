#!/usr/bin/env bash
# 合并 GitHub Actions 产出的 ISO 分卷（Linux / macOS）
# 用法: ./join-iso.sh tinyos-1.0.0-whuang-amd64.iso [输出文件名]
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "用法: $0 <分卷前缀> [输出文件名]"
    echo "例如: $0 tinyos-1.0.0-whuang-amd64.iso"
    exit 1
fi

PREFIX="$1"
OUT="${2:-$PREFIX}"

shopt -s nullglob
PARTS=("${PREFIX}.part-"*)
if [ ${#PARTS[@]} -eq 0 ]; then
    echo "未找到分卷文件: ${PREFIX}.part-*" >&2
    exit 1
fi

echo "合并 ${#PARTS[@]} 个分卷 -> ${OUT}"
cat "${PARTS[@]}" > "$OUT"

echo "校验 SHA256:"
sha256sum "$OUT"

if [ -f "${PREFIX}.sha256" ]; then
    echo "与官方校验和对比:"
    grep -F "$(sha256sum "$OUT" | cut -d' ' -f1)" "${PREFIX}.sha256" \
        && echo "  ✓ 校验通过" \
        || { echo "  ✗ 校验不匹配" >&2; exit 1; }
fi

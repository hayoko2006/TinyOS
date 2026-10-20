#!/usr/bin/env bash
# ============================================================================
# TinyOS 1.0 - 一键构建脚本
# 基于 Debian 13 (trixie) 稳定版，使用 live-build 产出 iso-hybrid 可启动镜像
# 用法: 以 root 在 Debian 13 环境中运行  sudo ./build.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${TINYOS_VERSION:-1.0.0}"
# EDITION 为版本口味标识（品牌命名），与 DIST（Debian 基座代号）互相独立
EDITION="${TINYOS_EDITION:-whuang}"
ARCH="${TINYOS_ARCH:-amd64}"
DIST="${TINYOS_DIST:-trixie}"

# 软件源：构建期用 HTTP（debootstrap 无需 TLS），目标系统内用 HTTPS
MIRROR_CHROOT="${TINYOS_MIRROR_CHROOT:-http://mirrors.ustc.edu.cn/debian/}"
MIRROR_BINARY="${TINYOS_MIRROR_BINARY:-https://mirrors.ustc.edu.cn/debian/}"
MIRROR_SECURITY="${TINYOS_MIRROR_SECURITY:-https://mirrors.ustc.edu.cn/debian-security/}"

BUILD_DIR="${TINYOS_BUILD_DIR:-/root/tinyos-build}"
MIN_FREE_MB="${TINYOS_MIN_FREE_MB:-25000}"
# 默认输出到 WSL 挂载的 Windows 桌面 tiny/out（存在则自动使用）
if [ -d "/mnt/c/Users/Administrator/Desktop/tiny" ]; then
    OUT_DIR="${TINYOS_OUT_DIR:-/mnt/c/Users/Administrator/Desktop/tiny/out}"
else
    OUT_DIR="${TINYOS_OUT_DIR:-${SCRIPT_DIR}/out}"
fi

log()  { printf '\n\033[1;36m[TinyOS]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[TinyOS] 错误:\033[0m %s\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
# 从脚本一开始就记录完整日志（含依赖安装、lb config 等早期阶段），
# 并在任何一步失败时把日志尾部归档到仓库 docs/evidence/ —— 便于在无凭据
# 环境下直接读到失败原因（此前只在 lb build 失败时才留日志，早期失败会丢证据）。
EVIDENCE_DIR="${SCRIPT_DIR}/../docs/evidence"
mkdir -p "${OUT_DIR}" "${EVIDENCE_DIR}"
exec > >(tee "${OUT_DIR}/build.log") 2>&1

save_failure_log() {
    local code=$?
    if [ "${code}" -ne 0 ]; then
        sleep 1  # 等待 tee 落盘
        tail -n 500 "${OUT_DIR}/build.log" > "${EVIDENCE_DIR}/build-tail.log" 2>/dev/null || true
    fi
}
trap save_failure_log EXIT

# ----------------------------------------------------------------------------
log "0/7 环境检查"
[ "$(id -u)" -eq 0 ] || fail "请以 root 运行本脚本（sudo ./build.sh）"
grep -q 'trixie\|bookworm' /etc/os-release 2>/dev/null || \
    fail "请在 Debian 12/13 环境中运行（当前: $(grep PRETTY_NAME /etc/os-release)）"
[ "$(df -m / | awk 'NR==2{print $4}')" -gt "${MIN_FREE_MB}" ] || \
    fail "根分区可用空间不足 ${MIN_FREE_MB}MB（建议 40GB+，可用 TINYOS_MIN_FREE_MB 调整阈值）"

# ----------------------------------------------------------------------------
log "1/7 安装构建依赖"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    live-build debootstrap xorriso squashfs-tools dosfstools e2fsprogs mtools \
    grub-pc-bin grub-efi-amd64-bin shim-signed python3 python3-pil rsync ca-certificates \
    xz-utils bzip2 file cpio >/dev/null

# ----------------------------------------------------------------------------
log "2/7 同步构建配置 -> ${BUILD_DIR}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cp -a "${SCRIPT_DIR}/config" "${BUILD_DIR}/config"

# 修复可执行权限（Windows/NTFS 上不保留 exec 位）
find "${BUILD_DIR}/config/hooks" -type f \( -name '*.hook.chroot' -o -name '*.hook.binary' \) -exec chmod +x {} +
if [ -d "${BUILD_DIR}/config/includes.chroot/usr/local/bin" ]; then
    find "${BUILD_DIR}/config/includes.chroot/usr/local/bin" -type f -exec chmod 755 {} +
    find "${BUILD_DIR}/config/includes.chroot/usr/local/sbin" -type f -exec chmod 755 {} + 2>/dev/null || true
fi
find "${BUILD_DIR}/config/includes.chroot/etc/skel" -type f -exec chmod 644 {} + 2>/dev/null || true
if [ -f "${BUILD_DIR}/config/includes.chroot/etc/sudoers.d/tinyos-live" ]; then
    chmod 440 "${BUILD_DIR}/config/includes.chroot/etc/sudoers.d/tinyos-live"
fi
# 构建工具本身在目标内需要可执行
chmod +x "${BUILD_DIR}/config/includes.chroot/usr/share/plymouth/themes/tinyos/"*.script 2>/dev/null || true

# 将口味标识注入目标系统，供品牌化钩子读取（os-release VARIANT 等）
mkdir -p "${BUILD_DIR}/config/includes.chroot/etc"
printf '%s\n' "${EDITION}" > "${BUILD_DIR}/config/includes.chroot/etc/tinyos-edition"

# 生成品牌视觉素材（壁纸 / 开机动画标识），使仓库无需提交二进制文件
ASSETS=(
    "includes.chroot/usr/share/wallpapers/TinyOS-Dark/contents/images/1920x1080.png"
    "includes.chroot/usr/share/wallpapers/TinyOS-Light/contents/images/1920x1080.png"
    "includes.chroot/usr/share/wallpapers/TinyOS-Aurora/contents/images/1920x1080.png"
    "includes.chroot/usr/share/plymouth/themes/tinyos/logo.png"
    "includes.chroot/usr/share/plymouth/themes/tinyos/bar_fg.png"
    "includes.chroot/usr/share/plymouth/themes/tinyos/bar_bg.png"
)
need_assets=0
for a in "${ASSETS[@]}"; do
    [ -f "${BUILD_DIR}/config/${a}" ] || need_assets=1
done
if [ "${need_assets}" = "1" ]; then
    log "    生成品牌视觉素材（tools/gen-assets.py）"
    python3 "${SCRIPT_DIR}/tools/gen-assets.py" --config-dir "${BUILD_DIR}/config"
    chmod 644 "${BUILD_DIR}/config/includes.chroot/usr/share/plymouth/themes/tinyos/"*.png 2>/dev/null || true
fi

# GRUB 菜单背景取自深色壁纸。壁纸位于 includes.chroot（进 squashfs），
# 而 GRUB 主题在 includes.binary（ISO 文件系统层），故此处复制一份。
GRUB_THEME_DIR="${BUILD_DIR}/config/includes.binary/boot/grub/themes/tinyos"
if [ -d "${GRUB_THEME_DIR}" ]; then
    DARK_WALLPAPER="${BUILD_DIR}/config/includes.chroot/usr/share/wallpapers/TinyOS-Dark/contents/images/1920x1080.png"
    if [ -f "${DARK_WALLPAPER}" ]; then
        cp -f "${DARK_WALLPAPER}" "${GRUB_THEME_DIR}/background.png"
        chmod 644 "${GRUB_THEME_DIR}/background.png"
        log "    已生成 GRUB 主题背景"
    fi
fi

# ----------------------------------------------------------------------------
log "3/7 lb config（发行版: ${DIST} ${ARCH}，口味: ${EDITION}，构建源: ${MIRROR_CHROOT}）"
cd "${BUILD_DIR}"
lb clean >/dev/null 2>&1 || true
lb config noauto \
    --distribution "${DIST}" \
    --architecture "${ARCH}" \
    --archive-areas "main contrib non-free non-free-firmware" \
    --binary-image iso-hybrid \
    --apt-indices false \
    --apt-recommends true \
    --backports true \
    --security true \
    --updates true \
    --linux-flavours "${ARCH}" \
    --linux-packages "linux-image" \
    --memtest none \
    --bootappend-live "boot=live components quiet splash locales=zh_CN.UTF-8 keyboard-layouts=us timezone=Asia/Shanghai" \
    --bootappend-live-failsafe "boot=live components memtest noapic noapm nodma nomce nolapic nomodeset" \
    --iso-volume "TinyOS_${EDITION}_${VERSION}_${ARCH}" \
    --iso-application "TinyOS ${VERSION} (${EDITION} edition)" \
    --iso-publisher "TinyOS Project; https://tiny.hayoko.cn; hayoko@hayoko.cn" \
    --mirror-bootstrap "${MIRROR_CHROOT}" \
    --parent-mirror-bootstrap "${MIRROR_CHROOT}" \
    --mirror-binary "${MIRROR_BINARY}" \
    --parent-mirror-binary "${MIRROR_BINARY}" \
    --mirror-binary-security "${MIRROR_SECURITY}" \
    --parent-mirror-binary-security "${MIRROR_SECURITY}" \
    --checksums sha256 \
    --compression xz \
    1>&2

# ----------------------------------------------------------------------------
log "4/7 可选组件"
# 磁盘安装器（Calamares）默认关闭，设置 TINYOS_INSTALLER=1 启用
if [ "${TINYOS_INSTALLER:-0}" = "1" ] && \
   [ -f "${BUILD_DIR}/config/package-lists/40-installer.list.chroot.disabled" ]; then
    if apt-cache show calamares >/dev/null 2>&1; then
        mv "${BUILD_DIR}/config/package-lists/40-installer.list.chroot.disabled" \
           "${BUILD_DIR}/config/package-lists/40-installer.list.chroot"
        log "  已启用 Calamares 磁盘安装器"
    else
        log "  当前仓库无 calamares，跳过安装器"
    fi
fi

# ----------------------------------------------------------------------------
log "5/7 lb build（首次构建需下载 2-4GB 软件包，Waydroid 安卓镜像另需下载约 800MB）"
BUILD_LOG="${BUILD_DIR}/build-$(date +%Y%m%d-%H%M%S).log"
lb build 2>&1 | tee "${BUILD_LOG}"

# ----------------------------------------------------------------------------
log "6/7 产出镜像"
ISO="$(ls -1t ./*.iso 2>/dev/null | head -n1)" || true
[ -n "${ISO}" ] && [ -f "${ISO}" ] || fail "未找到生成的 ISO，请检查上方构建日志"

FINAL_NAME="tinyos-${VERSION}-${EDITION}-${ARCH}.iso"
mkdir -p "${OUT_DIR}"
cp -f "${ISO}" "${OUT_DIR}/${FINAL_NAME}"
( cd "${OUT_DIR}" && sha256sum "${FINAL_NAME}" > "${FINAL_NAME}.sha256" )
# 注：完整构建日志已由脚本开头的 tee 持续写入 ${OUT_DIR}/build.log

log "7/7 完成"
cat <<EOF
============================================================
 TinyOS ${VERSION} (${EDITION}) 构建成功
 ISO    : ${OUT_DIR}/${FINAL_NAME}
 大小   : $(du -h "${OUT_DIR}/${FINAL_NAME}" | cut -f1)
 SHA256 : ${OUT_DIR}/${FINAL_NAME}.sha256
============================================================
 写入 U 盘（Linux）: dd if=${FINAL_NAME}.iso of=/dev/sdX bs=4M status=progress
 写入 U 盘（Windows）: 使用 Rufus，分区类型选 GPT（UEFI）
 直接测试（QEMU）  : qemu-system-x86_64 -m 4096 -enable-kvm \\
                       -device virtio-vga ${FINAL_NAME}.iso
============================================================
EOF

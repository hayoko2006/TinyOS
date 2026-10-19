# TinyOS 构建流程文档

本文档描述 TinyOS 1.0（基于 Debian 13 "Trixie"）的完整构建流程、定制点与排错方法。

---

## 1. 概述

TinyOS 使用 Debian 官方构建工具链 **live-build + debootstrap** 生成 `iso-hybrid` 镜像：

- **iso-hybrid**：同一镜像既可刻录光盘/U 盘启动，也可直接作为磁盘镜像，同时支持 **UEFI** 与 **Legacy BIOS** 两种固件。
- **构建过程**：bootstrap（拉取 Debian 基础系统）→ chroot（安装与定制软件）→ binary（压缩成 squashfs、封装 ISO）。
- **squashfs + overlay**：系统以只读压缩镜像 + 内存写层运行；U 盘使用时可添加 `persistence` 内核参数启用持久化保存。

## 2. 构建环境要求

| 项目 | 要求 |
|------|------|
| 宿主系统 | Debian 12/13，或任意发行版 + Docker 容器（镜像 `debian:trixie`） |
| 架构 | amd64 |
| 权限 | root |
| 磁盘 | 根分区可用 ≥ 25 GB（推荐 40 GB） |
| 内存 | ≥ 4 GB |
| 网络 | 可访问 `mirrors.ustc.edu.cn`（构建期下载 2–4 GB 软件包 + Waydroid 安卓镜像约 800 MB） |

### Windows 环境（WSL2）

```powershell
# 1) 管理员 PowerShell：启用 WSL2（需重启一次）
wsl --install --no-distribution

# 2) 重启后安装 Debian 发行版
wsl --install --distribution Debian

# 3) 进入 Debian，更新索引
wsl -d Debian
sudo apt update
```

> WSL2 会消耗较多内存，建议在 `C:\Users\<用户>\.wslconfig` 中限制：
> ```ini
> [wsl2]
> memory=8GB
> processors=6
> swap=8GB
> ```

### 备选：容器构建

```bash
docker run --privileged --rm -it -v /path/to/tiny:/work debian:trixie bash
cd /work/tynos && ./build.sh
```

> 必须加 `--privileged`，live-build 需要挂载与 chroot 能力。

### 备选：GitHub Actions 云端构建（无需本地 Linux 环境）

仓库内置 [`.github/workflows/build-iso.yml`](../.github/workflows/build-iso.yml)，可在 GitHub 托管的 Ubuntu 跑者上完成全部构建与测试：

```bash
# 方式一：网页手动触发
# 仓库 → Actions → 构建 TinyOS ISO → Run workflow（可填 version / edition）

# 方式二：推送自动触发（改动 tynos/ 下任意文件即触发）
git push origin main
```

workflow 步骤：

1. **释放磁盘空间**：删除跑者预装的 dotnet / Android SDK / GHC 等，腾出 40GB+（默认仅约 14GB 可用）。
2. **容器内构建**：`docker run --privileged debian:13 ./build.sh`。
3. **产物校验**：`sha256sum -c`、`file`、`xxd` 检查 ISO 头。
4. **离线内容断言**：挂载 ISO → `unsquashfs -l` 列出 squashfs 文件树 → 逐项断言五类需求的关键文件（主题包、兼容层工具、安卓镜像、镜像优选工具、品牌标识）是否齐备。
5. **QEMU 启动冒烟测试**：跑者提供 `/dev/kvm` 时启用硬件加速，通过 QEMU monitor `screendump` 在 45/120/210/360 秒四个时间点抓取画面（GRUB → 内核 → 登录 → 桌面），并保存串口日志与 `info status`。
6. **归档证据**：截图与日志提交到 `docs/evidence/`，便于复核；同时作为 Artifact 上传。
7. **上传产物**：`tinyos-iso`（完整 ISO + 校验和 + build.log）、`tinyos-iso-parts`（>2GB 分卷）、`tinyos-evidence`。

> 分卷合并：`tools/join-iso.sh`（Linux）/ `tools/join-iso.ps1`（Windows），合并后会自动比对 SHA256。

可调输入：手动触发时可指定 `version`（默认 `1.0.0`）与 `edition`（默认 `whuang`），对应环境变量 `TINYOS_VERSION` / `TINYOS_EDITION`。

## 3. 一键构建

```bash
cd /path/to/tiny/tynos
sudo ./build.sh
```

### 可配置环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `TINYOS_VERSION` | `1.0.0` | 版本号（写入 ISO 名称与 os-release） |
| `TINYOS_EDITION` | `whuang` | 版本口味/品牌标识，与 `TINYOS_DIST` 解耦；写入 ISO 卷标、文件名与 os-release 的 `VARIANT`/`VARIANT_ID`，并反映在 `PRETTY_NAME` 中 |
| `TINYOS_DIST` | `trixie` | Debian 发行版代号（构建基座，必须是真实存在的 Debian 代号） |
| `TINYOS_ARCH` | `amd64` | 目标架构 |
| `TINYOS_MIN_FREE_MB` | `25000` | 构建前根分区最低可用空间（MB），不足即中止；CI 环境因磁盘紧张设为 `18000` |
| `TINYOS_MIRROR_CHROOT` | `http://mirrors.ustc.edu.cn/debian/` | 构建期软件源（HTTP，免 TLS 依赖） |
| `TINYOS_MIRROR_BINARY` | `https://mirrors.ustc.edu.cn/debian/` | 目标系统内软件源（HTTPS） |
| `TINYOS_OUT_DIR` | `../out` | 镜像输出目录 |
| `TINYOS_INSTALLER` | `0` | 设为 `1` 时若仓库存在 Calamares 则打包磁盘安装器 |

示例：

```bash
sudo TINYOS_VERSION=1.1.0 TINYOS_MIRROR_BINARY=https://mirrors.tuna.tsinghua.edu.cn/debian/ ./build.sh
```

### 构建耗时参考

| 阶段 | 说明 |
|------|------|
| 首次拉取基础系统 | 依赖网络带宽，通常数分钟 |
| chroot 安装软件 | 主要耗时阶段（KDE + Wine + Waydroid） |
| Waydroid 镜像预下载 | 约 800 MB |
| squashfs 压缩 | 视 CPU 而定（xz 压缩较重） |
| **总计** | 视磁盘/网络/CPU 而定，首次构建明显慢于增量重建 |

## 4. 定制点详解

### 4.1 系统基座与深度裁剪（需求 1）

- 基底：`config/package-lists/00-tinyos-base.list.chroot`
- 桌面：`config/package-lists/10-tinyos-desktop.list.chroot`
- 裁剪钩子：`config/hooks/live/0700-trim.hook.chroot`

裁剪措施：

1. `--apt-indices false`：镜像内不留 APT 索引（首次开机自动 `apt update` 重建）。
2. `/etc/dpkg/dpkg.cfg.d/01-tinyos-trim`：后续安装的软件同样不再写入文档/手册/信息页。
3. 清空 `/usr/share/doc`（保留 `copyright` 以满足许可）与 `/usr/share/man`、`/usr/share/info`、`/usr/share/groff` 的内容（目录本身保留，否则 binary 阶段 apt 事务中的 `install-info` 等维护脚本会失败）。
4. 语言包仅保留 `en*` 与 `zh*`。
5. `apt-get autoremove --purge` + 清理 `/var/lib/apt/lists`、`/var/cache/apt`、日志。

> 如需进一步压缩体积，可在 `0700-trim.hook.chroot` 追加删除 `libreoffice*`、多余固件或 `okular/gwenview` 等应用。

### 4.2 桌面美化套件（需求 2）

| 组成 | 位置 | 说明 |
|------|------|------|
| 3 套 Global Theme | `usr/share/plasma/look-and-feel/com.tinyos.{dark,light,aurora}` | 声明配色、图标、壁纸、光标默认值 |
| 3 套配色方案 | `usr/share/color-schemes/TinyOS{Dark,Light,Aurora}.colors` | 完整 KDE 配色（含 Selection/Tooltip/Header 等分组） |
| 3 套壁纸包 | `usr/share/wallpapers/TinyOS-{Dark,Light,Aurora}` | Plasma 图片壁纸包（1920×1080） |
| 品牌素材生成器 | `tynos/tools/gen-assets.py` | 壁纸与 Plymouth 标识在构建时由该脚本生成（Pillow 实现、随机种子固定），因此仓库不提交二进制素材；如需替换为自制壁纸，直接覆盖对应 PNG 即可（已存在则不会重新生成） |
| 图标主题 | Debian 包 `papirus-icon-theme` | Dark/Light 两种变体随方案切换 |
| 窗口装饰/特效 | KWin（Breeze 装饰 + 模糊/背景对比等默认特效） | 配色方案自动重着色 |
| 登录界面 | `usr/share/sddm/themes/tinyos`（构建钩子基于 breeze 重新品牌化） | 背景随方案同步 |
| 开机动画 | `usr/share/plymouth/themes/tinyos` | 深空渐变 + 标识淡入 + 进度条 |
| 启动菜单 | `includes.binary/boot/grub/themes/tinyos` + `0010-grub-branding.hook.binary` | GRUB 主题与菜单品牌化 |

**一键切换**：`tinyos-theme {dark|light|aurora|list|status}`（`/usr/local/bin/tinyos-theme`）

- 桌面菜单中提供三个入口：`TinyOS 深色方案 / 浅色方案 / 极光方案`。
- 切换动作：`plasma-apply-lookandfeel` + `plasma-apply-colorscheme` + `plasma-apply-icontheme` + `plasma-apply-wallpaperimage`，并同步 SDDM 登录背景（下次登录生效）。

### 4.3 兼容层集成（需求 3）

**Windows 程序兼容层** — `config/hooks/live/0200-wine.hook.chroot`

- `dpkg --add-architecture i386` 支持 32 位 Windows 程序。
- 安装 `wine wine64 wine32 winbind winetricks fonts-wine`。
- 性能优化组件：`gamemode`（CPU/GPU 调度优先级自动切换）、`mangohud`（帧率叠加，可选）。
- DXVK：仓库存在 `dxvk` 时自动安装；否则 `tinyos-wine dxvk` 提供手动启用指引。
- 渲染栈：`mesa-vulkan-drivers` + `libvulkan1`（AMD RADV / Intel ANV 硬件加速）。

助手工具 `tinyos-wine`：

```bash
tinyos-wine setup          # 初始化 Wine 前缀
tinyos-wine run app.exe    # 运行 Windows 程序
tinyos-wine game game.exe  # 游戏模式（Gamemode）
tinyos-wine dxvk           # 启用 DXVK（Direct3D → Vulkan）
tinyos-wine info           # 查看兼容层状态
```

**安卓应用兼容层** — `config/hooks/live/0300-waydroid.hook.chroot`

- 来源：Debian **trixie-backports** 官方仓库（`waydroid`，无需第三方源）。
- 构建期按 Waydroid OTA 清单直连下载并校验（sha256）VANILLA 安卓镜像（绕过 chroot 内缺失的 binder 检查），实现开箱即用。
- 启用 `waydroid-container` 服务；默认开启多窗口模式，安卓应用以独立窗口显示在 KDE 桌面。
- 依赖宿主机内核 `binderfs`（Debian 6.12 内核已启用）。

助手工具 `tinyos-waydroid`：`start / stop / status / ui / install <apk> / uninstall <pkg> / list / shell / init`。

> 硬件加速说明：Waydroid 通过宿主 GPU 渲染，需宿主提供正常工作的 Vulkan/OpenGL 驱动。在虚拟机中测试需宿主开启 3D 加速（virtio-gpu/virgl）。

### 4.4 软件源配置（需求 4）

- 默认源：**中科大 USTC**（`0500-branding.hook.chroot` 写入 `/etc/apt/sources.list`）。
- 备用源以注释形式内置：国内 **清华 TUNA / 阿里云 / 华为云 / 腾讯云 / 网易 / 上交**，国际 **Debian 官方 CDN / Kernel.org（北美）/ Hetzner（欧洲）/ JAIST（日本）/ AARNet（澳洲）**，取消注释即可切换。
- 国际节点的 security 更新统一走官方 `security.debian.org`；海外用户可直接选用官方 CDN。
- Backports 源用于 Waydroid。
- 自动优选工具 `tinyos-mirror`（Python3）：
  - 并发探测各镜像 `dists/trixie/Release` 的响应延迟；
  - 按“国内 / 国际”分组输出，并采用全量节点中延迟最低者；
  - 路径失效或未同步的节点会被判定为不可用，不会写入源列表；
  - 自动备份原配置为 `/etc/apt/sources.list.tinyos-bak`；
  - 支持 `--auto` / `--list` / `--set <name>` / `--quiet`。
- 首次开机由 `tinyos-firstboot.service` 自动执行 `tinyos-mirror --auto` 并刷新索引；海外环境会自动落到官方 CDN 或就近的大洲节点。

```bash
sudo tinyos-mirror              # 交互式：列出延迟并确认切换
sudo tinyos-mirror --auto       # 非交互自动优选
sudo tinyos-mirror --list       # 仅测速
sudo tinyos-mirror --set tuna   # 指定清华源
sudo tinyos-mirror --set debian # 指定 Debian 官方 CDN（海外）
```

## 5. 交付物与验证

构建成功后输出：

```
out/tinyos-1.0.0-whuang-amd64.iso
out/tinyos-1.0.0-whuang-amd64.iso.sha256
```

验证：

```bash
sha256sum -c out/tinyos-1.0.0-whuang-amd64.iso.sha256
file out/tinyos-1.0.0-whuang-amd64.iso          # 应识别为 ISO 9660 / hybrid
lsblk -f out/tinyos-1.0.0-whuang-amd64.iso      # 查看分区表（EFI 分区 + ISO9660）
```

虚拟机快速启动验证：

```bash
# 需要 4GB+ 内存；UEFI 可加 -bios /usr/share/OVMF/OVMF_CODE.fd
qemu-system-x86_64 -m 4096 -smp 4 -enable-kvm \
  -device virtio-vga-gl -display sdl \
  out/tinyos-1.0.0-whuang-amd64.iso
```

## 6. 常见问题排查

| 现象 | 原因与处理 |
|------|-----------|
| `debootstrap` 校验失败/超时 | 更换 `TINYOS_MIRROR_CHROOT`（如换成 `https://` 或 TUNA）；检查网络与磁盘空间 |
| Waydroid 安装失败 | 确认 `--backports true` 生效、`trixie-backports` 可达；构建日志搜索 `waydroid` |
| Waydroid 镜像下载失败 | 构建钩子会重试 3 次；也可在网络良好时在装好的系统里运行 `sudo tinyos-waydroid init` |
| Plymouth 主题报错 | 不影响启动；检查 `/usr/share/plymouth/themes/tinyos/` 下 `logo.png`、`bar_fg.png`、`bar_bg.png` 是否存在 |
| 图标主题未生效 | 确认已装 `papirus-icon-theme`；执行 `gtk-update-icon-cache -f /usr/share/icons/Papirus` |
| 中文显示为方块 | 确认 `fonts-noto-cjk` 已安装；执行 `fc-cache -f` |
| 磁盘不足 | 构建目录默认 `/root/tinyos-build`，确保该分区 ≥ 25 GB；或设置 `TINYOS_BUILD_DIR` |
| U 盘启动黑屏 | 菜单选 “failsafe” 项（已内置 `nomodeset`）排查显卡驱动问题 |
| 增量重建 | `lb clean && sudo ./build.sh`；如需彻底清理可 `lb clean --purge` |

## 7. 目录维护建议

- 新增软件：编辑 `config/package-lists/*.list.chroot`（每行一个包名）。
- 新增文件注入：放入 `config/includes.chroot/`（路径即目标系统绝对路径）。
- 新增构建期逻辑：放入 `config/hooks/live/NNNN-name.hook.chroot`（`NNNN` 决定执行顺序，脚本以 `sh -e` 执行）。
- 修改主题：编辑 `includes.chroot/usr/share/{color-schemes,plasma,wallpapers}` 下对应文件后重建。

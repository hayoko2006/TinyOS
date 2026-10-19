# TinyOS 1.0

基于 **Debian 13 "Trixie"（当前最新稳定版）** 深度定制构建的精简桌面操作系统。

| 项目 | 内容 |
|------|------|
| 系统基座 | Debian 13.7 trixie stable (amd64) |
| 桌面环境 | KDE Plasma 6（Wayland 会话） |
| 显示管理器 | SDDM（品牌化登录主题 + 自动登录） |
| 开机动画 | Plymouth（深空渐变 + 品牌标识淡入 + 极光青进度条） |
| 启动引导 | GRUB（BIOS + UEFI 双启动，TinyOS 品牌主题） |
| Windows 兼容 | Wine + winetricks + Gamemode（可选 DXVK → Vulkan 硬件加速） |
| 安卓兼容 | Waydroid（trixie-backports 官方包，预置 VANILLA 安卓镜像） |
| 软件源 | 中科大 USTC 默认；内置清华/阿里等国内源 + 官方 CDN、北美/欧洲/日本/澳洲节点，延迟自动优选（国内外均可用） |
| 输入法 | fcitx5 + 中文词库（预配置环境变量与自启动） |
| 镜像格式 | iso-hybrid（可 dd 写 U 盘，UEFI + Legacy BIOS 双启动） |

> 官网：<https://tiny.hayoko.cn> · 邮箱：hayoko@hayoko.cn（已写入 `/etc/os-release`、ISO 元数据、主题包与终端登录横幅）

## 目录结构

```
tiny/
├── .github/workflows/build-iso.yml   # GitHub Actions 云端构建 + 启动测试
├── tynos/                            # TinyOS 构建工程（在 Linux 容器/系统中执行）
│   ├── build.sh                      # 一键构建入口
│   ├── tools/gen-assets.py           # 品牌视觉素材生成器（壁纸/开机标识，可复现）
│   └── config/                       # live-build 配置
│       ├── package-lists/            # 软件包清单（基础层 / 桌面层 / 可选安装器）
│       ├── hooks/
│       │   ├── live/                 # chroot 阶段钩子（源/语言/裁剪/兼容层/主题/品牌化）
│       │   └── binary/               # binary 阶段钩子（GRUB 品牌化）
│       ├── includes.chroot/          # 直接注入目标系统的文件
│       │   ├── etc/                  # 系统配置（APT 源、skel 用户模板、systemd 单元）
│       │   ├── usr/local/bin/        # TinyOS 工具（镜像优选/主题切换/Wine/Waydroid）
│       │   ├── usr/share/plasma/     # 3 套 Global Theme（深色/浅色/极光）
│       │   ├── usr/share/color-schemes/  # 3 套配色方案
│       │   ├── usr/share/wallpapers/     # 3 套壁纸包（构建时由 gen-assets.py 生成）
│       │   ├── usr/share/plymouth/       # 开机动画主题
│       │   └── usr/share/applications/   # 一键切换等桌面入口
│       └── includes.binary/          # GRUB 主题（ISO 文件系统层）
├── docs/
│   ├── BUILD.md                      # 构建流程文档
│   ├── TEST-REPORT.md                # 功能测试报告
│   └── evidence/                     # CI 自动归档的启动测试证据（截图/日志）
├── tools/
│   ├── join-iso.sh                   # ISO 分卷合并（Linux）
│   └── join-iso.ps1                  # ISO 分卷合并（Windows）
└── out/                              # 本地构建产物（ISO + SHA256 + 构建日志）
```

## 快速开始

### 方式一：GitHub Actions 云端构建（推荐，无需本地 Linux 环境）

在仓库页面 **Actions → 构建 TinyOS ISO → Run workflow** 手动触发，或直接向 `main` 推送 `tynos/` 下的改动自动触发。

流程会自动完成：释放跑者磁盘 → Debian 13 容器内 `live-build` 构建 → 校验镜像与 SHA256 → 离线断言关键组件 → QEMU 启动截图取证 → 归档证据 → 上传产物。

产物获取：

| 产物 | 说明 |
|------|------|
| `tinyos-iso` | 完整 ISO + `.sha256` + `build.log` |
| `tinyos-iso-parts` | ISO 超过 2GB 时的 1900MB 分卷（便于下载/再分发），用 `tools/join-iso.*` 合并 |
| `tinyos-evidence` | 启动截图、串口日志、关键文件清单 |

> 分卷合并：`./tools/join-iso.sh tinyos-1.0.0-whuang-amd64.iso`（Windows 见 `join-iso.ps1`），合并后自动比对 SHA256。

### 方式二：本地 Linux / WSL2 构建

```powershell
# 管理员 PowerShell：启用 WSL（需重启一次），随后安装 Debian
wsl --install --no-distribution
wsl --install --distribution Debian
```

```bash
# 在 WSL 的 Debian（或任意 Debian 13 环境 / debian:13 容器）中
cd /path/to/tiny/tynos
sudo ./build.sh                     # 输出到 ../out
```

### 写入 U 盘 / 启动

- Windows：用 **Rufus** 写入 U 盘（分区类型选 GPT，目标系统 UEFI）
- Linux：`sudo dd if=tinyos-1.0.0-whuang-amd64.iso of=/dev/sdX bs=4M status=progress`
- 虚拟机：`qemu-system-x86_64 -m 4096 -enable-kvm -device virtio-vga tinyos-1.0.0-whuang-amd64.iso`

首次启动自动登录进入桌面（Live 用户 `user` / 密码 `live`，免密 sudo）。首次开机会自动测试国内镜像延迟并切换到最快节点。

详细构建说明见 [BUILD.md](docs/BUILD.md)，实测结果见 [TEST-REPORT.md](docs/TEST-REPORT.md)。

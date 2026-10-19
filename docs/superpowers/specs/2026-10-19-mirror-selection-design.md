# 软件源扩展设计（国内 + 官方/国际节点）

- 日期：2026-10-19
- 状态：已确认（按方案 A 实施）

## 背景

原 `tinyos-mirror` 仅内置 7 个国内镜像，首次开机 `--auto` 会在这些节点中选最快者。
海外用户测得的最低延迟节点仍是国内源，更新体验差；构建期（CI 跑者在美西）也全部拉取 USTC。

## 目标

1. 海外用户首次开机后自动落到官方 CDN 或就近的大洲节点。
2. 国内用户默认仍走 USTC，行为不变。
3. 不引入外部 IP/地理定位服务依赖。

## 方案

`tinyos-mirror` 的镜像表改为显式数据结构：

```
name -> { base, security, label, region }
```

- `base` / `security` 均为完整 URL，不再从 base 推导 security 路径
  （官方源 `deb.debian.org` 的 security 位于 `security.debian.org`，推导会出错）。
- `region` 仅用于分组展示（`cn` / `intl`），不参与选路。

### 节点集合

| 区域 | 节点 |
|------|------|
| 国内 | USTC（默认）、TUNA、阿里云、华为云、腾讯云、网易、上海交大 |
| 国际/官方 | Debian 官方 CDN、Kernel.org（北美）、Hetzner（欧洲）、JAIST（日本）、AARNet（澳洲） |

国际节点的 security 统一使用官方 `https://security.debian.org/debian-security/`。

### 选择策略

- 并发探测每个节点 `dists/trixie/Release`（HEAD，6s 超时）。
- 返回 ≥400 或异常的节点标记为不可用，绝不写入源列表。
- 在全部可用节点中取延迟最低者；输出按国内/国际分组。
- `--auto` / `--list` / `--set` / `--quiet` 语义保持不变。

## 配套改动

- 镜像内默认 `sources.list`（品牌化钩子 + 兜底文件）的注释备用区补全国内/国际节点。
- firstboot、桌面入口、README、BUILD.md 文案同步。
- CI 构建源改为官方 CDN（跑者在美西），仅影响构建期，不影响镜像内默认源。

## 验收

- `tinyos-mirror --list` 能输出 12 个节点的延迟，分组正确。
- 海外环境下（可用官方 CDN 延迟最低模拟）`--auto` 选中官方或大洲节点。
- `--set debian` 生成的 `sources.list` 中 security 行为 `security.debian.org`。

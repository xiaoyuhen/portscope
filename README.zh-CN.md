# PortScope

[English](README.md) · 简体中文

一个原生 macOS 应用，列出本机所有正在监听的端口，说明每个服务究竟是做什么的，
并且可以直接停止或重启它 —— 不用再在 `lsof`、`ps` 和五个终端标签页之间来回翻。

> 状态：开发中。下面每个里程碑完成后都会以 PR 形式合入。

## 为什么需要它

`lsof -iTCP -sTCP:LISTEN` 只能告诉你端口 5173 属于某个 PID。它不会告诉你：这是
`~/work/acme-web` 项目的 Vite 开发服务器，它绑定在所有网卡上，而且已经跑了三天。
PortScope 一眼就能回答这些问题。

## 计划中的功能

- **实时刷新所有监听端口** —— 回环、局域网和通配绑定；IPv4 与 IPv6 合并为一行。
- **说明它是什么**，而不只是哪个 PID —— 服务类型、项目目录、框架、HTTP 响应头，
  以及每个判断的依据。
- **停止、强制停止、重启**服务；非开发服务器会先要求确认。
- **菜单栏常驻** —— 显示端口数量与最近变化。
- **中英文**，运行时可切换。
- **一键在浏览器打开**，或复制 `localhost:port`。

## 环境要求

- macOS 14 (Sonoma) 及以上
- Apple Command Line Tools —— **不需要安装 Xcode**

```bash
xcode-select --install   # 如果尚未安装
```

## 构建与运行

```bash
git clone git@github.com:xiaoyuhen/portscope.git
cd portscope
./scripts/build.sh          # debug
open dist/PortScope.app

./scripts/build.sh --release   # 优化构建
```

自检（不依赖测试框架）：

```bash
swift run PortScope --selftest
```

## 里程碑

| # | 里程碑 | 状态 |
|---|--------|------|
| M0 | 基础工程：包结构、应用包、构建脚本、国际化、自检 | ✅ |
| M1 | 原生端口扫描（libproc）与进程归属 | ⬜ |
| M2 | 服务识别：这个端口是干什么的 | ⬜ |
| M3 | 主窗口界面 | ⬜ |
| M4 | 停止 / 重启服务 | ⬜ |
| M5 | 菜单栏应用、语言切换、设置 | ⬜ |
| M6 | 兼容性矩阵、打包、文档 | ⬜ |

## 架构

```
Sources/
  PortScopeKit/          # 引擎，不含 UI，后续可复用于 CLI 或小组件
    Core/                # 数据模型、进程调用、本地化
    SelfTest/            # 内置检查，通过 --selftest 运行
  PortScope/             # SwiftUI 应用
    App/                 # 入口与应用级状态
    UI/                  # 设计变量与视图
```

引擎是纯 Swift 库，不依赖窗口服务即可测试和复用；应用层只负责呈现。

### 工具链说明

PortScope 仅依赖 Apple Command Line Tools 即可构建。这带来两点刻意的取舍：

1. **不使用 `@State` / `@Environment`。** 它们在当前 SDK 中是宏，而
   `SwiftUIMacros` 插件只在安装 Xcode 时才有。视图统一使用
   `ObservableObject` + `@StateObject` / `@EnvironmentObject`。
2. **不使用 XCTest / Swift Testing。** CLT 中两者都不可用，因此检查写在
   `PortScopeKit/SelfTest`，通过 `PortScope --selftest` 运行，CI 也调用同一入口。

## 许可证

MIT

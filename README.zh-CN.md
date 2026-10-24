# PortScope

[English](README.md) · 简体中文

一个原生 macOS 应用：列出本机所有正在监听的端口，说明每个服务究竟是做什么的，
并且可以直接停止或重启它 —— 不用再在 `lsof`、`ps` 和五个终端标签页之间来回翻。

![PortScope](docs/screenshots/ports-dark.png)

## 为什么需要它

`lsof -iTCP -sTCP:LISTEN` 只能告诉你端口 5173 属于某个 PID。它不会告诉你：这是
`~/work/acme-web` 项目的 Vite 开发服务器，它绑定在所有网卡上，而且已经跑了三天。
PortScope 一眼就能回答这些问题，并且会说明它凭什么这么判断。

## 功能

- **实时列出所有监听端口。** 回环、局域网、通配绑定都包括；同一服务的 IPv4 与
  IPv6 套接字合并为一行。整机扫描约 100 毫秒，且不需要任何提权。
- **默认安静。** 桌面应用和系统服务会长期占用端口，但它们几乎从来不是你打开端口
  监控的原因。判断规则不靠一份应用名单：开发运行时（node、python、docker、
  redis……）、运行在项目目录里的进程、以及已在识别阶段判定为系统的服务，永远
  显示；其余从 `.app` 启动的应用一律收拢成一行——"14 个桌面与系统端口"——点击
  才展开。装了新应用不需要改代码。搜索仍然能找到它们。
- **说明它是什么**，而不只是哪个 PID —— 服务、框架、项目目录、HTTP 状态，以及
  每个结论的依据。不确定时会明说："Node.js，55%"，而不是给一个看似肯定的猜测。
- **停止与重启。** 操作前确认，连同子进程一起处理，结束后验证结果。具体能碰什么、
  不会碰什么，见 [安全性](#安全性)。
- **菜单栏常驻。** 关掉窗口后 PortScope 仍在菜单栏显示实时端口数量。
- **中英文**，运行时可切换。默认一律英文，与系统语言无关；只有在设置里主动选择
  简体中文才会切换。
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
./scripts/package.sh           # 打包并计算校验和
```

## 命令行

同一个引擎，不开窗口 —— 便于脚本调用，兼容性测试也用它驱动。

```bash
PortScope --list            # 端口、进程、服务表格
PortScope --list --json     # 机器可读
PortScope --stop 3000       # 停止 :3000 上的服务
PortScope --restart 3000    # 停止后按原命令行重启
PortScope --selftest        # 内置检查，失败时退出码为 1
```

## 识别原理

三层证据，由强到弱。它们是**合并**关系而非互相替代：低层证据若与结论一致会提升
置信度，仅仅是"也存在"则不会。

| 层级 | 信号 | 例子 |
|------|------|------|
| 1. 进程 | 可执行文件、argv、工作目录 | `manage.py runserver` → Django，95% |
| 2. HTTP | 仅回环请求 `GET /` 的响应头 | `Server: AirTunes` → AirPlay 接收器 |
| 3. 端口 | 常见端口，最后手段 | 5173 → Vite，**上限 50%** |

置信度上限为 99%：这里的每一个信号都只是推断。能响应 HTTP 但匹配不上任何特征的
端口会显示为 "HTTP API"（35%），而不是"未知"——"这里有个 HTTP 服务"本身就是信息。

探测范围刻意收窄：只连 `127.0.0.1`（即使服务绑定在 `0.0.0.0` 也不走局域网地址）、
1.5 秒超时、固定 User-Agent、不使用代理；对不可能说 HTTP 的端口直接跳过。

## 安全性

PortScope 会改动你的机器，因此规则写在代码里：

- **绝不向不属于自己的进程发信号** —— 只处理当前用户的进程，绝不碰 PID 1，也绝不
  碰自己。被拒绝的原因会显示在界面上。
- **先 SIGTERM**，三秒宽限期后才 SIGKILL —— 并且会告诉你是否用了强杀。
- **连同子进程一起处理。** 开发服务器通常带着编译器、数据库和监听进程；只杀端口
  持有者会让它们继续占着端口。
- **从不读取你的环境变量。** 那里通常放着 API 密钥，所以重启后进程拿到的是你的
  shell 环境 —— 确认框里会说明这一点。
- **重启会验证。** 端口必须在 20 秒内重新监听，否则报告失败。输出写入
  `~/Library/Logs/PortScope/`。

## 兼容性

`scripts/compat/run.sh` 会在本机启动真实服务器，检查 PortScope 是否正确识别，
再用 PortScope 停止它并确认端口已释放。当前覆盖：Express 限流服务、Vite 开发
服务器、Python `http.server`、无框架的 Node 服务，以及 Express + Vite 的单仓
多服务。详见 [docs/compatibility.md](docs/compatibility.md)。

## 验证

分两层，因为它们能发现的问题不一样。

```bash
PortScope --selftest      # 56 项逻辑检查：扫描、识别、进程控制、折叠规则、
                          # 共享列表模型、本地化
./scripts/validate.sh     # 20 项针对运行中应用的界面检查
```

自检看不到菜单栏应用最容易出错的那类问题：窗口还能不能回来、面板和窗口显示的
是不是同一批行、全新安装时是哪种语言。`scripts/validate.sh` 通过辅助功能接口像
人一样操作构建好的应用：用隔离的偏好设置启动一份临时副本，打开菜单栏面板，关掉
窗口，点 "Open PortScope"，再把屏幕上的内容读回来。如果两个界面对于哪些端口被
折叠的结论不一致、窗口打不开（连续两次）、全新安装不是英文，或者已保存的中文
偏好没生效，它都会失败。

改动窗口、菜单栏或语言路径之后请运行它。终端需要辅助功能权限。

## 架构

```
Sources/
  PortScopeKit/          # 引擎，不含 UI，可复用于 CLI 或小组件
    Core/                # 扫描、进程信息、识别、进程控制
    SelfTest/            # 内置检查，通过 --selftest 运行
  PortScope/             # SwiftUI 应用
    App/                 # 入口、状态、菜单栏、命令行
    UI/                  # 设计变量与视图
```

### 工具链说明

PortScope 仅依赖 Apple Command Line Tools 即可构建。有几处 SDK 缺失是显式绕过的，
并且都在对应代码处写了说明：

- `@State` / `@Environment` 是宏，其插件只在安装 Xcode 时才有 → 视图局部状态用
  `LocalState<Value>`（只有一个属性的 `ObservableObject`）。
- CLT 中既没有可用的 XCTest，也没有 Swift Testing → 检查写在
  `PortScopeKit/SelfTest`，通过 `--selftest` 运行。
- `MenuBarExtra` 与 `NSPopover` 在此包结构下无法呈现 → 改用 `NSStatusItem` 与
  无边框 `NSPanel`。
- SwiftUI `.sheet` 不会弹出 → 改为窗口内确认层。

## 里程碑

| # | 里程碑 | 状态 |
|---|--------|------|
| M0 | 基础工程：包结构、应用包、构建脚本、国际化、自检 | ✅ |
| M1 | 原生端口扫描（libproc）与进程归属 | ✅ |
| M2 | 服务识别：这个端口是干什么的 | ✅ |
| M3 | 主窗口 | ✅ |
| M4 | 停止与重启服务 | ✅ |
| M5 | 菜单栏、语言切换、设置 | ✅ |
| M6 | 兼容性矩阵、打包、文档 | ✅ |

每个里程碑都以独立的 PR 合入，说明见 `docs/milestones/`。

## 图标

圆环代表端口，两组弧线从它向左右两侧发散。设计依据
[freshtechbro/claudedesignskills](https://github.com/freshtechbro/claudedesignskills)
中的 Bold Minimalism 原则。几何与设计说明见 [docs/logo.md](docs/logo.md)。

## 许可证

MIT

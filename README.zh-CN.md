# PortScope

[English](README.md) · 简体中文 · [Deutsch](README.de.md)

一个原生 macOS 应用：列出本机所有正在监听的端口，说明每个服务究竟是做什么的，
并且可以直接停止或重启它 —— 不用再在 `lsof`、`ps` 和五个终端标签页之间来回翻。

![PortScope](docs/screenshots/ports-dark.png)

## 安装

使用 [Homebrew](https://brew.sh)：

```bash
brew install --cask xiaoyuhen/tap/portscope
```

或者从 [Releases](https://github.com/xiaoyuhen/portscope/releases) 下载最新的
`PortScope-x.y.z.zip`，解压后把 `PortScope.app` 拖进「应用程序」。

构建产物是**临时签名（ad-hoc）、未经过公证**的，macOS 会拦下下载的 zip 第一次启动（Homebrew 安装会自动处理）。可以执行一次：

```bash
xattr -dr com.apple.quarantine /Applications/PortScope.app
```

或者先打开一次、关掉警告，再到「系统设置 → 隐私与安全性」里点「仍要打开」。
（macOS 14 上右键 →「打开」也可以；macOS 15 起取消了这个捷径。）

需要 macOS 14 (Sonoma) 及以上，Apple 芯片与 Intel 都支持。

## 从源码构建

不需要 Xcode，Apple Command Line Tools 即可。

```bash
git clone https://github.com/xiaoyuhen/portscope.git
cd portscope
./scripts/build.sh
open dist/PortScope.app
```

`./scripts/package.sh` 生成与 release 相同的压缩包：通用二进制（Apple 芯片与
Intel 均可运行），附校验和，并会在解压后验证签名。

## 为什么需要它

`lsof -iTCP -sTCP:LISTEN` 只能告诉你端口 5173 属于某个 PID。它不会告诉你：这是
`~/work/acme-web` 项目的 Vite 开发服务器，它绑定在所有网卡上，而且已经跑了三天。
PortScope 一眼就能回答这些问题，并且会说明它凭什么这么判断。

## 功能

- **实时列出所有监听端口。** 回环、局域网、通配绑定都包括；同一服务的 IPv4 与
  IPv6 套接字合并为一行。枚举套接字并读取进程信息约需 100 毫秒；首次扫描还会对
  每个候选端口做一次 HTTP 探测，整体约 2 秒，且不需要任何提权。
- **默认安静。** 桌面应用和系统服务会长期占用端口，但它们几乎从来不是你打开端口
  监控的原因。判断规则不靠一份应用名单：开发运行时（node、python、docker、
  redis……）、运行在项目目录里的进程、以及已在识别阶段判定为系统的服务，永远
  显示；其余从 `.app` 启动的应用一律收拢成一行——"14 个桌面与系统端口"——点击
  才展开。装了新应用不需要改代码。搜索仍然能找到它们。
- **说明它是什么**，而不只是哪个 PID —— 服务、框架、项目目录、HTTP 状态，以及
  每个结论的依据。不确定时会明说："Node.js，55%"，而不是给一个看似肯定的猜测。
- **Docker 容器按名字显示。** 发布出来的端口会显示背后的容器——`acme-web-1`、镜像、
  Compose 项目——而不是 `com.docker.backend`。运行数据库或缓存镜像的容器计入数据存储。停止和重启通过引擎 API 只作用于这一个
  容器，绝不碰 Docker 本身。支持 Docker Desktop、OrbStack、Colima 和 Rancher
  Desktop，不需要 CLI。
- **停止与重启。** 操作前确认，连同子进程一起处理，结束后验证结果。具体能碰什么、
  不会碰什么，见 [安全性](#安全性)。
- **菜单栏常驻。** 关掉窗口后 PortScope 仍在菜单栏显示实时端口数量；面板列出与
  主窗口完全相同的行。设置里一个开关即可**登录时自动打开**。
- **英文、简体中文和德语**，运行时可切换。默认一律英文，与系统语言无关；只有在
  设置里主动选择其他语言才会切换。
- **自动更新。** 每天检查一次 GitHub Releases；有新版本时展示更新内容，「安装并重新打开」
  会下载、校验校验和与签名，然后原地替换。可以跳过某个版本，也可以在设置里关掉检查。
- **一键在浏览器打开**，或复制 `localhost:port`。

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

探测范围刻意收窄：只连回环地址——`127.0.0.1`，仅绑定 IPv6 的服务则连 `::1`（即使服务绑定在
`0.0.0.0` 也不走局域网地址）；从不跟随重定向；1 秒超时、固定 User-Agent、不使用代理；对不可能说
HTTP 的端口直接跳过。

## 折叠规则

规则是结构性的，不靠一份应用名单，所以装了新应用也不需要改代码：

1. 开发类服务（开发服务器、打包器、数据库、缓存、容器、AI）→ **显示**。
2. 可执行文件是开发运行时（`node`、`python3.12`、`redis-server`、`docker`……）→
   **显示**。
3. 能识别出项目目录 → **显示**。
4. 识别阶段判定为系统服务 → **折叠**。
5. 位于 `/System/`、`/usr/libexec/` 等路径下 → **折叠**。
6. 位于 `.app` 包内 → **折叠**。
7. 其余 → **显示**。

顺序本身就是设计。第 2 步在第 5 步之前，所以用 `/usr/bin/python3` 跑的
`python3 -m http.server` 仍然可见；也在第 6 步之前，所以 Docker 的
`com.docker.backend` 监听仍然可见。第 7 步选择的是安全方向：把用户正在找的那一行
折叠掉，代价远高于多显示一行。

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

## 隐私

端口、进程、路径和命令行都不会离开这台机器。

唯一的例外是**匿名启动统计**：每个版本每天最多一次，发送版本号、macOS 主次版本、
架构，以及一个随机的安装 UUID。绝不包含端口、进程、路径或主机名，也不存储 IP。

默认开启，可在设置里关闭。完整请求体、接收端存储格式以及所有关闭方式见
[docs/privacy.md](docs/privacy.md)。从源码构建的版本除非显式传入
`PORTSCOPE_TELEMETRY_URL`，否则不发送任何数据。

## 验证

三层，因为它们能发现的问题不一样。

```bash
PortScope --selftest              # 逻辑检查，失败时退出码为 1
./scripts/compat/fixtures.sh      # 4 个真实服务器：识别、停止
./scripts/validate.sh             # 20 项针对运行中应用的界面检查
```

**自检**覆盖扫描、识别、进程控制、折叠规则、共享列表模型和本地化。它是手写的
检查框架，因为在只有 Command Line Tools 的环境里 XCTest 和 Swift Testing 都用不了。

**兼容性矩阵**会启动真实服务器——一个 Express 形态的 HTTP 服务、一个无框架的
Node 服务、Python 的 `http.server`，以及一个从项目目录启动的服务——询问 PortScope
每个是什么，然后**通过 PortScope 本身**停止它，并确认端口确实已释放。它不依赖
仓库之外的任何东西，所以能在 CI 里跑。

**界面检查**通过辅助功能接口像人一样操作构建好的应用：用隔离的偏好设置启动一份
临时副本，打开菜单栏面板，关掉窗口，点 "Open PortScope"，再把屏幕上的内容读回来。
如果两个界面对于哪些端口被折叠的结论不一致、窗口打不开（连续两次）、全新安装不是
英文，或者已保存的中文偏好没生效，它都会失败。

CI 跑前两项加上应用包校验；界面检查需要图形会话，所以在本地运行，但 CI 会编译它
以免失效。

## 架构

```
Sources/
  PortScopeKit/          # 引擎，不含 UI，可复用于 CLI 或小组件
    Core/                # 扫描、进程信息、识别、进程控制
    SelfTest/            # 内置检查，通过 --selftest 运行
  PortScope/             # SwiftUI 应用
    App/                 # 入口、状态、菜单栏、统计、命令行
    UI/                  # 设计变量与视图
Support/Validation/      # 界面检查脚本驱动的验证程序
infra/telemetry/         # 统计启动次数的 Cloudflare Worker
```

没有任何第三方依赖。引擎只用标准库和 Darwin，所以应用只有几 MB，且仅靠 CLT 就能
构建。

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
- SwiftUI 关闭 `WindowGroup` 窗口时会销毁它 → `MainWindowController` 拦截关闭
  改为隐藏，这样菜单栏入口永远有东西可打开。

## 参与贡献

欢迎提 issue 和 PR。先读 [CONTRIBUTING.md](CONTRIBUTING.md)：里面列了需要运行的
检查，以及代码遵循的约定。安全问题请走 [SECURITY.md](SECURITY.md)，不要开公开
issue。

## 维护者说明

使用情况有两个来源，都不需要长期维护的服务：

- **release 下载量。** GitHub 会统计每个 release 附件的下载次数。
  `.github/workflows/usage-report.yml` 每月把快照追加到一个名为 "Usage" 的
  滚动 issue。

  ```bash
  gh api repos/xiaoyuhen/portscope/releases/latest \
    --jq '.assets[] | "\(.name): \(.download_count)"'
  ```

- **应用内的匿名启动统计**，前提是配置了接收端。Worker 在
  [infra/telemetry](infra/telemetry/)，部署只需一次 `wrangler deploy`，然后把
  URL 填进仓库变量 `PORTSCOPE_TELEMETRY_URL`。在设置该变量之前，release 构建
  不发送任何数据。

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
| M7 | 菜单栏一致性、折叠规则、默认语言、界面验证 | ✅ |

每个里程碑都以独立的 PR 合入，说明见 `docs/milestones/`。

## 图标

圆环代表端口，两组弧线从它向左右两侧发散。设计依据
[freshtechbro/claudedesignskills](https://github.com/freshtechbro/claudedesignskills)
中的 Bold Minimalism 原则。几何与设计说明见 [docs/logo.md](docs/logo.md)。

## 许可证

MIT

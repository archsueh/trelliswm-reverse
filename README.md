# TrellisWM clean-room study

> **非官方声明 / Disclaimer**：本项目是独立的 clean-room 规格研究，与 TrellisWM 及其作者**无关联、未获背书**。`capture/` 中的原品元数据与符号名仅作事实引用，TrellisWM 及相关商标归其权利人所有。完整说明见 [NOTICE.md](NOTICE.md)。

以 `storytold/craft-anything` 的 **Study → Build → Check → Ready** 方法，从 `/Applications/TrellisWM.app` 0.10.0 (build 560) 的**可见证据**逆推规格，并独立写出一套可编译、可单测、可交互的实现。

**结论：READY · 14/14 Check 通过 · Swift 18/18 单测 · JS 24/24 自检。**
这不是可替代原品的 app，是一份带证据台账、置信度和明确局限的规格验证工程。

---

## 0. 先纠正两个前提

| 早期判断 | 实测结论 | 置信度 |
|---|---|---|
| TrellisWM 是 AeroSpace / yabai 那类 BSP 平铺 WM（依据二进制里 `tiling` / `BSP` 字样） | **错**。它是「分形 / 相机式」窗口管理器：递归 split 树里 `split` 可以再包含 `split`，窗口可嵌套在另一个空间内部；导航靠 step in/out、back/forward、saved views，不是切 workspace | 高 |
| 「用 craft-anything 复刻代码」 | craft-anything 是 **clean-room 逆向工程方法论 + 引擎**，不是代码模板。默认 Clean room 不读内部代码，Deep 才动反汇编 / Ghidra。本次全程只用 Clean room | 高 |

`strings` 里的类型名属 L5 低置信度线索，**单凭名字不断言行为**；任何行为结论都要有 L1（公开文档）/ L3（app 自己的布局文档）/ L4（运行日志）二次印证。

---

## 1. 目录结构

```
trelliswm-reverse/
├── craft.json                     项目清单、方法、边界、产物索引
├── README.md                      本文件
├── capture/                       Study：只读采集的证据（均可由脚本重采）
│   ├── evidence.md                证据台账（分层、主题、局限、溯源 S1–S10）
│   ├── commands.json              15 条 URL 命令 / 12 行快捷键 / 8 panes / 权限 / Free-Pro
│   ├── info-plist.json            bundle 元数据
│   ├── release-defaults.json      47 项默认设置 + 33 项 offered
│   ├── layout-schema.json         树文法 + 7 条不变量
│   ├── layout-sample.json         脱敏的真实嵌套布局树（来自 departures.json 模板）
│   ├── runtime-events.json        事件词汇、状态迁移、SETTLED 时长分布
│   └── symbols.json               符号名（仅术语提示，无反汇编）
├── investigation.cany/
│   ├── questions.md               Q1–Q16：结论 / 置信度 / 证据 / 已纠正的过度断言
│   └── coverage.md                覆盖与追溯矩阵
├── app/                           Build：独立 Swift 实现
│   ├── Package.swift
│   ├── Sources/TrellisCore/       LayoutNode / LayoutEngine / Camera / Commands / Settings / LayoutDocument
│   ├── Sources/TrellisApp/        AppKit + AX 窗口系统封装、菜单栏、probe 入口
│   └── Tests/TrellisCoreTests/    18 个 XCTest
├── sim/index.html                 Build：JS 独立实现 + 交互模拟器（无需任何权限）
├── checks/
│   ├── collect_evidence.py        只读重采证据
│   ├── check_evidence.py          Check：三方注册表比对 + 实跑单测 + 无头渲染
│   ├── report.json / CHECKS.md    机器可读 / 人读的检查结果
│   └── sim-render.png             无头实渲染截图
└── inbox/unspecified.md           Ready：未解决问题与提高置信度的正当做法
```

---

## 2. 逆推出的规格（核心）

```
Node    := Desktop | Panel | Split
Desktop := { kind:"desktop", id:"desktop" }              # 恒定的浮动窗口层叶子
Panel   := { kind:"panel", id, views:[SeatID], selected, tabbed? }   # views>1 即 tab group
Split   := { kind:"split", id, axis:"x"|"y", children:[Node], weights:[Double] }  # Σweights=1
```

- 「无限嵌套」没有额外机制，就是 `split.children` 允许再放 `split`（真实模板深度 ≥ 3）。
- `desktop` 是树中唯一恒定的叶子，dock 时永远保留其空间；guide 的 "One part of the screen is the Desktop" 与此对应。
- 相机 = `framed` 节点 id + 一对浏览历史栈，不是连续缩放引擎；9 个 saved view 槽位。
- 窗口移动走 macOS Accessibility，zoom 时显示的是**静态截图图层**（ScreenCaptureKit），不是录屏。
- 布局按 `<display-UUID>|desktop-1` 分文件持久化，`version: 2`；`seats` 存窗口指纹用于「退出后归位」，但**哈希算法与匹配权重未知**。

完整文法与 7 条不变量见 `capture/layout-schema.json`，命令与快捷键见 `capture/commands.json`。

---

## 3. 实跑结果

| 项 | 命令 | 结果 |
|---|---|---|
| 重采证据 | `python3 checks/collect_evidence.py` | 7 个 capture 文件，只读 |
| Swift 编译 | `cd app && swift build --disable-sandbox` | 通过（本机 SwiftPM manifest 沙箱被拒，需该 flag） |
| Swift 单测 | `cd app && swift test --disable-sandbox` | **18 tests / 0 failures** |
| 只读窗口探测 | `app/.build/debug/trellis-probe --live` | 枚举到本机窗口，**未移动任何窗口** |
| 静态校验 | `python3 checks/check_evidence.py --headless` | **14/14 PASS · READY** |
| 无头渲染 | Chrome `--headless=new --dump-dom --screenshot` | `selftest PASS 24/24`，6 个窗口节点渲染 |
| 真实 API / 权限 | — | **不需要**。模拟器是纯前端；App 骨架只对 AX 做只读封装 |

`sim/index.html` 直接双击即可用：点窗口 frame（再点退回）、拖标题栏到某条边 dock、拖间隙改权重、15 条命令按钮、URL 输入框、`⌃⌥` 快捷键、back/forward、saved views 1–9、切换「显示空间边界」看递归层级、载入真实模板权重看窄 tile 退化成 app 图标。

---

## 4. 两套实现互相印证

同一份规格分别用 Swift（纯函数、返回新树）和 JS（同样纯函数）独立写了一遍，`check_evidence.py` 再把两者与证据三方比对：

| 注册表 | 证据 | Swift | JS spec | 结果 |
|---|---|---|---|---|
| URL 命令 | 15 | 15 个 switch case | 15 | 一致 |
| settings pane | 8 | 8 个 enum case | 8 | 一致 |
| 发布默认键 | 47 | 47 个属性 | 47 | 一致 |
| 快捷键 | 12 行 | — | 12 行逐字 | 一致 |

---

## 5. 边界与局限（必须随交付一起读）

**没有做的事**：反汇编 / 反编译 / Ghidra；复制任何源码、图标、壁纸、教程资源或本地化文案（497 条只作术语读取）；绕过许可、试用或激活；注册原产品的 bundle ID；触碰正在运行的 TrellisWM 的任何窗口。

**明确标 `UNSPECIFIED`、未实现也不伪造等价**：手势阈值与滤波、pinch→zoom 连续映射、动画 easing 曲线、窗口指纹哈希与匹配权重、静态截图缓存淘汰、多显示器 Space 私有 API、许可校验协议。实现里分别用可替换默认或 `SeatMatcher` 协议占位。

**低置信度 / 歧义**：
- Q13 dock 到边时「新建 split 还是并入既有 split」只有行为描述、无成对前后快照 → 推断。
- Q16 `framed:"desktop"` 是「缩到最外」还是「单独 frame Desktop」在现有样本里不可分（全浮动时 root 就是 desktop 叶子）→ 实现采用自洽约定，非观测事实。
- Q14 seat 哈希算法 → 未知。

**Check 阶段纠正的 4 处过度断言**见 `investigation.cany/questions.md` 的「已纠正的过度断言」表，其中最重要的是：460ms 是完整 layout motion 的**主模态 / 中位数**，不是全样本均值（均值约 366ms，被中断的快速 motion 拉低）。

---

## 6. 溯源

| 编号 | 来源 |
|---|---|
| S1–S3 | `trelliswm.app/`、`/docs/`、`/appcast.xml` |
| S4–S6 | `Contents/Info.plist`、`Resources/ReleaseSettings.json`、`{en,zh-Hans}.lproj/Localizable.strings` |
| S7 | `~/Library/Application Support/TrellisWM/*.json` |
| S8 | `~/Library/Logs/TrellisWM.log` |
| S9 | `/usr/bin/strings Contents/MacOS/TrellisWM`（术语提示） |
| S10 | `storytold/craft-anything` README（方法论） |

对象只在其所有者本机、应所有者要求被检查。Clean room 指「从可见行为独立实现」，不是 OS sandbox。

---

## 7. 下一步（都由你点头才动）

1. 把 `app/` 做成真正可运行的 `.app`：接 AX 写操作（需要 Accessibility 授权）、静态截图管线、Sparkle 之外的分发与签名。
2. 提高 Q13 / Q16 置信度：在你自己机器上做成对行为采样（dock 前后各导一次 `layout-*.json` 比对树差异），不需要读内部代码。
3. 把这套 Study → Build → Check 流程固化成可复用 skill，用于下一个 app 的规格逆推。

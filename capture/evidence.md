# Evidence ledger — TrellisWM 0.10.0 (build 560)

采集日期：2026-11-09 · 对象：`/Applications/TrellisWM.app` · 方式：**只读**，未运行除官方 app 自身外的任何注入、未反汇编、未反编译。

## 0. 先纠正一个前提

**TrellisWM 不是平铺窗口管理器。** 早期会话里根据二进制中 `tiling` / `Workspace` / `BSP` 字样把它归入 AeroSpace / yabai 一类，这个判断是错的（置信度：高，已被两份独立证据推翻）：

| 维度 | AeroSpace / yabai | TrellisWM |
|---|---|---|
| 排布 | 二叉树切分，所有窗口同屏不重叠 | 递归 split 树，**窗口可嵌套在另一个空间的内部**，不必同屏 |
| 导航 | 切换 workspace / focus | **相机式 zoom**：step in / out 层级，back / forward 历史 |
| Desktop | 无特殊地位 | 树里有一个恒定的 `desktop` 叶子，专供浮动窗口 |
| 输入 | 快捷键 / 配置 | 快捷键 + 拖拽 dock + 触控板 pinch / pan + URL 命令 |
| 视觉 | 直接移动真实窗口 | Zoom 时用窗口**静态截图**（"Pictures, never recordings"）作图层 |

官网自称 "**The fractal window manager for Mac**"；guide 原文："Docked windows can even hold spaces inside spaces, as deep as you like." 本机持久化文档也确实是任意深度的递归 `split` 节点。

## 1. 证据分层

| 层 | 来源 | 性质 | 可引用程度 |
|---|---|---|---|
| **L1** | `https://trelliswm.app/`、`/docs/`、`/appcast.xml` | 公开产品文档，作者自述 | 最高。命令、快捷键、权限、Free/Pro 全部逐字可核。 |
| **L2** | `Contents/Info.plist`、`Resources/ReleaseSettings.json`、`en.lproj/Localizable.strings`、`zh-Hans.lproj/Localizable.strings` | 随 bundle 分发、用户可见的元数据与 UI 文案 | 高。设置键与默认值是事实数据；本地化文案**只作术语**使用，不复制。 |
| **L3** | `~/Library/Application Support/TrellisWM/*.json`（app 自己的持久化文档） | 真实运行产生的布局树 | **最高（结构性）**。数据模型不由猜测得出。 |
| **L4** | `~/Library/Logs/TrellisWM.log` | app 自己的事件日志 | 高。事件词汇、动画时长、性能计时可实测。**日志持续写入**，行数 / 样本数一律以 `runtime-events.json` 的 `log_lines` / `settled_ms.samples` 为准，本文不写死计数。 |
| **L5** | `/usr/bin/strings` 输出的符号名 | 仅为「术语提示」 | 低。**单凭类型名不断言任何行为**，所有 L5 线索必须由 L1/L3/L4 二次印证才进入规格。 |

产物索引：`info-plist.json`、`release-defaults.json`、`layout-schema.json`、`layout-sample.json`、`runtime-events.json`、`symbols.json`、`commands.json`。可复现采集器：`checks/collect_evidence.py`。

## 2. 主题台账

### 2.1 身份与分发（L1 + L2，置信度：高）

| 项 | 值 |
|---|---|
| Bundle ID | `app.trellisui.trelliswm` |
| 版本 | `0.10.0` / build `560`；appcast 上一版 `0.9.8` (307)、`0.9.7` (260) |
| 作者 | © 2026 Dan Fessler |
| 最低系统 | macOS 14.0，arm64 only |
| 形态 | `LSUIElement=true`（无 Dock 图标，菜单栏 agent） |
| URL scheme | `trelliswm` |
| 更新 | Sparkle，`https://trelliswm.app/appcast.xml`，EdDSA 签名 + delta 更新 |
| 主体积 | 11 MB，主可执行文件 6.5 MB，仅内嵌 Sparkle.framework（**无第三方 WM 引擎**） |
| 语言 | en + zh-Hans，各约 497 条本地化条目 |

### 2.2 数据模型（L3，置信度：**高 / 实测**）

从 `layout-*.json`、`arrangement-*.json`、`departures.json` 逆推出的文法：

```
Node  := Desktop | Panel | Split
Desktop := { kind: "desktop", id: "desktop" }
Panel   := { kind: "panel", id: String, views: [SeatID], selected: SeatID, tabbed: Bool? }
Split   := { kind: "split", id: "split-XXXXXX", axis: "x" | "y",
             children: [Node], weights: [Double] }   // sum(weights) == 1
```

观测到的不变量（`capture/layout-schema.json` 有完整列表）：

1. `split` 可递归包含 `split` —— 这就是「分形 / ∞ 层嵌套」的实现，**不是**额外机制。
2. `desktop` 是唯一恒定的叶子，浮动窗口层；guide 的 "One part of the screen is the Desktop" 与此一一对应。
3. `panel.views` 有多个元素即 **tab group**，`selected` 指向当前 tab；`tabbed` 为可选项。
4. `weights` 归一化，控制 `axis` 方向上的比例；真实样本里有 `[0.585, 0.012, 0.012, 0.390]` 这种被压到极窄的 tile —— 对应 guide 里「窗口太小时显示为 app 图标」的行为。
5. 顶层文档：`{doc:{root,floating,hidden}, dockSpots, floatSizes, framed, framings, framedLeaves, seats, saved, session, version:2, world, mirrorDigest, saltDigest}`。
6. `framed` 存相机焦点节点 id；`framings` 缓存每个焦点节点的矩形。**歧义（置信度：中，须降级）**：真实样本里 `framed: "desktop"` 时 `doc.root` 本身也是 `{kind:"desktop"}` 叶子（全浮动状态），因此「缩到最外」与「单独 frame Desktop」在数据上重合、无法区分；早期把它直接写成「表示缩到最外」是过度断言。guide 的 `frame-desktop` 明确是后者。实现按 `everything → root.id` / `frame-desktop → "desktop"` 拆开，属约定而非观测结论，见 Q16。
7. `seats` 以稳定 seat id 记窗口指纹（`frame` / `realFrame` / `titles` / `tokens` / `document` / `pid` / `session` / `placement`），用于「退出后窗口回到原位」和「重开的窗口归位」。
8. `departures.json` 存 `{ghosts, salt, templates, version}`，templates 里保存历史布局树模板，按窗口指纹匹配归位。

`world` 形如 `<display-UUID>|desktop-1`，说明布局按「显示器 + macOS Space」独立持久化。

### 2.3 相机与导航（L1 + L3 + L4，置信度：高）

| 概念 | 证据 | 推导 |
|---|---|---|
| zoom out / everything | `⌃⌥Space`、`trelliswm://everything` | 把 `framed` 设为根节点 |
| step in / out | `⌃⌥↑/↓`、`zoom-in` / `zoom-out` | 在树中上移/下移一层，非连续缩放 |
| frame a window | `⌃⌥↩`、双击标题栏、`frame-window` | `framed = <node id>`，`framings` 记住来处以支持「再按一次返回」 |
| frame the Desktop | 双击 Desktop、`frame-desktop` | `framed = "desktop"`；与 `everything` 的区别见上文歧义 |
| back / forward | `⌃⌥[ ]`、`back` / `forward` | 独立的浏览历史栈，guide 明说 "like a web browser" |
| saved views 1–9 | `⌃⌥⇧n` / `⌃⌥n`、`view?n=` / `save-view?n=` | 9 个相机状态槽位，per display |
| neighbouring space | 方向键、`neighbour?dir=` | 在**当前层级**的同级节点间移动，不是切 macOS Space |
| rectangle zoom | `⌘⇧`-drag | 框选若干节点，计算包围矩形并 frame |

### 2.4 动效与性能（L1 + L4，置信度：高 / 本机实测）

官网标称 **460ms** "one layout motion for every split, dock and close"。**这里纠正一处统计口径错误**：早期结论写「实测与标称吻合」时只挑了 `SETTLED after 461/464 ms` 两条；全量样本并不支持「均值 460ms」的说法。本机 `SETTLED after N ms` 样本的**中位数是 460.0ms**、约半数落在 450–479ms 区间，但**均值只有约 366ms**（min 33 / max 801）——一批 <100ms 的被中断 / 快速 motion 把均值拉低了。因此 460ms 是**完整 layout motion 的主模态**，不是全样本均值；本实现的 CSS 过渡取 460ms 作为典型值。样本数、桶计数与每次采集时点见 `runtime-events.json` 的 `settled_ms`（日志持续写入，数字会漂移，不写死）。完整时序在日志里是：

```
MOTION land → <target>
BEGIN slow <n> ms
SETTLED after 46x ms
HANDOFF ... / FRAMES <display> 107 in 885 ms at 120 Hz: 0 dropped
LANDED <target> in 1128 ms
```

采集到的事件词汇共 23 种，高频的是 `ADD / REMOVE / ADOPT / MINIMUM / MAXIMUM / GHOST / MOTION / BEGIN / SETTLED / LANDED / RESTORE / PICTURES`（完整计数见 `runtime-events.json`）。`PICTURES` 约每 5 分钟报告一次缓存；其中一次采样为 21 个窗口约 354.8 MB + 壁纸 52.4 MB —— 印证「静态截图图层、不录屏」是真实实现而非营销措辞。

`MINIMUM` / `MAXIMUM` 事件显示 app 会按 bundle ID **学习**每个 app 的最小/最大尺寸并持久化到 `defaults` 的 `appMinimums`（采集时点 25 个 app，随使用增长；不写死），窗口太小时以图标/颜色占位——真实模板里 `[0.585, 0.012, 0.012, 0.390]` 那种被压窄的 tile 正是这一行为的结果。

### 2.5 设置面（L2，置信度：高）

`ReleaseSettings.json` 给出 **47 项默认值** + **33 项** `offered` 设置条目（分 `standard` / `advanced` / `hidden` 三档可见性）。日志启动时也打印 `SETTINGS 47 release defaults registered`，两处互证。代表性键：

| 类别 | 键（默认值） |
|---|---|
| 几何 | `gap=12`、`desktopEdgeStrength=0.05`、`fixedMinimum=false`、`squeezeBelowMinimum=true`、`shareRemovedSpace=true` |
| 动效 | `animationSpeed=1`、`redrawWait=0.5`、`interruptLandings=true`、`reflowWhileDragging=true` |
| 拖拽预览 | `previewDrags=true`、`previewStyle="tinted"`、`tintOpacity=0.8`、`appColours=true`、`appColourAmount=0.25` |
| 相机 | `stepTowardPointer=false`、`panSensitivity=1.8`、`touchPinchPan=true`、`deskPinchSteps=false` |
| Tab | `tabStyle="material"`、`tabPadding=8`、`tabInset=2`、`tabChipMargin=4`、`tabCloseButtons=true` |
| 系统集成 | `replaceMissionControl=true`、`menuBarControls=true`、`menuBarFill=0.12`、`overviewSwipesSpaces=false` |
| 恢复 | `returnReopenedWindows="afterQuit"`、`hiddenDesktopReturns=false`、`soleFloatTakesDesktop=true` |

### 2.6 命令面（L1，置信度：高 / 逐字）

15 条 `trelliswm://` 命令、12 行主快捷键、8 个 settings pane 全部在 `capture/commands.json`。Free 每 desktop 最多 5 个 docked 窗口；Pro 才有 tab groups / saved views / URL 命令。

### 2.7 术语提示（L5，置信度：**低**，仅用于命名参考）

`strings` 中出现 52 个 PascalCase 类型名，例如 `LayoutNode`、`LayoutDocument`、`LayoutMetrics`、`TileLayoutManager`、`WindowPlan`、`WindowTracker`、`SpaceZoom`、`CameraCurve`、`LayoutTween`、`PictureLayer`、`DockTarget`、`TabStripLayer`、`GapHandleWindow`、`OverviewShape`、`AppLimitStore`、`DisplayStore`。配合 `AXObserver`、`AXUIElement`、`AXWindowCreated`、`AXWindowMiniaturized`、`ScreenCaptureKit` 可判断：

- 窗口操作走 **macOS Accessibility API**（与 L1 的「Accessibility 权限必需」一致）；
- 静态截图走 **ScreenCaptureKit**（与 L1 的「Screen Recording 权限、Pictures never recordings」一致）；
- 截图图层、tab strip、gap handle、overview 都是自绘的 `NSWindow` / CoreAnimation 图层（与 L1 的 "Written in Swift" 一致）。

**这里没有反汇编、没有函数体、没有任何代码被复制。** 类型名只作为本实现模块划分的命名参考。

## 3. Limitations（必须随交付一起读）

1. **未实现、也无法从证据确定的部分**：手势识别的具体阈值与滤波、pinch 到 zoom level 的连续映射曲线、图片缓存的淘汰策略、动画 easing（`CameraCurve` / `LayoutTween` 只有名字）、多显示器的 Space 私有 API 用法、许可校验协议。规格里这些一律标 `UNSPECIFIED`，实现里用可替换的合理默认，不做「复刻」宣称。
2. **L3 样本偏窄**：本机当前 `doc.root` 多为 `{"id":"desktop","kind":"desktop"}`（用户近期处于全浮动状态），深层嵌套树来自 `departures.json` 的**历史模板**。树文法本身确定，但「dock 到某条边时如何决定新建 split 还是并入既有 split」的启发式只有 guide 的行为描述，没有成对的操作前后快照，属于**推断（置信度：中）**。
3. **窗口身份匹配**：`seats` 用 `titles` / `tokens` / `document` / `session` 做指纹，`mirrorDigest` / `saltDigest` 参与哈希。字段可见，但哈希算法与匹配权重**未知**，实现里用可插拔的 `SeatMatcher` 接口占位。
4. **版权边界**：497 条本地化文案、`AppIcon.icns`、`MenuBarIcon.svg`、`Lessons/` 资源均未复制到本实现；本实现不复用产品名、bundle ID 或 URL scheme 的归属标识。UI 术语只用于文档对照。
5. **不是可替代原品的 app**：`app/` 是 clean-room 的核心逻辑 + 可编译 macOS 骨架，不含签名、不含 Sparkle 更新、不含授权、不含手势识别全链路、不含静态截图管线。`sim/` 是可交互模型，用来验证规格，不是产品。

## 4. 溯源

| 编号 | 来源 | 用途 |
|---|---|---|
| S1 | `https://trelliswm.app/` | 产品定位、快捷键摘要、性能指标 |
| S2 | `https://trelliswm.app/docs/` | 完整 guide：命令、快捷键、权限、Free/Pro、故障排查 |
| S3 | `https://trelliswm.app/appcast.xml` | 版本历史、build 号、平台要求 |
| S4 | `Contents/Info.plist` | bundle 元数据 |
| S5 | `Contents/Resources/ReleaseSettings.json` | 47 项默认设置 |
| S6 | `Contents/Resources/{en,zh-Hans}.lproj/Localizable.strings` | 术语与交互约定（不复制全文） |
| S7 | `~/Library/Application Support/TrellisWM/*.json` | 真实布局树与 seat 结构 |
| S8 | `~/Library/Logs/TrellisWM.log` | 事件词汇、动画时长、性能计时 |
| S9 | `/usr/bin/strings Contents/MacOS/TrellisWM` | 类型名 / AX / ScreenCaptureKit 术语 |
| S10 | `https://raw.githubusercontent.com/storytold/craft-anything/main/README.md` | 方法论：Study → Build → Check → Ready / Refine，evidence / confidence / coverage / limitations |

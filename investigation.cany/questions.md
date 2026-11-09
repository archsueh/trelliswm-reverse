# Investigation — 问题、结论、置信度

方法：Study → Build → Check → Ready。每个问题必须有可引用的证据，不给投机性答案。

| # | 问题 | 结论 | 置信度 | 证据 |
|---|---|---|---|---|
| Q1 | craft-anything 是逆向工具还是项目模板？ | 是 **clean-room 逆向工程方法论 + 引擎**（Rust），不是代码模板。流程 Study → Build → Check → Ready/Refine，强调 evidence / confidence / coverage / limitations / responsible use。默认 Clean room 只读可见证据，Deep 才动 decoders / disassembler / Ghidra。 | 高 | S10 |
| Q2 | TrellisWM 属于哪一类 WM？ | **分形 / 缩放式**窗口管理器，不是 BSP 平铺。递归 split 树 + 相机层级 + 静态截图图层。 | 高 | S1 S2 S7 |
| Q3 | 「无限嵌套」怎么实现？ | 没有额外机制：`split.children` 允许再放 `split`，任意深度。 | 高 | S7（真实嵌套树样本，depth ≥ 3） |
| Q4 | Desktop 在模型里是什么？ | 树中唯一的 `{"kind":"desktop","id":"desktop"}` 叶子，专供浮动窗口， Dock 时永远保留其空间。 | 高 | S2 S7 |
| Q5 | zoom 是连续缩放还是离散层级？ | 主要是**离散层级**（step in/out 一层）；`⌥`-pinch / `⌘⇧` 框选提供连续相机，`panSensitivity` 与 `CameraCurve` 暗示存在连续插值，但曲线参数未知。 | 中 | S2 S5 S9 |
| Q6 | 窗口如何被移动？ | macOS Accessibility：`AXUIElement` 设置 position/size，`AXObserver` 订阅 `AXWindowCreated` / `AXWindowMiniaturized` / `AXWindowDeminiaturized` / `AXUIElementDestroyed`。 | 高 | S9 + S2（必需权限）+ S8（ADD/REMOVE 事件） |
| Q7 | zoom 时显示的是什么？ | 窗口的**静态截图图层**，不是实时录屏；`PICTURES` 日志显示 21 窗约 354.8 MB 常驻缓存，桌面壁纸另存。 | 高 | S1 S8 S9 |
| Q8 | 布局如何持久化？ | 按 `<display-UUID>\|desktop-1` 分文件，`version: 2`；`layout-*.json` 带 seat 指纹，`arrangement-*.json` 是轻量版，`departures.json` 存历史模板用于窗口归位。 | 高 | S7 |
| Q9 | 关闭后窗口怎么「回来」？ | seat 指纹（titles/tokens/document/session/pid/bundleID）+ `departures.templates` 匹配；日志有 `GHOST / RESTORE / ADOPT / PUT BACK / MATCH` 事件链。 | 高（机制）/ 未知（算法权重） | S7 S8 |
| Q10 | 动画时长真是 460ms？ | 是，但只对**完整** layout motion。`SETTLED` 样本中位数 460.0ms、约半数落在 450–479ms；全样本均值约 366ms，因一批 <100ms 的中断/快速路径被拉低。早期「均值 460」的写法已纠正。样本数随日志增长，见 `runtime-events.json`。完整 landing 约 1128 ms，120Hz 下 0 dropped frames。 | 高 | S1 S8 |
| Q11 | 命令集有多大？ | 15 条 URL 命令、12 行主快捷键、8 个 settings pane；Free 限 5 个 docked 窗口。 | 高 | S2 |
| Q12 | 有哪些第三方依赖？ | 只有内嵌 `Sparkle.framework`。其余是系统框架（AppKit / ScreenCaptureKit / QuartzCore / AX）。 | 高 | S4（bundle 文件清单） |
| Q13 | dock 到边时选「新建 split」还是「并入既有 split」？ | **未确定**。guide 只描述「邻居让位」的结果，本机无成对前后快照。实现采用「命中边 → 在该方向新建/扩展 split，权重由现有 siblings 等比让出」，作为可替换策略。 | 低（推断） | S2 S7 |
| Q14 | seat 哈希算法？ | **未知**。`mirrorDigest` / `saltDigest` 存在但算法不可见。实现以协议 `SeatMatcher` 抽象，不伪造等价性。 | 未知 | S7 |
| Q15 | 许可 / 激活协议？ | **不调查、不实现**。属于 craft-anything 明确排除的 DRM / licensing 绕过边界。 | — | S10 |
| Q16 | `framed: "desktop"` 到底是「缩到最外」还是「单独 frame Desktop」？ | **无法从现有样本区分**。本机 `layout-*.json` 里该值出现时 `doc.root` 恰好也是 desktop 叶子（全浮动），两种读法重合；guide 的 `frame-desktop` = "The Desktop on its own" 支持后者。早期结论「表示缩到最外」已降级为推断。实现采用 `everything → root.id`、`frame-desktop → "desktop"` 的自洽约定，并在全浮动时让二者自然重合。 | 低（歧义） | S2 S7 |

## 已纠正的过度断言

| 处 | 原结论 | 纠正后 | 触发 |
|---|---|---|---|
| 460ms 动画 | 「实测 461/464 ms，与标称吻合」（隐含均值 460） | 98 个 `SETTLED` 样本中位数 460.0ms、主模态 50 个在 450–479ms，但均值 365.0ms（21 个 <100ms 中断/快速路径）。460 是完整 motion 的**主模态** | Check C08 首次 FAIL |
| `framed: "desktop"` | 「表示相机缩到最外」 | 与「单独 frame Desktop」在数据上不可分，降为推断并标注实现约定 | 模拟器首屏渲染暴露 |
| `offered` 条目数 | 43 | 实测 33 | 复核 `release-defaults.json` |
| 日志行数 / appMinimums | 写死计数 | 改为「采集时点数，随运行增长，以 `runtime-events.json` / `defaults read` 为准」，不再写死 | 重采证据 |

## 未解决问题（进 inbox）

- 手势阈值、easing 曲线参数、图片缓存淘汰策略、多显示器 Space 私有 API —— 均标 `UNSPECIFIED`。
- 若日后需要提高 Q13 置信度，唯一正当做法是在**用户自己机器上**做行为采样：dock 前后各导出一次 `layout-*.json`，比对树差异；不需要读内部代码。
- 若要消解 Q16，需要一份 **root 不是 desktop 叶子**的布局文档且同时记录相机状态（例如 dock 一个窗口后立刻导出 `layout-*.json`），比对 `framed` 值；同样不需要读内部代码。

# Coverage & traceability — Check 阶段

结论：**READY**，14/14 Check 通过（`checks/CHECKS.md` / `checks/report.json`）。
覆盖指「规格的每一条可追溯到证据，并在至少一套实现里被验证」，**不指**功能等价或产品完整度。

## 1. 证据层覆盖

| 层 | 采集文件 | 覆盖内容 | 置信度 | 是否进入规格 |
|---|---|---|---|---|
| L1 公开文档 | `commands.json`、evidence.md §2.1/2.6 | 产品定位、15 命令、12 快捷键、权限、Free/Pro、平台、版本史 | 高 | 全部 |
| L2 bundle 元数据 | `info-plist.json`、`release-defaults.json` | bundle ID / build / LSUIElement / URL scheme、47 默认值、33 offered | 高 | 全部（本地化文案**不进入**） |
| L3 持久化文档 | `layout-schema.json`、`layout-sample.json` | 树文法、7 不变量、真实嵌套形状、权重、seat 字段 | 高（结构性） | 全部 |
| L4 运行日志 | `runtime-events.json` | 23 种事件词汇、状态迁移、SETTLED 分布、PICTURES 缓存证据 | 高（事实）/ 中（推论） | 事件与时长进入；机制推论标注 |
| L5 符号名 | `symbols.json` | 类型名、AX / ScreenCaptureKit 术语 | **低** | 仅命名参考，需 L1/L3/L4 二次印证 |

## 2. 追溯矩阵

| 规格条目 | 证据 | Swift 实现 | JS 实现 | 验证 | 置信度 |
|---|---|---|---|---|---|
| 三类节点 + 递归嵌套 | S7（真实模板 depth ≥3） | `LayoutNode.swift` | `split/panel/desktop` + `flatten` | XCTest ×4、JS 自检 ×4、C06/C07 | 高 |
| 权重归一化 / 几何分配 | S7 | `LayoutEngine.rects` | `rects()` | 单测 + JS「sibling 不重叠」 | 高 |
| desktop 恒定唯一叶子 | S2 S7 | `validate()` 保护 | `validate()` + `insertPanel` 特殊分支 | 单测 + JS「desktop protected」 | 高 |
| tab group = `views > 1` | S7 | `Panel.isTabGroup` | `panel()` 的 `tabbed` + 渲染 tab strip | 单测 + 模拟器 Notes 双 tab | 高 |
| dock / remove / gap resize | S2（行为描述）+ S7（树文法） | `LayoutEngine` 三操作 | 同名三函数 | 单测 ×6 + JS 自检 ×4 | 中（启发式是推断，见 Q13） |
| 相机层级 / back-forward | S2 S7 | `Camera.swift` | `applyCamera()` | 单测 + JS 自检 ×4 | 高 |
| saved views 1–9 | S2 | `CameraState.savedViews` | `saved` + 9 槽 UI | 单测 + JS「save→go」 | 高 |
| 15 条 URL 命令 | S2 逐字 | `CommandURL.parse` | `parseURL` | 单测 + JS 自检 ×6 + C01/C02 | 高 |
| 8 settings pane | S2 | `SettingsPane` | SPEC.panes | C03 | 高 |
| 47 发布默认键 | S5 | `Settings` 47 属性 | SPEC.settings_keys | 单测（Mirror keyCount）+ C04 | 高 |
| 12 行快捷键 | S2 逐字 | —（由命令层驱动） | SPEC.shortcuts + `keydown` | C05 | 高 |
| 460ms 典型 motion | S1 + S8 中位数 | — | CSS transition 460ms | C08（中位数 / 主模态） | 高（已纠正口径） |
| AX 移动窗口 | S2 权限 + S9 + S8 事件 | `WindowSystem.swift` 只读封装 | 不涉及 | `trellis-probe --live` 实跑 | 高（机制）/ 未实现写操作 |
| 静态截图图层 | S1 + S8 PICTURES + S9 | 不实现 | 不实现 | — | 高（结论）/ 明确排除 |
| seat 指纹哈希 / 匹配权重 | S7（字段可见） | `SeatMatcher` 协议 + `SimpleSeatMatcher` | 不涉及 | 无 | **未知，协议占位** |
| 许可 / 激活 | — | 不实现 | 不实现 | — | **不调查** |

## 3. 量化覆盖

| 面 | 覆盖 |
|---|---|
| URL 命令 | 15 / 15 |
| settings pane | 8 / 8 |
| 发布默认值 | 47 / 47 |
| 快捷键行 | 12 / 12 |
| 布局节点类型 | 3 / 3 |
| 文档不变量 | 7 / 7 |
| 自动检查 | 14 / 14 PASS |
| Swift 单测 | 18 / 18 |
| JS 页面自检 | 24 / 24 |
| 无头渲染 | 6 个窗口节点 + Desktop 层实渲染通过 |

## 4. 明确不覆盖（UNSPECIFIED）

手势阈值与滤波、pinch→zoom 连续映射、动画 easing 曲线、窗口指纹哈希、静态截图缓存淘汰、多显示器 Space 私有 API、许可协议、Sparkle 更新与签名、完整 AppKit UI 与静态截图管线。

这些不是「遗漏」，是**证据不足以正当断言**的部分。实现中用可替换默认或协议占位，不宣称等价。清单与提高置信度的正当做法见 `inbox/unspecified.md`。

## 5. 本阶段纠正

| 处 | 原结论 | 纠正 |
|---|---|---|
| 460ms | 均值与标称吻合（只挑了 461/464ms 两条） | 中位数 460.0ms / 主模态约半数在 450–479ms；均值约 366ms，被 <100ms 中断路径拉低 |
| `framed:"desktop"` | 表示缩到最外 | 与「单独 frame Desktop」在全浮动样本里不可分，降为歧义（Q16） |
| offered 条目 | 43 | 33 |
| 运行时计数 | 写死日志行数 / appMinimums 数 | 改为指向 `runtime-events.json`，不写死 |

## 6. 复现

```bash
cd trelliswm-reverse
/usr/bin/python3 checks/collect_evidence.py
/usr/bin/python3 checks/check_evidence.py --headless
cd app && /usr/bin/swift test --disable-sandbox
```

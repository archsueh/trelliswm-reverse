# Inbox — 未解决 / 明确不实现

Craft Anything 的 Ready 阶段要求把 limitations 显式留下，而不是用猜测填满。以下条目**没有可见证据**，实现里分别用了「可替换默认」或「协议占位」，都不宣称与原品等价。

## A. 证据不足，但可在用户自己机器上正当补采

| # | 问题 | 当前处理 | 提高置信度的**唯一正当做法** |
|---|---|---|---|
| A1 | dock 到某条边时，何时新建 split、何时并入既有 split（Q13） | 同轴插为兄弟并让出一半权重；异轴包一层；根叶子建新根 | 在 dock 前后各导出一次 `layout-*.json`，比对 `doc.root` 树差异；连做 5–10 组不同方向/层级，归纳启发式。**不需要读内部代码** |
| A2 | `framed:"desktop"` 的两种读法（Q16） | 实现约定：`everything → root.id`，`frame-desktop → "desktop"` | 取一份 **root 不是 desktop 叶子**的布局（先 dock 一个窗口），分别触发 `everything` / `frame-desktop` 后立刻导出，比对 `framed` 值 |
| A3 | pinch / pan 到 zoom level 的连续映射、手势阈值与滤波 | 模拟器只实现离散层级 step | 在公开 guide 允许范围内做输入→屏幕结果的行为采样；无公开参数则保持 `UNSPECIFIED` |
| A4 | 动画 easing 曲线（`CameraCurve` / `LayoutTween` 只有名字） | CSS 用固定 460ms cubic-bezier | 逐帧录制一次 landing，拟合位移曲线；属于可选 polish，不影响规格正确性 |

## B. 字段可见、算法不可见

| # | 问题 | 当前处理 |
|---|---|---|
| B1 | seat 指纹哈希（`mirrorDigest` / `saltDigest`）与匹配权重 | `SeatMatcher` 协议 + 一个显然不等价的 `SimpleSeatMatcher` 兜底。字段清单在 `capture/layout-schema.json` |
| B2 | 静态截图缓存淘汰策略 | 不实现。只保留 L4 中「约每 5 分钟报一次缓存体积」这一事实 |
| B3 | 多显示器 / macOS Space 的私有 API 用法 | 不实现。只保留 `world = <display-UUID>\|desktop-1` 这一持久化命名事实 |

## C. 边界内明确排除（不做，也不调查）

- 许可、试用、激活协议（craft-anything 明确排除的 DRM / licensing 绕过）。
- 反汇编 / 反编译 / Ghidra / 注入 / 私有符号恢复。
- 复制 497 条本地化文案、`AppIcon.icns`、`MenuBarIcon.svg`、`Lessons/` 资源。
- 复用产品名、bundle ID `app.trellisui.trelliswm` 或 URL scheme 的归属标识作为本实现的注册值。
- 触碰正在运行的 TrellisWM 的窗口；`trellis-probe --live` 只做 AX 只读枚举。

## D. 把 `app/` 推成真正可运行的窗口管理器

**v0.1 已做**（2026-11-13）：独立菜单栏代理 `Trellis WM.app`（bundle id `app.trellisreverse.wm`，`LSUIElement`）；Accessibility 授权检测与引导；主屏 `AXStandardWindow` 枚举与过滤；把窗口映射进 `TrellisCore` 布局并 `setFrame`（12pt 间隙 + `visibleFrame`）；每应用 `AXObserver` + `NSWorkspace` 启动/退出通知（去抖重排）；Carbon 全局快捷键（焦点、交换、分屏方向、比例、重排、开关平铺）；菜单开关 / 立刻重排 / 权限状态 / 退出。未授权或原品 TrellisWM 仍在运行时不会移动窗口。构建见 `installer/build_wm.sh`。

**仍缺，列为后续：** ScreenCaptureKit 静态截图 / 总览、tab strip / gap handle 的自绘 `NSWindow`、多显示器与 Space 绑定、Developer ID 签名与公证、Sparkle 之外的更新策略、把原品相机 / saved views / URL 命令接到真实窗口。这些仍是工程实现缺口，不是规格未知项。

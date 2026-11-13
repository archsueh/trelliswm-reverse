# Trellis WM 0.1.0 — 安装与使用

这是独立实现的菜单栏窗口管理器（bundle id `app.trellisreverse.wm`），用 clean-room 的 `TrellisCore` 布局引擎给真实窗口排版。与 TrellisWM 及其作者无关联、未获背书，也不是原品的替代或复刻。

它和可视化工作台 `Trellis Reverse.app`（`app.trellisreverse.studio`）是两个不同的 app，可以同时安装。

## 先停掉原品

同一台机器上不要同时跑两个窗口管理器。使用本 app 的平铺前，请先退出 `/Applications/TrellisWM.app`（菜单栏图标 → Quit）。本 app 若检测到原品仍在运行，会拒绝开启平铺。

## 安装

在仓库里：

```
cd installer
./build_wm.sh --install
```

会把 ad-hoc 签名的 `Trellis WM.app` 装到 `/Applications/Trellis WM.app`。也可以先不带 `--install`，再把 `.dist/wm/Trellis WM.app` 拖进「应用程序」。

系统要求：macOS 14+ · Apple Silicon。签名是 ad-hoc，没有 Developer ID、没有公证。若 Gatekeeper 提示无法验证开发者：右键打开，或：

```
xattr -d com.apple.quarantine "/Applications/Trellis WM.app"
```

## 第一次使用

1. 退出原品 TrellisWM。
2. 打开「Trellis WM」。菜单栏会出现一个三分栏图标（或文字 `WM`）。
3. 点菜单里的 **Grant Accessibility…**，在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 **Trellis WM**。首次授权后可能需要再开一次 app。
4. 在未授权之前，本 app **不会移动任何窗口**。默认平铺是关闭的。
5. 授权后，点 **Enable Tiling**，或按 `⌃⌥⌘T`。当前主屏上的普通标准窗口会被排进带 12pt 间隙的平铺布局（避开菜单栏和 Dock）。关闭平铺（菜单或再按一次同一快捷键）会把窗口放回开启前的位置；退出 app 时同样会还原。期间关掉的窗口会被跳过。若某个 app 有最小宽度（例如访达、微信）导致格子被钳制，相邻窗口会让出空间并保持 12pt 间隙，而不是互相重叠；若最小尺寸加间隙已经超出可见区域，窗口从左边起依次排开，允许伸出右缘，仍不重叠。

卸载：把 `/Applications/Trellis WM.app` 拖到废纸篓。偏好只写了 `tilingEnabled` 这一项，可用 `defaults delete app.trellisreverse.wm` 清掉。

## 默认快捷键

前缀一律是 **Control + Option + Command**，避开常见 macOS 快捷键，也避开原品 TrellisWM 的 `⌃⌥` 映射。

| 动作 | 快捷键 |
|---|---|
| 焦点下一个 / 上一个窗口 | `⌃⌥⌘J` / `⌃⌥⌘K` |
| 与下一个 / 上一个窗口交换位置 | `⌃⌥⌘⇧J` / `⌃⌥⌘⇧K` |
| 切换当前分屏方向（横 / 竖） | `⌃⌥⌘O` |
| 放大 / 缩小当前格子比例 | `⌃⌥⌘=` / `⌃⌥⌘-` |
| 立刻重新平铺 | `⌃⌥⌘R` |
| 打开 / 关闭平铺 | `⌃⌥⌘T` |

菜单里也有 Enable/Disable Tiling、Retile Now、权限状态和 Quit。

## v0.1 明确不做的事

多显示器与 Space、ScreenCaptureKit 总览、tab strip、缺口拖动手柄、相机式 zoom / saved views、公证与自动更新。这些会列为后续工作，不在本版承诺范围内。

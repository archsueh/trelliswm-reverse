# Trellis Reverse 1.0.0 — 安装说明

## 先说清楚：这是什么，不是什么

这是把之前的 TrellisWM clean-room 规格研究**打包成可双击的 macOS 原生 app**。

- **是**：一个用逆推出的 `TrellisCore` 布局引擎做的可视化工作台。可以看到递归 split 树、相机 frame / step in / step out / back / forward / saved views、15 条 URL 命令，并内嵌交互模拟器、CLI 探针、完整源码与证据台账。
- **不是**：窗口管理器，**不是 TrellisWM 的替代品或复刻版**。它不注册 `trelliswm://`、不请求辅助功能权限、不读取或修改任何真实窗口。README 第 5 节列出的 UNSPECIFIED 项（手势、动画 easing、窗口指纹哈希、静态截图管线等）依然未实现。

与 TrellisWM 及其作者**无关联、未获背书**。未复制原品任何源码、图标、壁纸或本地化文案。详见 `NOTICE.md`。

## 安装

**方式 A（DMG，标准拖拽）**：打开 `TrellisReverse-1.0.0.dmg`，把 `Trellis Reverse.app` 拖进 `Applications` 快捷方式。

**方式 B（pkg，双击安装器）**：打开 `TrellisReverse-1.0.0.pkg`，按提示安装到 `/Applications`。

系统要求：**macOS 14.0+ · Apple Silicon**（本机编译目标 arm64-apple-macosx）。

### 签名与首次打开

本包使用 **ad-hoc 自签名**，没有 Apple Developer ID 签名、没有公证（notarization）。所以：

- 从本机生成的 DMG 直接拖出来通常可以直接双击打开。
- 如果通过 AirDrop / 网络传输，Gatekeeper 会提示"无法验证开发者"。此时**右键点击 app → 打开 → 再点一次「打开」**，或执行：
  ```
  xattr -d com.apple.quarantine "/Applications/Trellis Reverse.app"
  ```
- 这是无付费开发者账号时的正常状态，不是文件损坏。`校验信息.txt` 里有 SHA-256 可核对完整性。

不需要授予「辅助功能」「屏幕录制」或任何隐私权限 —— app 只读自己 bundle 内的资源。

## 包里有什么

```
Trellis Reverse.app/Contents/
├── MacOS/
│   ├── TrellisStudio          原生 AppKit 工作台（双击运行）
│   └── trellis-probe          CLI 探针：--help / --commands / --live / --menubar
├── Info.plist                 自己的 bundle id：app.trellisreverse.studio
├── Resources/
│   ├── AppIcon.icns           由 installer/make_icon.py 生成，纯代码绘制
│   ├── Simulator/index.html   交互模拟器（自包含单文件，JS 自检 24/24）
│   ├── Source/                完整工程：app/ 源码、capture/ 证据、checks/、
│   │                          investigation.cany/、inbox/、README、NOTICE、craft.json
│   └── Docs/                  README.md、NOTICE.md
└── _CodeSignature/            ad-hoc 签名
```

DMG 里另有 `TrellisReverse-源码与证据.zip`，内容与 `Resources/Source` 一致，方便不解包 app 直接查看。

## 用起来

启动后：

- 点画布上任意窗口块 → frame 该节点；再点同一个 → 退回全景。
- 顶部按钮／「命令」菜单 → 15 条命令；URL 输入框可直接敲 `trellisprobe://zoom-in` 之类。
- 「文件」菜单 → 打开内嵌交互模拟器、在 Finder 显示源码、导出当前布局 JSON。
- 动效时长 0.46s，取自 `capture/runtime-events.json` 里 SETTLED 的观测中位数（不是均值）。
- 画布 tile 间隙为 **6pt**（显示偏好，窗口尺寸下比 12pt 更紧凑）。采集到的原品发布默认 `Settings.release.gap = 12` 作为证据保留，CLI 与内嵌模拟器仍按 12pt 建模；状态栏同时标注两者，不会把显示偏好混进规格。

## 复现构建

```
cd <repo>/installer
./build_app.sh --install
```

脚本会：release 编译 → 生成 iconset/icns → 组装 .app → ad-hoc 签名 → 打 DMG + pkg → 输出到 `~/Downloads` 并可装到 `/Applications`。全部产物在 `.dist/`（已 gitignore）。

**已知的本机构建日志噪声**：本机执行 `pkgbuild` 时会输出 4 行 `write: Permission denied`。已单独复现定位：来自 `pkgbuild` 自身的内部写操作，与 app 内容无关（清空所有扩展属性后仍复现；单独跑 `hdiutil create`、`codesign`、`swift build` 均无此输出），属于当前执行环境对某些写路径的限制。pkg 仍成功生成、payload 完整，可用 `pkgutil --payload-files <pkg>` 核对。这不是安装失败。

## 卸载

把 `/Applications/Trellis Reverse.app` 拖到废纸篓即可。app 不在 `~/Library` 写任何数据（只有窗口位置由系统 `NSWindow` 自动保存，可用 `defaults delete app.trellisreverse.studio` 清除）。

## 验证状态

Swift 单测 18/18 · Check 14/14 READY · JS 自检 24/24。证据、置信度与已纠正的过度断言见 `README.md` / `investigation.cany/questions.md`。

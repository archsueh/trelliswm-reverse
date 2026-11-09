# Check 阶段报告 — TrellisWM clean-room study

采集对象：`/Applications/TrellisWM.app` 0.10.0 (560) · 结论：**READY** · 14/14 PASS，0 FAIL，0 WARN

| ID | 检查项 | 结果 | 实测 |
|---|---|---|---|
| C01 | 15 URL commands: evidence == JS spec | **PASS** | evidence 15 / spec 15 |
| C02 | Swift parser covers every command | **PASS** | Swift switch cases 15, expected 15 |
| C03 | 8 settings panes: evidence == spec == Swift | **PASS** | evidence 8 / spec 8 / Swift 8 |
| C04 | 47 release keys: evidence == spec == Swift | **PASS** | evidence 47 / spec 47 / Swift 47 |
| C05 | Shortcuts quoted verbatim from guide | **PASS** | 12 rows, spec 12 |
| C06 | Layout grammar covers all observed node kinds | **PASS** | observed kinds ['desktop', 'panel', 'split']; nesting depth from real templates >= 3 |
| C07 | Document invariants carried into spec | **PASS** | 7 invariants; weights-sum and desktop-leaf rules present |
| C08 | 460ms budget matches measured median / mode | **PASS** | SETTLED median 460.0 ms, mean 365.9 ms, n=99, nominal 460 ms, modal band 450-479 has 51 |
| C09 | Runtime event vocabulary captured | **PASS** | 23 tags across 1468 log lines |
| C10 | No subject artwork / resources in implementation | **PASS** | clean |
| C11 | Craft Anything project skeleton complete | **PASS** | 17 artifacts present |
| C12 | XCTest suite exercises core invariants | **PASS** | 18 test methods |
| C13 | swift test --disable-sandbox | **PASS** | 18 tests, 0 failures |
| C14 | Simulator boots and self-tests in a real browser | **PASS** | selftest PASS 24/24, 6 window nodes rendered |

## 覆盖

| 面 | 覆盖 | 说明 |
|---|---|---|
| URL 命令 | 15/15 | 名称与查询参数逐字取自公开 guide，Swift / JS 双实现都可解析 |
| settings pane | 8/8 | 三处注册表一致 |
| 发布默认值 | 47/47 | ReleaseSettings.json / Swift Settings / JS spec 键集合相同 |
| 快捷键 | 12/12 | 逐字引用；UI 表列出 10 行键盘项，手势 2 行在 guide 内 |
| 布局文法 | 3/3 节点类型 + 7 不变量 | 来自本机持久化文档，非猜测 |
| 单测 | Swift XCTest 全绿 + JS 页面自检 | 两套独立实现互相印证 |

## 明确不覆盖（UNSPECIFIED，非遗漏而是无证据）

手势阈值与滤波、pinch→zoom 连续映射、动画 easing 曲线、窗口指纹哈希与匹配权重、
静态截图缓存淘汰、多显示器 Space 私有 API、许可校验协议。
实现中分别以可替换默认或协议占位，不宣称等价。详见 `capture/evidence.md` §3、
`investigation.cany/questions.md` Q13–Q15。

## 复现

```bash
cd trelliswm-reverse
/usr/bin/python3 checks/collect_evidence.py        # 只读重采证据
/usr/bin/python3 checks/check_evidence.py --headless
cd app && /usr/bin/swift test --disable-sandbox
```

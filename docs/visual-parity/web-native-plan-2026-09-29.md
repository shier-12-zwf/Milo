# Web 参考与 iOS 原生视觉迭代 · 2026-09-29

用户最新授权：继续开发测试；直接访问 Web 端并截图对照，不启动鸿蒙 App；全部开发和过程产物只放当前 `/Users/hut/Projects/milo`；清理旧并列工作目录；更新并合并 PR；页面、星空和点击动效要还原，返回及主要按钮按 iOS 习惯优化。

## 工作区与历史

两份旧 worktree 已移除，当前项目直接使用 `codex/ios-specdrive-pilot`。旧运行、原图和不相同的旧源文件经 SHA-256 逐文件核对，归档至 `.artifacts/ios/history-before-consolidation-2026-09-29.tar.gz`；清理记录保存原路径映射。所有原有 Web、鸿蒙、网关修改保持原字节，不加入本次 iOS 提交。历史状态没有清零或改写。

## 参考、实现与范围

1. 参考 `https://milo.huangtangai.top/app` 的实际浏览器界面，390×844 逻辑视口；保存原始截图、URL、日期、实际尺寸和逐页操作。站点首页宣传场景不代替 `/app` 产品。读取当前 Web 星空 GLSL 和 settings，与线上画面核对。仅合成测试内容；不清除浏览器已有日记。
2. iOS 使用 SwiftUI/Metal 实现 Web 的六层星尘、聚簇、闪烁、旋转/景深和指针排斥。同一参数与数学函数保留来源，触摸回馈覆盖页面空白和真实控件，不吞掉按钮、输入或滚动。降低动态效果/后台暂停需真实验证；静态夹具冻结与运动测试明确分开。
3. 使用 SF Symbols 的返回 chevron、原生材质、44pt 触摸目标和清楚的按压反馈；主要操作保持品牌色，文字按系统字号增长、禁用态明确。保持原有页面、语义与两条离线旅程。
4. 修复真实模板双向切换后的排版，保持选择区可见，验证两列、标题、预览及底栏在切换前后均无重叠；不能仅测初始模板夹具。使用明确有界的模板预览/标签布局。
5. 修复 DEBUG 滚动标记被父容器覆盖；53 个原有 iOS 状态全部保留，分为独立测试，单例失败不阻断其他状态取证。键盘和嵌套编辑器分别测量、逐段重叠直至实际末尾；未证实覆盖仍失败。
6. 新 Web 对照账本区分共享产品状态、Web 没有的 iOS 账号/系统状态、最大字号压力状态。共享状态必须实际 Web/iOS 原图及独立审查；额外原生状态仍需 iOS 实测，不能伪造 Web 参考。旧 Harmony 53 组账本和失败记录保留为历史，不能换标题冒充本轮通过。

## 验证与交付

- 保留31项核心、26项协调器、24项旧验证器回归和11条现有原生旅程；新增真实模板切换后几何、原生控件和动态星空触摸/降低动态效果检查。
- 实际 build-for-testing → test-without-building，代码变化使既有证据失效。日志、截图、浏览器素材、新报告只在项目内。
- 新阶段因用户变更参考平台、限定工作区、明确要求着色器动效和 iOS 控件而成立；不重开旧同义阶段来隐藏失败。新阶段每项至多3次执行、同输入连续无进展2次止，活跃执行至多90分钟（完整53状态和动态附加测试需要比之前单纯布局修复更长）。先独立计划审查，再实施和最终原图审查。
- 用户已明确授权更新和合并 PR；代码与视觉验证通过后合并当前功能迭代。真实AGC、实体手机、签名及商店发布仍分开列明，合并源码不代表发布或这些外部验证通过。
- 不为了合并删除失败检查；CI若因环境/外部未配置失败，保留并解释，先修本次功能范围内的失败。不修改用户的 Web/鸿蒙/网关未提交内容来修 CI。

## Review amendment: normative phase acceptance

`docs/visual-parity/web-cases.json` explicitly maps all original 53 IDs to shared, native-only, or accessibility-stress. This mapping and this section supersede historical Harmony runtime provenance and Harmony/iOS pairing requirements FOR THIS PHASE ONLY. Historical failures remain unchanged. Shared cases require actual Web URL, UTC capture time, 390x844 viewport, pixel size, action trace, original screenshot SHA-256, paired equivalent iOS content and current source fingerprint. Missing or unreachable browser captures BLOCK that case; source inspection, synthetic renders and neighboring screens cannot replace them. Continuous overlapping captures cover all overflow. Native-only cases (account/configuration and unavailable missing-record/busy states) require actual native screenshots, state assertions and independent review. Stress cases require largest iOS accessibility size, continuous scrolling coverage and usable controls. The reviewer must inspect content, hierarchy, stars/planet, spacing, type, unobscured content and button targets; native control differences require explicit recorded acceptance. No final visual completion claim until all entries pass.

## Review amendment: temporal evidence contract

Motion tests disable static fixture freezing. Evidence records source/build SHA, launch arguments, device/OS, timestamps and original video or successive frames. Capture at least three natural animation times on live Web and iOS; independently review rotation direction, layers, density, twinkle and apparent speed. Record before/during/after blank-area touch, real primary-control touch and mood change, holding at least 0.5 seconds. Repulsion must center on touch and smoothly recover, with no screen flash; navigation/selection must occur exactly once. Drag a long page: content must scroll while touch feedback does not consume the gesture; text entry must remain usable. With Reduce Motion enabled, natural animation and touch deformation stop while controls work. During at least two seconds inactive, animation time must not advance; returning must resume without a jump. DEBUG counters support original frames/video but never replace them. Missing lifecycle/Reduce Motion execution remains unpassed. Independent final review must inspect original temporal evidence, not only summary/static contact sheets.

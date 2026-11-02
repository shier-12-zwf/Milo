# iOS 登录、账号与设置功能清单 · 2026-09-30

本清单基于当前鸿蒙和 iOS 源码独立核查；未启动鸿蒙 App，未操作模拟器或验证远程服务。范围只包括登录、账号、AI 设置及其会话接线，不代表整款产品已经完成视觉或真机验收。

| 功能 | 鸿蒙源码依据 | iOS 状态与本次变化 | 仍需实际验证 |
| --- | --- | --- | --- |
| 首次登录及正常入口 | `features/auth/LoginScreen.ets`；`pages/Index.ets` 的登录门禁 | 已有验证码/密码/忘记密码页面，`JournalView.swift` 登录门禁和 `HomeView.swift`「我的」入口均存在；本次从正常入口验证，不依赖已登录截图夹具 | 干净安装首屏、正常进入及重启恢复的 UI 原图 |
| 邮箱验证码登录/自动注册、密码登录 | `AuthController.ets:129–253`，真实 AGC provider | 本次新增 `AGCAuthProvider.swift`，接官方固定版本 SDK；仅明确 UserNotRegistered 错误触发注册，错误验证码或网络失败不自动注册 | 匹配 iOS 包标识的配置、真实邮箱验证码、登录和注册服务结果；注入 provider 测试不等于真实服务通过 |
| 找回密码 | `AuthController.ets:256–283`；`LoginScreen.ets:136–156` | 本次把重置和登录拆开；密码已改但登录失败时提示准确状态、回到密码登录并丢弃已消费验证码 | 实际服务的部分成功情形尚未验证；模型注入测试覆盖不代表服务复现 |
| 密码显隐及旧错误清除 | `LoginScreen.ets:269–328` | 本次新增 `MiloSecureField.swift`，登录和账号新密码可显隐；用户编辑验证码/密码会清除旧反馈 | 实际字段编辑、显隐、自动填充及键盘体验 |
| 本地 owner 入口 | `AuthController.ets` 的 milo 分支 | 原有 `milo` 本地身份保留，无网络依赖；这是明确的本地入口，不是远程认证后备成功 | 普通登录→账号→设置→退出流程 |
| 账号密码管理 | `AccountScreen.ets:171–205` | 原有绑定邮箱、验证码、新密码/确认表单；本次接真实 provider 并补显隐。两端本地 owner 都刻意隐藏远程密码管理 | 真实邮箱账号改密及失败保留 |
| 退出登录与本机数据 | `AuthController.ets:294–306` | 本次允许远程清理失败时退出本机，保留日记和草稿；本机会话删除失败仍报错。鸿蒙当前也有远程失败阻止本地退出的顺序，故这是韧性改进，不能说鸿蒙已支持 | 真实普通退出、重启、保留数据；注入测试覆盖离线远程失败，本机文件删除失败尚缺专门执行证据 |
| 注销账号 | `AccountScreen.ets:121`；`AuthController.ets:354` | 已有确认和远端先行、本机随后删除；本次增加 account-deletion.json 记录已完成远端删除，支持本机清理失败后重启补做，避免再次要求已删除的远程会话 | 真实服务注销及本机清理；checkpoint 写入成功后的重试有注入测试，写入前崩溃不应宣称已验证 |
| 头像与恢复星球头像 | `AccountScreen.ets:39,157–166` | `AccountView.swift:89–110` 已有照片选择和恢复；`AccountModel.swift` 原有图像解码、体积限制、受保护本机存储 | 本轮未重新进行实际照片选择/存储失败测试；不列为新增页面 |
| JSON / Markdown 导出 | `AccountScreen.ets:48,218` | `AccountView.swift` 已有两种导出及原生分享；导出内容来自日记，不包含账号密码/API Key | 实际分享、文件内容及取消路径；本轮源码清单不替代已有/后续运行证据 |
| AI 总开关默认值 | `Index.ets:154–158,285–292` | 本次 `JournalModel.swift` 新建回忆读取账号设置；恢复草稿保留其明确选择；保存设置同步当前会话，取消旧请求并拒绝迟到写回 | 当前源版本协调器测试和真实保存/重启 UI 证据 |
| 五种个人模型预设 | `core/config/UserAiSettings.ets:10–15`；`AiSettingsScreen.ets:98` | `AIConnection.swift` 已有 DeepSeek、通义千问、Kimi、MiniMax、自定义，预设列表与鸿蒙一致 | 不把预设存在等同于每个厂商实际连通 |
| URL / Key / 同意 / 账号隔离 | `AiSettingsScreen.ets:45–52,109–126`；`Index.ets:103–124` | 已有 HTTPS 地址校验、Keychain 按账号和目的地址绑定、地址改变重获同意、删除 Key；本次保留这些边界 | 实际 Keychain 错误、服务连接及新配置请求；无真实 Key 时明确未验证 |
| 个人模型连接测试 | `AiSettingsScreen.ets:68,125` | `AISettingsView.swift` 和 `AccountModel.testConnection` 已有真实个人接口请求，不是假成功 | 真实用户配置/网络服务响应，本轮未由审查员发送请求 |
| MILO 默认/托管模型 | `AiSettingsScreen.ets:141` 按配置判断；`Index.ets:103–115` 创建 hosted adapter | 仍有源码能力差异：iOS 明确硬编码此安装包后台未接通；鸿蒙具备可配置 adapter，但当前网关地址同样为空。这一差异未在本轮声称修复 | 实际托管配置、隐私同意、网关接线和服务调用，作为未满足能力保留 |
| 会员说明 / 订阅 | `AiSettingsScreen.ets:148–154` | 两端已有规划价和额度说明，订阅按钮禁用；无实际支付/权益服务，不新增付费功能 | 只核查说明诚实，无购买能力或支付验证声明 |

源码路径前缀：鸿蒙 `apps/harmony/entry/src/main/ets/`；iOS `apps/ios/App/`。表内行号为核查时定位，实施后可能移动。

已有页面不等于真实服务已接通；已登录截图可能来自持久化身份或 DEBUG 截图夹具，不能证明登录页面缺失，也不能证明用户完成过远程登录。本次源代码审查见 `ios-functional-code-review-2026-09-30.json`；计划审查见 `ios-functional-plan-review-2026-09-30.json`。

第二次完整构建通过、36 项协调器检查通过为协调者当前报告，本文不把该报告改写成审查员自行执行的结果。后续应分别补充当前运行日志、真实截图、远程服务和真机结果。旧阶段 51/53 截图、8/11 操作以及旧包动效证据的未通过状态保持原样。

# 鸿蒙本地验证 · 2026-09-14

本轮调整分享卡片、短对话引导与登录体验。原则：应用一次只给一个短提示，让用户决定说多少、何时保存。

## 已修改

- 两种卡片统一 Canvas 字体与坐标单位，放大正文、日期与情绪标签；修正换行测量、预览宽度和图片导出比例；补齐模板选择的存储与恢复。
- 修复保存图片按钮的文字对比度和通用主按钮的圆角裁切。
- 离线提示缩为一句，用户表示不想继续时停止追问；AI 提示与客户端回复限制为短句。
- 修复聊天上下文丢失、MiniMax assistant 角色映射；解除三轮后锁定输入。
- 多行输入、键盘避让；实时保存对话、未发送文字和 AI 开关，重启可恢复。
- 关闭 AI 时日记只整理用户原话，重启后仍尊重开关；不额外编造情绪或结论。
- 简化邮箱验证码／密码登录，增加重发倒计时，修复重发失败和密码重置后的状态恢复。

## 自动验证

| 检查 | 结果 |
| --- | --- |
| `cd apps/harmony && ./hvigorw test` | 157 项通过，0 失败 |
| `cd apps/harmony && ./hvigorw assembleHap` | 成功生成签名调试 HAP |
| DevEco Node 运行 `apps/harmony/tests/shell-contract.test.mjs` | 3 项通过 |
| `npm -w services/ai-gateway test` | 19 项通过 |
| `npm -w services/ai-gateway run build` | 通过 |
| `npm test` | 133 项通过 |
| `npm run build` | 通过 |
| `npm run lint` | 无错误；保留已有 MoodOrb React Fast Refresh 警告 |
| `git diff --check` | 通过 |

Hvigor 的测试命令即使断言失败，也可能返回成功退出码。本轮额外检查了 `entry/.test/default/intermediates/test/coverage_data/test_result.txt`，157 条结果均为 `Success`。

## 模拟器实测

目标：`127.0.0.1:5555`，包名 `com.milo.echoes`，通过覆盖安装保留原有数据。

- 验证码／密码登录切换、空邮箱进入找回密码表单、`milo` 本地入口登录。
- 选情绪 → 选择过去时间 → 多轮对话 → 日记 → 卡片完整完成。
- 键盘打开时提问仍可见，多行文字可正常输入。
- 强制停止并重启：未发送文字、AI 开关与已发送记录恢复。
- AI 未配置时自动本地引导，超过三轮仍能发送；“先这样”得到简短停止回应。
- 关闭 AI 后进入日记并重启，再返回对话，仍为 AI 关闭，记录未重复。
- 星球卡片、轨道剧场均完成截图检查，并显示“已保存到系统图库”。
- 选择轨道剧场后强制停止应用，重新进入该回忆的卡片页仍显示 `2 / 2`。

模拟器保留一条本轮测试回忆供查看；早期重复测试记录已移除，原有回忆保留。

安装包：`apps/harmony/entry/build/default/outputs/default/entry-default-signed.hap`。
本地截图：`apps/harmony/entry/build/local-verification/`（构建目录内，不提交图片）。

## 尚未覆盖

本地 `GATEWAY_BASE_URL` 继续保持为空。AI 成功路径通过注入的模拟网关验证，真实 MiniMax 请求、真实邮箱收码／线上认证、真机语音输入未实测。AGC 配置、包名和本地签名配置保持原样。本轮没有发布到线上或 AppGallery。

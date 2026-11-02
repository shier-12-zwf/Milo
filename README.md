# MILO-米洛 · 回到过去的某一天

> 市面上的产品大多面向现在与未来，「MILO」带你回到过去——转动记忆水晶，让 AI 陪你唤醒某一天的感受，沉淀成一篇属于你的日记。

## 它是如何工作的

1. **转动拨盘，找到此刻的感受** — 首页是一颗晶体光球，像 iPod 转盘一样沿光环旋转，球体颜色随情绪明暗流转；再转动词环，收下最贴切的感受词（也可以不选，感受不必都有名字）。
2. **分辨来处** — 这份感受来自此刻，还是来自过去的某一天？
   - **此刻**：简单点选记录，不打断当下。
   - **过去**：只需一个模糊的时间标记（"去年夏天""大学毕业前后"），不必精确到日期。
3. **AI 引导回忆** — 通过 Codex ACP 接入 AI，一步步陪你说出当时的情景、困难或快乐、背后的原因，以及那一天对现在的特别之处。支持文字与浏览器语音输入。
4. **沉淀为日记** — 对话结束后，AI 以你的第一人称视角写成一篇日记（可手动开关、可编辑）。
5. **分享与回看** — 日记一键生成分享卡片（Canvas 渲染），保存的回忆随时在时间线里回看。

## 快速开始

```bash
npm install
npm run dev:all   # 同时启动前端 (5173) 与 ACP 桥接服务 (8787)
```

浏览器打开 http://localhost:5173 即可体验。

也可以分开启动：

```bash
npm run dev      # 仅前端
npm run server   # 仅 ACP 桥接
```

### AI 对话的前置条件

AI 引导依赖 [Codex](https://github.com/openai/codex) 账号：

- 桥接服务通过 `@zed-industries/codex-acp` 以 [Agent Client Protocol](https://agentclientprotocol.com) 与 Codex 通信，复用你本机 `~/.codex` 的登录态；
- 默认模型为 `gpt-5.4-mini`，可用环境变量覆盖：`ACP_MODEL=gpt-5.5 npm run server`；
- **没有 Codex 也能完整体验**：ACP 不可用时自动降级为内置的脚本化引导与本地日记模板。

## 技术栈

| 部分 | 选型 |
| --- | --- |
| 前端 | React 19 + TypeScript + Vite |
| AI 对话 | Codex ACP（stdio JSON-RPC），Node WebSocket 桥接到浏览器 |
| 语音输入 | Web Speech API（zh-CN） |
| 分享卡片 | Canvas 2D 渲染 1080px 宽、自适应高度 PNG，可保存图片后回到首页 |
| 数据 | localStorage 本地存储，无后端、无账号 |

## 目录结构

```
server/acp-bridge.mjs   # WebSocket ↔ codex-acp 桥接服务
src/
  components/           # 晶体光球、星空背景
  lib/                  # ACP 客户端、旋转拨盘手势、引导 prompt、语音、卡片渲染
  pages/                # 首页拨盘 → 分流 → 对话 → 日记 → 卡片 → 时间线
  store.ts              # localStorage 状态
services/ai-gateway/    # Express + MiniMax HTTP 网关（被 HarmonyOS 与 Web 共享）
apps/harmony/           # Stage-model ArkTS + ArkUI 原生应用
apps/web/               # React + Vite 现有 web 构建
docs/compliance/        # data-flow / permissions / release-checklist
docs/superpowers/plans/ # 多端策略与原生移植计划
```

## 多端策略

- **业务规则与后端契约共享**：服务端 Express 网关对 Web 与 HarmonyOS 暴露同一套 `/v1/recall/*` 路由与 `MiniMaxTransport` 接口；客户端只负责 UI 渲染。
- **Web（React + Vite）** 与 **HarmonyOS（ArkTS + ArkUI）** 已经实现；iOS / Android 暂未排期。
- **AI 失败降级**：Web 与 HarmonyOS 都通过 `ConversationController` / 离线 flow 切换到本地脚本化引导与 `fallbackDiary`，保证无 AI 也能完整走完流程。

## License

MIT

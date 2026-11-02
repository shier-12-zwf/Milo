# Milo 旧域名官网发布

2026-09-23，按用户要求更新已有 Vercel 项目，官网已公开上线。

- 官网：https://milo.huangtangai.top/
- Web 体验：https://milo.huangtangai.top/app
- 隐私说明：https://milo.huangtangai.top/privacy
- 项目：`hortons-projects-d177a826/milo`，`prj_VtppQWcMXWfxWPEnr4CNwY2gxNHl`。
- 新部署：`dpl_Cv7JZS3kMeMNV7EnPPWK68Wrg24a`，`milo-k2z4fn2pg-hortons-projects-d177a826.vercel.app`。
- 原部署保留：`dpl_9LAXCcJKQTRfmchCRfeqSHqQRe8X`，`milo-9wf0zts29-hortons-projects-d177a826.vercel.app`。

## 发布内容与边界

首页为新版 3D 星空官网，包含 15 种情绪星球、旋转/靠近/暖光交互和沉浸星空入口；原 Web 应用在 `/app`。继续使用原域名、原 `echoes.entries.v1` 存储键，未清理用户浏览器记录。

该 Vercel 项目没有配置 AI 后端或环境变量。本次以 `VITE_PUBLIC_AI_ENABLED=false` 构建，回忆对话直接使用本地引导，不展示无法使用的在线 AI 选项；隐私说明与介绍同步适配。未把华为云私有网关开放到公网。华为云私有预览和 `milomood.xyz` 备案进度保持原状态。

## 验证

- Web 146 项测试通过，TypeScript/Vite 构建成功；lint 只有已有的 `MoodOrb.tsx` Fast Refresh 警告。
- Vercel 独立部署地址浏览器验证 WebGL 实际启用、全部 15 种星球图片正常、沉浸入口与 `/app` 跳转正常。
- 使用虚构文字完成本地回忆对话、日记整理、保存及分享卡片生成；无浏览器错误。测试记录仅在独立部署地址，不在正式域名。
- 正式域名切换后，无登录 HTTP 请求验证 `/`、`/app`、`/privacy`、favicon、主 JS/CSS 均为 200，内容与本地构建逐字节一致；`/api/v1/recall/open` 返回预期的 404。
- 正式域名浏览器确认新版首页、3D 渲染和官网布局已生效。

## 再次发布与回滚

本次只上传编译后的静态站点，未上传 Harmony 工程、备案资料或本地配置。暂存输出在 `.artifacts/vercel-web-release/deploy/.vercel/output/`，符合 Vercel Build Output API v3；`static/` 为构建产物，`config.json` 配置 `/app`、`/privacy` 的入口重写、静态资源缓存及未启用 API 的 404。

```bash
VITE_PUBLIC_AI_ENABLED=false npm run build --workspace @milo/web -- --outDir /Users/hut/Projects/milo/.artifacts/vercel-web-release/dist
# 将本次 dist 同步到单独的 .vercel/output/static 后：
vercel deploy --prebuilt --prod --skip-domain --yes --cwd /Users/hut/Projects/milo/.artifacts/vercel-web-release/deploy
# 验收新部署后，以 CLI 返回的真实部署地址执行：
vercel promote <新部署地址> --yes
vercel alias set <新部署地址> milo.huangtangai.top
```

需要恢复旧版时：

```bash
vercel promote milo-9wf0zts29-hortons-projects-d177a826.vercel.app --yes
vercel alias set milo-9wf0zts29-hortons-projects-d177a826.vercel.app milo.huangtangai.top
```

独立部署地址可能受 Vercel 登录保护；公网验收必须使用正式域名并检查最终响应内容，不能将登录页的 HTTP 200 当作应用成功。

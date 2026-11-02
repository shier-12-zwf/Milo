# Web 端 Monorepo 骨架迁移方案

## 目标
把当前平铺的 `src/`、`tests/`、`public/` 等收进 `apps/web/`，在根目录建立 npm workspaces 骨架。
为后续鸿蒙端（第一周上线）留出 `apps/` 空间，但**不预先建空原生目录**。

## 目标结构
```
milo/
├── apps/
│   └── web/                    # ← 现有 Web 工程，整体迁入
│       ├── src/
│       ├── tests/
│       ├── public/
│       ├── index.html
│       ├── vite.config.ts
│       ├── tsconfig.json
│       ├── tsconfig.app.json
│       ├── tsconfig.node.json
│       ├── .oxlintrc.json
│       └── package.json        # ← 新建：web 端依赖
│
├── server/                     # ACP 桥，保持原位
│   └── acp-bridge.mjs
├── docs/                       # 设计档案，保持原位
├── .github/workflows/deploy-pages.yml
├── package.json                # ← 改为根 workspace
├── package-lock.json
└── README.md
```

## 迁移步骤

### 1. 用 git mv 整体搬迁（保留历史）
```bash
mkdir -p apps/web
git mv src index.html public tests .oxlintrc.json apps/web/
git mv vite.config.ts tsconfig.json tsconfig.app.json tsconfig.node.json apps/web/
```
注意：`tests/` 与 `public/` 随 `src/` 一起搬，**所有 `../src/...`、`../public/...` 相对路径不变**，测试零改动。

### 2. 依赖拆分到 apps/web/package.json（新建）
把 web 专属依赖从根挪到 `apps/web/package.json`：
- 运行时：`react`、`react-dom`
- 构建：`vite`、`@vitejs/plugin-react`
- 类型：`@types/react`、`@types/react-dom`

留在根 `package.json`：
- server 用：`@zed-industries/agent-client-protocol`、`ws`、`@types/ws`、`@zed-industries/codex-acp`
- 通用 devDeps：`typescript`、`oxlint`、`concurrently`
- scripts：`dev:all` 仍同时起 web + server

### 3. 根 package.json 配置 workspaces
```jsonc
{
  "name": "milo",
  "private": true,
  "workspaces": ["apps/web"],
  "scripts": {
    "dev": "npm -w apps/web run dev",
    "server": "node server/acp-bridge.mjs",
    "dev:all": "concurrently -k -n web,acp \"npm -w apps/web run dev\" \"node server/acp-bridge.mjs\"",
    "build": "npm -w apps/web run build",
    "test": "npm -w apps/web test",
    "lint": "oxlint"
  }
}
```

### 4. apps/web/package.json scripts
```jsonc
{
  "name": "@milo/web",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "test": "node --test tests/*.test.ts",
    "lint": "oxlint"
  }
}
```

### 5. apps/web/vite.config.ts 不变
（无需改 root，Vite 默认以配置文件所在目录为 root）

### 6. deploy-pages.yml 路径更新
`build` 步骤改为在根运行 `npm run build`（根 script 转发到 workspace），
`Upload Pages artifact` 的 `path` 仍为 `dist` → 改为 `apps/web/dist`。

### 7. pagesDeployment.test.ts 修正
该测试从根 `.github/...` 读文件。搬进 `apps/web/tests/` 后，从根 `npm test` 运行时
cwd 可能变。改为用 `import.meta.url` 解析到仓库根的绝对路径，避免 cwd 依赖。
（其余 22 个测试无需改动——相对路径不变。）

### 8. tsconfig 路径
`tsconfig.app.json` 的 `include: ["src"]` 仍在 `apps/web/` 下，无需改。
`tsconfig.node.json` include 若含 `vite.config.ts`，仍在同级，无需改。

### 9. 修正 package.json name "demo" → "milo"
顺手把根 package name 从 `demo` 改为 `milo`。

## 验证清单
- [ ] `npm install` 成功（workspaces hoist）
- [ ] `npm run dev` 前端起来在 5173
- [ ] `npm run dev:all` web + ACP 桥都起
- [ ] `npm run build` 产出 `apps/web/dist`
- [ ] `npm test` 全部 23 个测试通过
- [ ] `npm run lint` 通过
- [ ] git 历史可追溯（git mv 保留）

## 不在本次范围
- 鸿蒙工程目录（等开工再建 `apps/harmony/`）
- iOS/Android 工程
- packages 共享层抽取（等第二端开工再抽）
- 依赖深度拆分（server 独立 package.json）
- index.css 拆分
- ACP 桥云端化

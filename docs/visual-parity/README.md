# MILO 跨平台逐页验收

## 当前阶段：Web / iOS（2026-09-29）

用户已将本轮参考改为实际公开Web产品 `https://milo.huangtangai.top/app`，不启动鸿蒙App。当前计划见[Web参考与原生迭代](web-native-plan-2026-09-29.md)，实际进展见[本轮记录](../operations/ios-web-native-iteration-2026-09-29.md)。

- `web-cases.json` 保留全部53个原生状态：28共享、17原生独有、8最大字号压力状态；没有匹配原图或独立审查时保持pending。
- `web-parity-gate.mjs` 校验原生PNG、实际Web PNG/JPEG原图、构建/运行回执、页面及编辑器连续覆盖、图像绑定的独立作者审查和真实动效证据。JPEG通过macOS自带ImageIO完整解码；非macOS缺少该能力时明确失败，不猜测通过。
- 截图工具报告的网页devicePixelRatio可能不同于返回原图的实际像素倍率，以原图宽高为准。改后缀或转码不能补造图像来源。
- `specdrive.web-native.json` 是本阶段执行清单；本机继续 `.specdrive/web-native-20260929`，不得重新初始化来绕过原有执行上限。
- 所有新证据与临时产物留在当前项目；原始截图和私有数据不提交Git。

```sh
node --test apps/ios/tests/web-parity-gate.test.mjs
node apps/ios/scripts/web-parity-gate.mjs
node .agents/skills/specdrive/scripts/specdrive.mjs status .specdrive/web-native-20260929
```

## 历史鸿蒙参考契约

以下记录保留历史参考及工具接口，不能换标题后冒充本轮Web验收。

这里保存此前鸿蒙产品的参考指纹、53 个必需页面/状态及后续真实截图。
`cases.json` 中的 `pending`、空图片和空评审代表尚未完成，不能用早期 iOS
离线试验的几张图替代。本工具不生成截图或评审通过凭据。

## 使用方式

在项目根目录执行：

```sh
node apps/ios/scripts/parity-evidence.mjs hash-source
node apps/ios/scripts/parity-evidence.mjs hash-build --path apps/ios/DerivedData/Build/Products/Debug-iphonesimulator/Milo.app
node apps/ios/scripts/parity-evidence.mjs hash-fixture --case login--email
node apps/ios/scripts/parity-evidence.mjs hash-captures --case login--email
node apps/ios/scripts/parity-evidence.mjs validate
node apps/ios/scripts/parity-evidence.mjs report --output .artifacts/ios/harmony-history-report.html
node --test apps/ios/tests/parity-evidence.test.mjs
```

- `hash-source` 输出当前 iOS 源指纹及每个文件的 SHA-256，供真实构建和采集时记录。
- `hash-build` 对实际构建文件或整个 `.app` 目录计算指纹；它不会进行构建，也不宣称构建成功。
- `hash-fixture` 输出某个 case 的固定内容哈希；`hash-captures` 只对已经记录的两端
  capture 对象生成完整元数据哈希，供独立评审引用。二者都不写评审或给出通过判定。
- `validate` 默认读取本目录的 `cases.json`、其 `referenceManifest` 指向的
  `harmony-source.json`，以及 `ios-source-build.json`。任何证据缺失、不匹配或未评审时退出码为 1；完整匹配时为 0。
- `report` 即使证据仍未完成也会生成并排 HTML，清楚列出待办及可用原图链接。
  报告生成成功只表示 HTML 已写入，不等于验收通过。HTML 不嵌入第三方资源或修改图片。
- 测试只使用临时目录里的**合成图片、假源码、假构建和单元测试评审**；不会写入当前产品的图片或通过凭据。

可选参数：`--root <项目根目录>`、`--cases <清单文件>`、
`--ios-provenance <iOS构建指纹JSON>`、`--harmony-root <鸿蒙项目根目录>`、
`--evidence-root <图片根目录>`。图片根目录默认是清单所在目录；图片路径必须相对该目录，
不允许目录穿越或跳出根目录的符号链接。鸿蒙根目录默认采用参考文件中的 `referenceRoot`。

## 精确指纹算法

源指纹是两层 SHA-256：

1. 每个文件直接对原始字节计算 SHA-256。
2. 文件相对路径统一使用 `/`，按字符串字典顺序升序排列，生成
   `{ "relative/path": "file-sha256", ... }` 对象。
3. 对该对象的 `JSON.stringify` 结果按 UTF-8 计算 SHA-256；无缩进、无末尾换行。

iOS 范围为 `apps/ios/App`、`MiloCore`、`UITests`、`Resources`、`project.yml`、
`Milo.xcodeproj`、`scripts` 和 `tests`。这同时覆盖产品、资源、工程、测试和本验证器；
修改其中任意文件会让旧证据失效。忽略目录/文件名 `.build`、`.swiftpm`、`xcuserdata`、
`DerivedData`、`build`、`node_modules`、`.DS_Store`；产品源码范围内的符号链接会被拒绝。
所有列出的顶层输入必须存在。

鸿蒙范围是完整 `apps/harmony/entry/src/main` 和 `apps/harmony/AppScope`，包括深色资源、
页面配置和应用描述。当前 `harmony-source.json` 的 74 个文件及聚合哈希采用相同算法。
含敏感配置的文件仅存哈希，不能将配置内容附在报告中。新文件、删除或改动都使旧指纹失效。

构建为单个 HAP/IPA/文件时直接对文件字节计算 SHA-256；构建为 `.app` 目录时，对
**目录内所有文件**使用相同的排序映射算法，路径相对于 `.app` 根目录，不忽略任何资源。
移动未修改的 `.app` 不改变构建指纹；目录内符号链接不受支持，不能静默漏掉其内容。

`ios-source-build.json` 由真实构建执行者在源码未再改变时记录，至少包含：

```json
{
  "version": 1,
  "sourceHash": "hash-source 输出的 sourceHash",
  "build": {
    "path": "apps/ios/DerivedData/Build/Products/Debug-iphonesimulator/Milo.app",
    "sha256": "hash-build 输出的 SHA-256"
  },
  "buildReceipt": {
    "sourceHashBefore": "执行构建前的 sourceHash",
    "sourceHashAfter": "构建结束后的 sourceHash",
    "buildHash": "本次实际产物 SHA-256",
    "command": ["实际构建程序", "原始参数"],
    "startedAt": "真实开始时间 ISO 8601",
    "finishedAt": "真实结束时间 ISO 8601",
    "exitCode": 0,
    "log": { "path": "实际构建日志的相对路径", "sha256": "日志字节 SHA-256" }
  }
}
```

构建及日志路径相对于相应项目根目录。**两平台**均须增加由实际构建执行者记录的
`buildReceipt`；不能追认、猜测或给历史构建补造成功回执。构建前后源码指纹必须相等且
匹配当前源码；真实产物、退出码、时间顺序和非空日志哈希均须匹配。iOS 日志必须包含
`** BUILD SUCCEEDED **`、预构建测试包时的 `** TEST BUILD SUCCEEDED **`，或实际构建并测试时的 `** TEST SUCCEEDED **`；鸿蒙日志必须
包含 `BUILD SUCCESSFUL`，且不能有 `BUILD FAILED` / `TEST FAILED`。
截图时间不得早于该构建结束时间。

原生截图流程先执行 `xcodebuild build-for-testing`，记录真实预构建的 `buildReceipt`；
随后用 `test-without-building` 执行交互或截图，确认预构建源码和产物未变，并另记
`verificationReceipt`。保留较早的预构建回执，不能用截图测试结束时间覆盖其 `finishedAt`。
测试期间产生的截图仍必须晚于预构建完成时间；较晚的测试回执不能替代此前置构建证据。

这是一套**关联与完整性校验**，不是签名认证或防伪证明。哈希本身无法证明记录者身份、
某命令确实执行过、该日志对应某次真实构建。集成负责人须保存真实执行过程，独立审查者
须核对构建、设备和截图记录；JSON 声明不能替代这些事实。

## 单个页面/状态的证据格式

保留清单的 `id`、`route`、`state`、`required`、`textSize`、`checkpoints`。
验证器独立保留已评审的 53 个必需 ID、大字号和滚动检查点，防止删行、改为非必需、
删除检查点或降低字号后得到通过。扩大清单可以添加新 case；缩减既有验收范围需要重新评审。

每个 case 的 `harmony` 和 `ios` 分别记录：

```json
{
  "caseId": "login--email",
  "sourceHash": "对应平台当前源指纹",
  "buildHash": "对应平台实际安装构建的指纹",
  "fixtureVersion": "milo-parity-v1",
  "fixtureHash": "hash-fixture --case 对应 ID 的结果",
  "fixedTime": "2026-09-26T09:41:00+08:00",
  "locale": "zh_CN",
  "timezone": "Asia/Shanghai",
  "textSize": "default",
  "actualTextSetting": { "category": "large", "description": "采集时实际启用的系统默认字号" },
  "capturedAt": "实际采集时间的 ISO 8601 字符串",
  "device": {
    "name": "实际模拟器或设备型号",
    "osVersion": "实际系统版本",
    "viewport": { "width": 390, "height": 844 },
    "scale": 3
  },
  "images": [
    {
      "checkpoint": "visible-state",
      "path": "evidence/ios/实际原图文件名.png",
      "sha256": "原始 PNG 字节 SHA-256",
      "scrollOffset": 0,
      "contentAnchor": "这张图最后可见的具体内容或控件"
    }
  ]
}
```

上例是**格式说明，不是有效证据**。viewport 使用逻辑单位，scale 为像素比例；PNG
完整尺寸必须等于 viewport × scale。保留系统栏和键盘，报告不裁切或重绘原图。
必须真实启用并记录系统字号，不能只在元数据填入预期值。

`actualTextSetting` 必须为结构化对象，普通字符串（包括非空的 `"default"`）不能通过：

- iOS 默认 case 使用 `{ "category": "large" }`，最大字号使用
  `{ "category": "accessibility5" }`。分别兼容 UIKit 的
  `UICTContentSizeCategoryL` 和 `UICTContentSizeCategoryAccessibilityXXXL`。
  记录默认字号却申报最大字号、或反过来，均会失败。
- 鸿蒙记录 `{ "scale": 实际值, "defaultScale": 平台默认值,
  "maxSupportedScale": 平台支持的最大值 }`。数值必须由实际系统状态及平台设置获得，
  最大值必须大于默认值；默认 case 的 scale 须等于 defaultScale，最大字号 case
  的 scale 须等于 maxSupportedScale。
- 两平台都可添加 `description` 作为人工说明，但它不能替代规范化类别/比例；报告根据
  结构化字段显示真实记录值。修改结构化字号后也必须重新生成并审阅 capture 元数据绑定。

PNG 验证检查完整 chunk 边界、CRC、IHDR/IDAT/IEND、压缩像素数据的解压长度和扫描行；
只保留 PNG 头、修改 CRC、截断内容后重新填哈希均不能通过。格式有效仍不能证明它是
某台设备上采集的真实产品画面，这一点由真实采集及独立审图负责。

`fixtureHash` 用于绑定内容本身，而非只绑定版本标签。算法为对以下对象递归排序键
（数组保留顺序），`JSON.stringify` 后按 UTF-8 计算 SHA-256：

- `fixture`：ledger 顶层字段，排除 `cases`、`referenceManifest`、`captureContract`。
  因而 `syntheticNote`、固定时间、语言或将来新增的全局固定内容均在哈希中。
- `case`：该行所有字段，排除 `harmony`、`ios`、`review`、`status`。

case ID、页面、状态、字号、检查点或固定文字变化都会使原证据失效。不能将登录邮箱页的
capture 和评审直接复制给密码页。

对于 `top → all-overflow-content → bottom`：

- capture 增加运行时测量的 `scrollGeometry`：`{ totalContentHeight, viewportHeight,
  maxScrollOffset, lastAnchor }`。最后锚点必须是页面最后实际内容/操作，不能任意填写。
  最大偏移应为 `max(0, totalContentHeight - viewportHeight)`（容许 1 个逻辑单位测量误差）。
- `images` 按实际向下滚动顺序排列，首图 `top`、偏移 0，末图 `bottom`。
- 至少有一张 `all-overflow-content` 中间图；内容很长时可以有多张，不能只拍首尾。
- 每张图增加 `visibleContentHeight`，记录当时可见滚动内容高度，不计键盘和遮挡区域。
- 所有滚动图的可见高度须匹配实测 viewportHeight；末图必须到达 maxScrollOffset，
  `contentAnchor` 必须等于实测 `lastAnchor`。给长页三张偏移 0/1/2 的图不能证明到底。
- 偏移严格递增，相邻偏移差不大于前图可见内容高度的 90%，保证至少 10% 重叠。
- 每个内容锚点必须明确且不同；同一个文件或相同图片字节不能伪装成多个检查点。
- 若运行时测量显示 `totalContentHeight <= viewportHeight` 且 `maxScrollOffset == 0`，
  使用**一张** `checkpoint: "full-content"` 的真实图，偏移为 0、锚点为 lastAnchor，
  并显式填写 `coversCheckpoints: ["top", "all-overflow-content", "bottom"]`。
  这张图证明所有逻辑检查点同时可见，包括最大字号仍能一屏显示的情况，不需要伪造滚动。

元数据校验无法证明图片确实来自该设备、固定数据真实进入视图，或画面内容确实覆盖连续区域。
采集者必须保留原始运行记录，独立评审必须核实画面与锚点。时间、语言、fixture 版本和源码
指纹均匹配后，才允许比较同一 case。

## 独立评审格式

每个 case 的 `review` 由实际看过两端全部原图的独立评审者填写：

- `verdict`：只有实际通过才为 `pass`；`reviewer` 和 `reviewedAt` 不能为空。
  评审时间不得早于任一平台采集时间。
- `caseId`、`fixtureHash`：必须匹配该行及两端固定内容。
- `sourceHashes`：`{ harmony, ios }`，绑定两端当前源指纹。
- `buildHashes`：`{ harmony, ios }`，绑定两端实际构建指纹；相同源码重新构建后不能静默挪用旧评审。
- `imageHashes`：`{ harmony: [按 images 顺序排列的 SHA256], ios: [...] }`，绑定所有原图。
- `captureHashes`：`{ harmony, ios }`，绑定**完整 capture 对象**递归键排序后的 JSON
  SHA-256，数组保留顺序。因此设备、时间、滚动总高度、最后锚点、偏移、图片路径或其他
  capture 元数据变化都会令旧评审失效。可用 `hash-captures --case <ID>` 计算，无自动通过行为。
- `fidelity`、`readability`、`actions`、`polish`：分别为 `{ verdict, notes }`。
  全部必须通过且有具体说明，特别说明可核查的美学提升。
- `findings`：显式数组。发现项必须含 `status` 和具体 `notes`；只接受已修复的
  `resolved` 或经独立评审接受的 `accepted-deviation`，未解决项阻断通过。

原生安全确认等差异要引用鸿蒙源操作画面并写明理由，不能制造鸿蒙中不存在的界面。
跨 case 或跨平台重复图片默认拒绝。确需引用原操作截图的后续 case，必须有明确发现项：
`status: "accepted-deviation"`、`sourceCaseId`、`sourcePlatform`、当前 `platform`、
该图 `sha256`、具体 `sourceAction` 以及 `notes`。源 case 必须先出现在清单中；该例外
仅用于独立评审接受的源操作引用，不能把同一图复制给未实现的页面。
验证器核对的是证据结构、当前文件及评审声明，不能认证评审者身份或自动判断美学。
独立审图必须核对连续内容覆盖和最终锚点，不能只看元数据的 bottom 标签。
最终报告仍须结合真实的此刻/过去两条旅程、重启恢复、失败回退、导出和外部服务验证。
模拟器截图不能当作实体 iPhone 实测，DEBUG 账号状态不能当作真实 AGC 登录成功。

# iOS 邮箱账号服务接入

Milo 使用真实 Huawei AGConnectAuth **1.9.4.300** SDK。SDK 已编译接入并不代表远程邮箱登录已经验收：缺少有效 iOS 配置时，App 使用明确报错的未配置 provider；本地 `milo` 入口和 DEBUG 截图身份都不是 AGC 认证。

## 获取依赖

从仓库根目录执行：

```sh
python3 apps/ios/scripts/install-agc-sdk.py
python3 apps/ios/scripts/install-agc-sdk.py --verify
```

脚本按 [agc-sdk-lock.json](../../apps/ios/agc-sdk-lock.json) 的固定官方 URL 下载并核验 SHA-256，仅写入忽略的 `apps/ios/Vendor/AGConnect/`。再次安装会核对每一个已安装文件的哈希，损坏或缺失时重新安装；`--verify` 只检查、不联网。临时解压目录也在当前项目内。无需 CocoaPods，全局环境不变。

供 CI 使用时，在生成 Xcode 工程前运行安装脚本。四个静态 XCFramework 路径均位于 `apps/ios/Vendor/AGConnect/1.9.4.300/`：

- `AGConnectAuth.xcframework`
- `AGConnectCredential.xcframework`
- `AGConnectCore.xcframework`
- `HMFoundation.xcframework`

工程应链接它们且 `embed: false`，链接 `Security.framework`，保留 `-ObjC`。将同目录的 **AGCResources.bundle** 作为资源拷贝到 App bundle。SDK 许可原文保存在 `Licenses/`；不要把厂商二进制提交到仓库。

官方提供 [CocoaPods 与手动 SDK 集成说明](https://developer.huawei.com/consumer/en/doc/AppGallery-connect-Guides/agc-auth-ios-integration-sdk-0000001326347605)。当前采用手动 XCFramework 模式，没有声称存在官方 Swift Package 发布。

## 配置真实 iOS 应用

1. 在 AppGallery Connect 的现有 Milo 项目内创建或选择 **iOS** 应用，Bundle ID 必须为 `com.milo.echoes.ios`。在 Auth Service 开启邮箱认证，并设置实际数据处理位置。
2. 按 [Auth Service 的 iOS 信息配置说明](https://developer.huawei.com/consumer/ru/doc/AppGallery-connect-Guides/agc-auth-config-ios-0000001282051066) 填写实际 App Store ID 和 Team ID。Apple Developer 登录不能代替 AGC 项目配置。
3. 从该 **iOS 应用** 下载原始 `agconnect-services.plist`，放到 `apps/ios/Resources/agconnect-services.plist`，加入资源复制。此配置保持本地，不提交。不要将 Harmony 的 JSON 改后缀或填入假凭证。
4. `AGCAuthProvider.make()` 会验证 plist、Bundle ID、SDK 所需标识/凭证及区域，验证通过才调用一次 `AGCInstance.startUp`。配置缺失或不匹配返回 `UnconfiguredAGCAuthProvider`，仍保留真实 SDK 的编译依赖。

SDK 从配置读取 appId、productId、cpId、clientId、clientSecret、apiKey 和 routePolicy。不要将这些值写到日志或测试证据。纯邮箱认证不需要示例中各社交登录 SDK、URL scheme 或 Apple 登录能力。

## 账号行为与验收边界

- 验证码发送区分登录/注册与重置密码两个 purpose；使用新版 AGCAuth 实例方法。
- 验证码登录仅在官方 `UserNotRegistered` 错误后注册新用户；其他失败不尝试注册。
- 密码重置只完成重置。之后的自动登录由 AccountModel 单独执行，必须能显示“重置成功但登录失败”的部分成功状态。
- 会话恢复向 SDK 请求刷新 token；磁盘上的显示身份不被当成新认证。SDK 管理 token，不另存明文密码或验证码。
- 修改密码、注销等敏感操作若超过最近登录期限，会提示重新登录；不能将删除本地状态伪装成远程注销成功。参见[官方重认证规则](https://developer.huawei.com/consumer/en/doc/appgallery-connect-Guides/agc-auth-ios-reauthenticate-0000001127283387)。

验收应使用用户掌控的测试邮箱，分别记录验证码注册、密码登录、重启会话恢复、重置后登录、最近登录过期、退出和远程注销的实际结果。发送邮件、修改密码和注销不能在安装脚本或普通 CI 中自动执行。真实配置、收件箱和设备不足时，明确记录未验证，不能用 fake provider 的单测或截图代替。

## 本次编译证据

本地 `.artifacts/ios/auth-research-20260930/` 保留官方包的 SHA、headers、API 编译探针、适配器编译诊断和安装器校验结果。Swift 6 / iOS 17 的 arm64 真机与模拟器 SDK API 探针均已编译链接；探针未执行，没有请求远程账号服务。全 App 构建、UI 与真实账号验收由项目主流程单独记录。

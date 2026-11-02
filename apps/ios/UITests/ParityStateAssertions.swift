import XCTest

/// Read-only checks for the isolated capture fixtures. Geometry/scroll coverage,
/// real network behavior and visual approval remain separate assertions.
@MainActor
func assertParityState(_ caseID: String, in app: XCUIApplication) {
    let parts = caseID.components(separatedBy: "--")
    let largeTextCases: Set<String> = [
        "home--words-three", "now-note--keyboard-long", "chat--conversation",
        "diary--long", "timeline--populated", "detail--transcript-expanded",
        "account--local", "ai-settings--personal"
    ]
    guard parts.count == 2 || (parts.count == 3 && parts[2] == "large-text") else {
        XCTFail("Unsupported parity case: \(caseID)")
        return
    }
    let stateID = parts.prefix(2).joined(separator: "--")
    if parts.count == 3 {
        guard largeTextCases.contains(stateID) else {
            XCTFail("Unsupported large-text parity case: \(caseID)")
            return
        }
    }
    let check = ParityStateCheck(caseID: caseID, app: app)
    let note = "今天慢慢走了一段路，风很温柔。"
    let longNote = Array(repeating: note + "路边的树叶轻轻摇晃，我停下来，记住了这段安静的时间。", count: 14).joined(separator: "\n\n")
    let opening = "那段时光里，你最先想起的是什么？"
    let followup = "那一刻，是什么让你记住了它？"
    let entryID = "timeline.entry.B8867CF1-3C35-489D-B128-9788DDCDDB63"

    // Modal states must remain modal throughout capture; never scroll underneath.
    if stateID == "detail--delete-confirmation" {
        check.alert(title: "放下这段回忆？",
                    message: "这会从这台设备删除这段回忆，无法撤销。",
                    cancel: "再留一会儿", destructive: "放下回忆")
        return
    }
    if stateID == "account--delete-confirmation" {
        check.alert(title: "注销账号？",
                    message: "将注销 MILO 账号，并删除此设备的日记和草稿，无法恢复。已保存到相册的图片不会删除。",
                    cancel: "取消", destructive: "注销并删除")
        return
    }
    XCTAssertFalse(app.alerts.firstMatch.exists, "\(caseID): unexpected alert")

    switch stateID {
    case "login--email", "login--password", "login--code", "login--reset", "login--error":
        check.require(check.element("page-login"))
        let submit = check.require(app.buttons["login-submit"])
        switch parts[1] {
        case "email":
            check.label(app.staticTexts["登录 MILO"], equals: "登录 MILO")
            check.empty(app.textFields["login-email"], placeholder: "邮箱地址")
            check.label(submit, equals: "获取验证码")
            XCTAssertFalse(submit.isEnabled, caseID)
            XCTAssertFalse(app.secureTextFields["login-password"].exists, caseID)
            XCTAssertFalse(app.textFields["login-code"].exists, caseID)
        case "password":
            check.value(app.textFields["login-email"], equals: "milo@example.com")
            check.require(app.secureTextFields["login-password"])
            check.require(app.buttons["login-forgot-password"])
            check.label(submit, equals: "登录")
            XCTAssertFalse(submit.isEnabled, caseID)
            XCTAssertFalse(app.textFields["login-code"].exists, caseID)
        case "code":
            check.label(app.staticTexts["输入验证码"], equals: "输入验证码")
            check.require(app.staticTexts["已发送至 milo@example.com"])
            check.empty(app.textFields["login-code"], placeholder: "6 位验证码")
            check.label(submit, equals: "登录")
            XCTAssertFalse(submit.isEnabled, caseID)
            XCTAssertFalse(app.textFields["login-email"].exists, caseID)
            XCTAssertFalse(app.secureTextFields["login-new-password"].exists, caseID)
        case "reset":
            check.label(app.staticTexts["设置新密码"], equals: "设置新密码")
            check.require(app.staticTexts["已发送至 milo@example.com"])
            check.empty(app.textFields["login-code"], placeholder: "6 位验证码")
            check.require(app.secureTextFields["login-new-password"])
            check.label(submit, equals: "重置并登录")
            XCTAssertFalse(submit.isEnabled, caseID)
            XCTAssertFalse(app.textFields["login-email"].exists, caseID)
        default:
            check.value(app.textFields["login-email"], equals: "milo@example.com")
            check.visibleError("login-error-message", text: "邮箱登录尚未接通，请完成此 iOS 版本的账号服务配置。现有本机回忆不会丢失。")
            check.label(submit, equals: "获取验证码")
            XCTAssertTrue(submit.isEnabled, caseID)
        }
        if parts[1] != "error" { XCTAssertFalse(check.element("login-error-message").exists, caseID) }

    case "home--mood-calm", "home--mood-joyful", "home--mood-low":
        let selected = String(parts[1].dropFirst("mood-".count))
        for mood in ["joyful", "bright", "okay", "calm", "heavy", "low", "very-low"] {
            let button = check.require(app.buttons["mood-\(mood)"])
            XCTAssertEqual(button.isSelected, mood == selected, "\(caseID): selected mood \(mood)")
        }
        check.require(app.buttons["confirm-mood"])
        XCTAssertFalse(app.buttons["confirm-words"].exists, caseID)

    case "home--words-empty", "home--words-three":
        let selectedCount = parts[1] == "words-three" ? 3 : 0
        for index in 0..<12 {
            let word = check.require(app.buttons["word-\(index)"])
            XCTAssertEqual(word.isSelected, index < selectedCount, "\(caseID): word \(index) selection")
        }
        check.require(app.staticTexts[selectedCount == 0 ? "转动词环，挑选最多三个贴近的词" : "平静 · 安稳 · 松弛"])
        check.require(app.buttons["confirm-words"])
        XCTAssertFalse(app.buttons["confirm-mood"].exists, caseID)

    case "classify--default":
        check.require(app.staticTexts["这份感受，来自哪里？"])
        check.label(app.buttons["choose-now"], contains: "它属于此刻")
        check.label(app.buttons["choose-past"], contains: "它来自过去")
        XCTAssertTrue(app.buttons["choose-now"].isEnabled, caseID)
        XCTAssertTrue(app.buttons["choose-past"].isEnabled, caseID)

    case "now-note--empty", "now-note--written", "now-note--keyboard-long":
        let editor = check.require(app.textViews["note-input"])
        check.value(editor, equals: parts[1] == "empty" ? "" : parts[1] == "written" ? note : longNote)
        XCTAssertTrue(check.require(app.buttons["save-now"]).isEnabled, caseID)
        if parts[1] == "keyboard-long" {
            check.require(app.keyboards.firstMatch)
            check.require(app.buttons["note-editor-done"])
        }

    case "past-time--empty", "past-time--preset", "past-time--custom":
        let start = check.require(app.buttons["start-chat"])
        let custom = check.require(app.textFields["custom-time"])
        for preset in ["昨天", "上个星期", "几个月前", "去年这个时候", "去年夏天", "几年前", "大学时光", "刚工作那会儿", "少年时代", "小时候"] {
            let button = check.require(app.buttons["time-\(preset)"])
            XCTAssertEqual(button.isSelected, parts[1] == "preset" && preset == "昨天", "\(caseID): selected time \(preset)")
        }
        if parts[1] == "custom" {
            check.value(custom, equals: "高三的雨季")
            XCTAssertTrue(start.isEnabled, caseID)
        } else {
            check.empty(custom, placeholder: "比如，高三的雨季")
            XCTAssertEqual(start.isEnabled, parts[1] == "preset", caseID)
        }

    case "chat--opening", "chat--conversation", "chat--offline", "chat--keyboard", "chat--busy":
        check.toggle("chat-ai-toggle", isOn: parts[1] != "offline")
        check.require(app.staticTexts["本地记录"])
        check.require(app.staticTexts["chat-capability-notice"])
        check.require(app.buttons["AI 设置"])
        let input = check.require(check.element("chat-input"))
        if parts[1] == "keyboard" {
            check.value(input, equals: note)
            check.require(app.keyboards.firstMatch)
        } else { check.empty(input, placeholder: "说说那一刻…") }
        let send = check.require(app.buttons["send-message"])
        XCTAssertEqual(send.isEnabled, parts[1] == "keyboard", caseID)
        if parts[1] == "busy" {
            check.require(check.element("chat-thinking-progress"))
            check.require(app.staticTexts["回响正在靠近…"])
            XCTAssertFalse(app.buttons["finish-chat"].exists, caseID)
            XCTAssertFalse(check.require(app.buttons["语音输入"]).isEnabled, caseID)
        } else if parts[1] == "opening" {
            check.require(app.staticTexts.matching(identifier: "message-0").matching(NSPredicate(format: "label == %@", opening)).firstMatch)
            XCTAssertFalse(check.element("message-1").exists, caseID)
            XCTAssertFalse(app.buttons["finish-chat"].exists, caseID)
        } else if parts[1] == "keyboard" {
            XCTAssertFalse(app.buttons["finish-chat"].exists, caseID)
        } else {
            XCTAssertTrue(check.require(app.buttons["finish-chat"]).isEnabled, caseID)
        }
        // LazyVStack removes offscreen messages. Verify an exact loaded fixture
        // message without incorrectly requiring every message in every slice.
        let expectedMessages = [opening, note, followup]
        let loadedFixtureMessage = expectedMessages.enumerated().contains { index, text in
            app.staticTexts.matching(identifier: "message-\(index)").matching(NSPredicate(format: "label == %@", text)).firstMatch.exists
        }
        XCTAssertTrue(loadedFixtureMessage, "\(caseID): no expected transcript message in the accessibility snapshot")

    case "diary--enabled", "diary--disabled", "diary--editing", "diary--long":
        let enabled = parts[1] != "disabled"
        check.toggle("diary-toggle", isOn: enabled)
        XCTAssertTrue(check.require(app.buttons["save-past"]).isEnabled, caseID)
        XCTAssertFalse(check.element("diary-generating").exists, caseID)
        if !enabled {
            XCTAssertFalse(check.element("diary-content").exists, caseID)
            XCTAssertFalse(check.element("diary-editor").exists, caseID)
            XCTAssertFalse(app.buttons["edit-diary"].exists, caseID)
        } else if parts[1] == "editing" {
            check.value(check.element("diary-editor"), equals: note)
            check.label(app.buttons["edit-diary"], equals: "完成编辑")
            XCTAssertFalse(check.element("diary-content").exists, caseID)
        } else {
            check.label(app.staticTexts["diary-content"], equals: parts[1] == "long" ? longNote : note)
            check.label(app.buttons["edit-diary"], equals: "编辑日记")
            XCTAssertFalse(check.element("diary-editor").exists, caseID)
        }

    case "timeline--empty":
        check.require(app.staticTexts["这里还很安静"])
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.entry.")).count, 0, caseID)
    case "timeline--populated":
        let entry = check.require(app.buttons[entryID])
        check.label(entry, contains: note)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.entry.")).count, 1, caseID)
        XCTAssertFalse(app.staticTexts["这里还很安静"].exists, caseID)

    case "detail--now", "detail--past", "detail--transcript-expanded":
        let past = parts[1] != "now"
        check.require(app.staticTexts[past ? "去年夏天" : "此刻"])
        check.label(app.staticTexts["detail.content"], equals: past ? longNote : note)
        XCTAssertTrue(check.require(app.buttons["delete-memory"]).isEnabled, caseID)
        check.require(app.buttons["open-card"])
        if past {
            let expanded = parts[1] == "transcript-expanded"
            check.label(app.buttons["toggle-transcript"], equals: expanded ? "收起当时的对话" : "看看当时的对话")
            if expanded {
                for text in ["米洛：\(opening)", "我：\(note)", "米洛：\(followup)"] { check.require(app.staticTexts[text]) }
            } else { XCTAssertFalse(app.staticTexts["我：\(note)"].exists, caseID) }
        } else { XCTAssertFalse(app.buttons["toggle-transcript"].exists, caseID) }
    case "detail--missing":
        check.require(app.staticTexts["这段回忆已经飘走了。"])
        XCTAssertFalse(check.require(app.buttons["delete-memory"]).isEnabled, caseID)
        XCTAssertFalse(check.element("detail.content").exists, caseID)
        XCTAssertFalse(app.buttons["open-card"].exists, caseID)

    case "card--planet-letter", "card--orbit-theatre":
        for template in ["planet-letter", "orbit-theatre"] {
            let button = check.require(app.buttons["card-template-\(template)"])
            XCTAssertEqual(button.isSelected, template == parts[1], "\(caseID): template \(template)")
        }
        check.require(check.element("card.preview"))
        check.label(check.element("card-templates-heading"), contains: parts[1] == "planet-letter" ? "1 / 2" : "2 / 2")
        check.require(app.buttons["share-card"])
        check.require(app.buttons["save-card"])

    case "account--local", "account--remote", "account--password-form", "account--export":
        let remote = parts[1] == "remote" || parts[1] == "password-form"
        check.label(app.staticTexts["account-login-method-value"], equals: remote ? "邮箱登录" : "本地体验账号")
        check.label(app.staticTexts["account-bound-email-value"], equals: remote ? "milo@example.com" : "未绑定")
        check.require(app.buttons["account-logout"])
        check.require(app.buttons["account-delete"])
        if remote { check.require(app.buttons["account-password-toggle"]) }
        else { XCTAssertFalse(app.buttons["account-password-toggle"].exists, caseID) }
        if parts[1] == "password-form" {
            check.require(app.textFields["account-password-code"])
            check.require(app.secureTextFields["account-new-password"])
            check.require(app.secureTextFields["再次输入新密码"])
            check.require(app.buttons["保存新密码"])
            check.label(app.buttons["account-password-toggle"], contains: "收起")
        } else {
            XCTAssertFalse(app.textFields["account-password-code"].exists, caseID)
            XCTAssertFalse(app.secureTextFields["account-new-password"].exists, caseID)
        }
        // This fixture is the export-entry screen, not a generated file/share sheet.
        if parts[1] == "export" {
            check.label(app.buttons["account-export-json"], equals: "导出 JSON（完整数据）")
            check.label(app.buttons["account-export-markdown"], equals: "导出 Markdown（方便阅读）")
            XCTAssertTrue(app.buttons["account-export-json"].isEnabled, caseID)
            XCTAssertTrue(app.buttons["account-export-markdown"].isEnabled, caseID)
        }

    case "ai-settings--hosted", "ai-settings--personal", "ai-settings--missing-config", "ai-settings--consent", "ai-settings--connection-error":
        let personal = ["personal", "consent", "connection-error"].contains(parts[1])
        check.toggle("ai-enabled", isOn: true)
        check.require(app.buttons["ai-source-personal"])
        check.require(app.buttons["ai-source-hosted"])
        check.value(app.buttons["ai-consent"], equals: parts[1] == "consent" ? "已同意" : "未同意")
        XCTAssertTrue(check.require(app.buttons["ai-save"]).isEnabled, caseID)
        if personal {
            check.label(app.buttons["ai-provider"], equals: "DeepSeek")
            check.value(check.element("ai-base-url"), equals: "https://api.deepseek.com/v1")
            check.value(check.element("ai-model"), equals: "deepseek-chat")
            check.require(app.secureTextFields["ai-api-key"])
            check.require(app.buttons["ai-test-connection"])
            XCTAssertFalse(check.element("ai-hosted-unavailable").exists, caseID)
        } else {
            check.label(app.staticTexts["ai-hosted-unavailable"], equals: "尚未接通：此安装包缺少后台公网 HTTPS 地址。")
            check.require(app.staticTexts["MILO 星球会员"])
            XCTAssertFalse(check.require(app.buttons["订阅暂未开放"]).isEnabled, caseID)
            XCTAssertFalse(check.element("ai-base-url").exists, caseID)
            XCTAssertFalse(app.secureTextFields["ai-api-key"].exists, caseID)
        }
        if parts[1] == "connection-error" {
            check.visibleError("account-error", text: "连接失败，请检查网络、URL 和模型服务状态。")
        } else { XCTAssertFalse(check.element("account-error").exists, caseID) }
    default:
        XCTFail("No production-state assertions for \(caseID)")
    }
}

@MainActor
private struct ParityStateCheck {
    let caseID: String
    let app: XCUIApplication

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    @discardableResult
    func require(_ element: XCUIElement) -> XCUIElement {
        XCTAssertTrue(element.exists || element.waitForExistence(timeout: 3), "\(caseID): required production element is missing")
        return element
    }
    func label(_ element: XCUIElement, equals expected: String) {
        XCTAssertEqual(require(element).label, expected, caseID)
    }
    func label(_ element: XCUIElement, contains expected: String) {
        XCTAssertTrue(require(element).label.contains(expected), "\(caseID): missing label content \(expected)")
    }
    func value(_ element: XCUIElement, equals expected: String) {
        XCTAssertEqual(require(element).value as? String, expected, caseID)
    }
    func empty(_ element: XCUIElement, placeholder: String) {
        let value = require(element).value as? String
        XCTAssertTrue(value == "" || value == placeholder, "\(caseID): input should be empty, not fixture/user text")
    }
    func toggle(_ identifier: String, isOn: Bool) {
        value(app.switches[identifier], equals: isOn ? "1" : "0")
    }
    func visibleError(_ identifier: String, text: String) {
        let error = require(app.staticTexts[identifier])
        XCTAssertFalse(error.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(caseID): blank error")
        XCTAssertEqual(error.label, text, caseID)
        // Capture asserts initial visibility separately. This check also runs
        // after full-page scrolling, when this same error can be offscreen.
    }
    func alert(title: String, message: String, cancel: String, destructive: String) {
        let alert = require(app.alerts[title])
        XCTAssertEqual(app.alerts.count, 1, caseID)
        label(alert.staticTexts[title], equals: title)
        label(alert.staticTexts[message], equals: message)
        for label in [cancel, destructive] {
            let button = require(alert.buttons[label])
            XCTAssertTrue(button.isHittable && button.isEnabled, "\(caseID): modal action \(label) must be available")
        }
    }
}

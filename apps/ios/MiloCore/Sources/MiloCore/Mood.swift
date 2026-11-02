import Foundation

/// Shared vocabulary; the home dial uses `primaryMoods` rather than all cases.
public enum Mood: String, Codable, CaseIterable, Identifiable, Sendable {
    case joyful, bright, okay, calm, heavy, low
    case veryLow = "very-low"
    case lonely, sad, angry, afraid, disappointed, anxious, aggrieved, embarrassed

    public static let primaryMoods: [Mood] = [.joyful, .bright, .okay, .calm, .heavy, .low, .veryLow]
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .joyful: "雀跃"
        case .bright: "明亮"
        case .okay: "还不错"
        case .calm: "平静"
        case .heavy: "有些沉"
        case .low: "低落"
        case .veryLow: "非常低落"
        case .lonely: "孤独"
        case .sad: "悲伤"
        case .angry: "愤怒"
        case .afraid: "害怕"
        case .disappointed: "失望"
        case .anxious: "焦虑"
        case .aggrieved: "委屈"
        case .embarrassed: "尴尬"
        }
    }
    public var valence: Int {
        switch self {
        case .joyful: 3
        case .bright: 2
        case .okay: 1
        case .calm: 0
        case .heavy, .anxious, .embarrassed: -1
        case .low, .lonely, .angry, .afraid, .disappointed, .aggrieved: -2
        case .veryLow, .sad: -3
        }
    }
    /// Exact HarmonyOS prefix + polarity list, deduplicated in order.
    public var descriptorWords: [String] {
        let prefix: [String] = switch self {
        case .veryLow: ["沉到底", "撑不住", "空荡", "无望"]
        case .low: ["低沉", "消沉", "沮丧", "提不起劲"]
        case .heavy: ["沉重", "疲惫", "压着", "迟滞"]
        case .calm: ["平静", "安稳", "松弛", "清醒"]
        case .okay: ["还不错", "舒心", "安然", "有盼头"]
        case .bright: ["明亮", "开朗", "有希望", "焕然"]
        case .joyful: ["雀跃", "兴奋", "欢欣", "想庆祝"]
        case .lonely: ["孤单", "被落下", "想念", "疏离"]
        case .sad: ["悲伤", "心碎", "想哭", "哀痛"]
        case .angry: ["恼火", "愤懑", "被冒犯", "想反抗"]
        case .afraid: ["恐惧", "不安全", "警觉", "想躲开"]
        case .disappointed: ["落空", "心凉", "遗憾", "不甘"]
        case .anxious: ["焦灼", "不安", "紧绷", "停不下来"]
        case .aggrieved: ["委屈", "被误解", "忍着", "想被看见"]
        case .embarrassed: ["窘迫", "不自在", "难为情", "想逃开"]
        }
        let base: [String]
        if valence < 0 {
            base = ["难过", "失落", "孤独", "担心", "疲惫", "压抑", "委屈", "害怕", "遗憾", "迷茫", "烦躁", "无力"]
        } else if valence > 0 {
            base = ["轻盈", "温暖", "喜悦", "期待", "安心", "满足", "有力量", "被理解", "感动", "雀跃", "明亮", "自在"]
        } else {
            base = ["平静", "安稳", "松弛", "清醒", "踏实", "淡然", "宁静", "柔和", "从容", "平衡", "舒展", "自在"]
        }
        var seen = Set<String>()
        return Array((prefix + base).filter { seen.insert($0).inserted }.prefix(12))
    }
}

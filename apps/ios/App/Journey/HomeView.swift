import SwiftUI
import MiloCore

struct HomeView: View {
    @Bindable var model: JournalModel
    @State private var confirmNewDraft = false
    @State private var pendingMood: Mood = .calm
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    if model.hasUnfinishedDraft && model.draft.page == "home" {
                        Button("继续未收藏的草稿", action: model.resumeDraft)
                            .frame(minHeight: 44).accessibilityIdentifier("resume-draft")
                    }
                    if model.draft.page == "home-words" {
                        wordContent
                    } else {
                        moodContent
                    }
                }.font(.subheadline).foregroundStyle(MiloTheme.dim).padding(.horizontal, 24).padding(.top, 8)
                    .frame(minHeight: max(500, geometry.size.height - 20), alignment: .top)
            }.parityScrollMetrics("home").scrollIndicators(.hidden)
        }.onAppear { pendingMood = model.draft.mood }
        .confirmationDialog("开始新记录会替换未收藏的草稿。", isPresented: $confirmNewDraft, titleVisibility: .visible) {
            Button("开始新的记录", role: .destructive) { model.beginMoodWords(mood: pendingMood) }
            Button("继续草稿") { model.resumeDraft() }
            Button("取消", role: .cancel) {}
        }
    }

    @ViewBuilder private var header: some View {
        let brand = Text("MILO-米洛").font(.caption2).tracking(3).foregroundStyle(MiloTheme.hint)
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                brand.fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 20) { navigation; Spacer(minLength: 0) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
        } else {
            HStack(spacing: 18) { brand; Spacer(minLength: 4); navigation }.frame(minHeight: 44)
        }
    }
    @ViewBuilder private var navigation: some View {
        Button(model.entries.isEmpty ? "回忆" : "回忆 · \(model.entries.count)") { model.go("timeline") }
            .accessibilityIdentifier("open-timeline")
        Button("我的") { model.go("account") }.accessibilityIdentifier("open-account")
    }

    private var moodContent: some View {
        VStack(spacing: 0) {
            MoodOrbit(mood: $pendingMood)
                .frame(height: 400)
                .padding(.top, 36)
                .padding(.horizontal, -24)
            Text("沿圆环旋转，或点击任意情绪直接切换")
                .font(.caption).foregroundStyle(MiloTheme.hint).multilineTextAlignment(.center).padding(.top, 12).padding(.bottom, 22)
            MiloPrimaryButton(title: model.hasUnfinishedDraft ? "开始新的记录" : "就是这种感觉") {
                if model.hasUnfinishedDraft { confirmNewDraft = true } else { model.beginMoodWords(mood: pendingMood) }
            }.accessibilityIdentifier("confirm-mood").frame(maxWidth: 240).padding(.bottom, 24)
        }.frame(maxWidth: .infinity)
    }
    private var wordContent: some View {
        VStack(spacing: 0) {
            HStack { MiloBackButton { model.draft.labels = []; model.go("home") }; Spacer() }.padding(.top, 10)
            Text("如果要给它一个名字").font(MiloTheme.serif(22)).foregroundStyle(MiloTheme.ink).multilineTextAlignment(.center).padding(.top, 4)
            Spacer(minLength: 18)
            DescriptorOrbit(mood: model.draft.mood, selected: $model.draft.labels).padding(.horizontal, -24)
            Spacer(minLength: 18)
            Text(model.draft.labels.isEmpty ? "转动词环，挑选最多三个贴近的词" : model.draft.labels.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(MiloTheme.dim).multilineTextAlignment(.center).padding(.bottom, 8)
            Text("没有合适的也没关系，可以直接继续")
                .font(.caption).foregroundStyle(MiloTheme.hint).multilineTextAlignment(.center).padding(.bottom, 22)
            MiloPrimaryButton(title: "带着它继续") { model.go("classify") }
                .accessibilityIdentifier("confirm-words").padding(.bottom, 24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MoodOrbit: View {
    @Binding var mood: Mood
    @State private var position: Double = 3
    @State private var lastAngle: Double?
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let moods = Mood.primaryMoods
    private var active: Int { (Int(position.rounded()) % 7 + 7) % 7 }
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Circle().stroke(.white.opacity(dragging ? 0.32 : 0.2), style: StrokeStyle(lineWidth: 0.7, dash: [1, 4]))
                    .frame(width: 288, height: 288).position(center)
                MoodPlanet(mood: moods[active], size: 246).position(center)
                ForEach(Array(moods.enumerated()), id: \.element.id) { index, item in
                    let angle = (180 + (Double(index) - position) * 360 / 7) * .pi / 180
                    let selected = index == active
                    Rectangle().fill(.white.opacity(selected ? 0.9 : 0.4))
                        .frame(width: 1, height: selected ? 18 : 10)
                        .rotationEffect(.radians(angle))
                        .position(x: center.x + sin(angle) * 144, y: center.y - cos(angle) * 144)
                    Button { settle(Double(index) + ((position - Double(index)) / 7).rounded() * 7) } label: {
                        Text(item.title).font(MiloTheme.serif(selected ? 22 : 12, relativeTo: .caption))
                            .foregroundStyle(selected ? .white : item.valence > 0 ? Color(red: 0.95, green: 0.86, blue: 0.75) : MiloTheme.dim)
                            .fixedSize().padding(8).frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain)
                        .position(x: center.x + sin(angle) * 174, y: center.y - cos(angle) * 174)
                        .accessibilityIdentifier("mood-\(item.rawValue)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.contentShape(OrbitDragRegion(), eoFill: true)
                .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { value in
                    let dx = value.location.x - center.x, dy = value.location.y - center.y
                    guard hypot(dx, dy) > 22 else { return }
                    let angle = atan2(dy, dx) * 180 / .pi
                    if let lastAngle {
                        let delta = (angle - lastAngle + 540).truncatingRemainder(dividingBy: 360) - 180
                        position -= delta / (360 / 7)
                        mood = moods[active]
                    }
                    lastAngle = angle; dragging = true
                }.onEnded { _ in lastAngle = nil; dragging = false; settle(position.rounded()) })
        }.onAppear { position = Double(moods.firstIndex(of: mood) ?? 3) }
            .sensoryFeedback(.selection, trigger: active)
    }
    private func settle(_ value: Double) {
        withAnimation(reduceMotion ? nil : .timingCurve(0.22, 0.72, 0.18, 1, duration: 0.52)) { position = value }
        mood = moods[(Int(value.rounded()) % 7 + 7) % 7]
    }
}

private struct DescriptorOrbit: View {
    let mood: Mood
    @Binding var selected: [String]
    @State private var angle: Double = 0
    @State private var lastAngle: Double?
    @State private var confirmNewDraft = false
    @State private var pendingMood: Mood = .calm
    @Environment(\.dynamicTypeSize) private var textSize
    private var words: [String] { mood.descriptorWords }
    private var focus: Int { (Int((-angle / 30).rounded()) % 12 + 12) % 12 }
    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let center = CGPoint(x: width / 2, y: 165)
                ZStack {
                    MoodPlanet(mood: mood, size: 144).position(center)
                    ForEach(Array(words.enumerated()), id: \.element) { index, word in
                        wordButton(word, index: index, center: center, width: width)
                    }
                }.contentShape(OrbitDragRegion(), eoFill: true)
                    .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                        let current = atan2(value.location.y - center.y, value.location.x - center.x) * 180 / .pi
                        if let lastAngle { angle += (current - lastAngle + 540).truncatingRemainder(dividingBy: 360) - 180 }
                        lastAngle = current
                    }.onEnded { _ in lastAngle = nil; withAnimation(.easeOut(duration: 0.4)) { angle = (angle / 30).rounded() * 30 } })
            }.frame(height: 330).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            if textSize.isAccessibilitySize {
                // A readable alternative supplements the unchanged ring at accessibility sizes.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                    ForEach(words, id: \.self) { word in
                        Button { toggle(word) } label: {
                            Text(word).font(.body).foregroundStyle(selected.contains(word) ? .white : MiloTheme.dim)
                                .frame(maxWidth: .infinity, minHeight: 44).padding(8)
                                .background(MiloTheme.accent.opacity(selected.contains(word) ? 0.25 : 0.05), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 24)
            }
        }.sensoryFeedback(.selection, trigger: selected)
    }
    private func wordButton(_ word: String, index: Int, center: CGPoint, width: CGFloat) -> some View {
        let radians = (Double(index) * 30 - 90 + angle) * .pi / 180
        let picked = selected.contains(word)
        let highlighted = picked || index == focus
        let radius: CGFloat = min(128, (width - 90) / 2)
        return Button { toggle(word) } label: {
            VStack(spacing: 2) {
                Text(word).font(MiloTheme.serif(highlighted ? 19 : 14, relativeTo: .caption))
                    .foregroundStyle(highlighted ? .white : MiloTheme.hint)
                    .shadow(color: highlighted ? MiloTheme.accent.opacity(0.65) : .clear, radius: 9)
                Circle().fill(picked ? MiloTheme.dim : .clear).frame(width: 5, height: 5)
            }.fixedSize().frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain)
            .position(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * 128)
            .accessibilityIdentifier("word-\(index)")
            .accessibilityAddTraits(picked ? .isSelected : [])
    }
    private func toggle(_ word: String) {
        if selected.contains(word) { selected.removeAll { $0 == word } }
        else if selected.count < 3 { selected.append(word) }
    }
}

/// Ring drags leave the page edges free for ordinary vertical scrolling.
private struct OrbitDragRegion: Shape {
    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        let outer = CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
        var path = Path(ellipseIn: outer)
        path.addEllipse(in: CGRect(x: rect.midX - 30, y: rect.midY - 30, width: 60, height: 60))
        return path
    }
}

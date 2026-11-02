import SwiftUI
import UIKit
import MiloCore

/// Both preview and exported PNG use the same 1080-unit artwork. Geometry mirrors
/// HarmonyOS CardArt (the production renderer), including its variable paper height.
@MainActor
struct CardArtworkView: View {
    let entry: JournalEntry
    let template: CardTemplate
    var body: some View {
        Image(uiImage: CardArtworkRaster.image(entry: entry, template: template))
            .resizable()
            .aspectRatio(1080 / designHeight, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(template.title)，\(CardCopy(entry: entry).heading)，\(entry.mood.title)，\(CardCopy(entry: entry).body)")
    }

    var designHeight: CGFloat { CardArtPainter.height(entry: entry, template: template) }
}

/// UIKit owns the complete drawing bounds. SwiftUI only receives a bitmap with
/// a fixed aspect ratio, so artwork cannot contribute an unbounded layout size.
@MainActor
enum CardArtworkRaster {
    private static let byteLimit = 32 * 1024 * 1024
    private static let cache: NSCache<CardRasterKey, UIImage> = {
        let cache = NSCache<CardRasterKey, UIImage>()
        cache.countLimit = 12
        cache.totalCostLimit = byteLimit
        return cache
    }()

    static func image(entry: JournalEntry, template: CardTemplate) -> UIImage {
        let key = CardRasterKey(entry: entry, template: template, thumbnail: false)
        if let cached = cache.object(forKey: key) { return cached }
        let size = CGSize(width: 1080, height: CardArtPainter.height(entry: entry, template: template))
        let image = UIGraphicsImageRenderer(size: size, format: format()).image { renderer in
            CardArtPainter(context: renderer.cgContext, entry: entry, template: template).draw()
        }
        retain(image, for: key)
        return image
    }

    static func thumbnail(entry: JournalEntry, template: CardTemplate) -> UIImage {
        let key = CardRasterKey(entry: entry, template: template, thumbnail: true)
        if let cached = cache.object(forKey: key) { return cached }
        let artwork = image(entry: entry, template: template)
        let size = CGSize(width: 320, height: 200)
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format()).image { renderer in
            renderer.cgContext.clip(to: CGRect(origin: .zero, size: size))
            // Keep the previous top-cropped preview, now in an actual 320×200
            // bitmap rather than a full-height drawing inside the button.
            artwork.draw(in: CGRect(x: 0, y: 0, width: size.width,
                                   height: artwork.size.height * size.width / artwork.size.width))
        }
        retain(thumbnail, for: key)
        return thumbnail
    }

    static func clear() { cache.removeAllObjects() }

    private static func format() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return format
    }

    private static func retain(_ image: UIImage, for key: CardRasterKey) {
        guard let cgImage = image.cgImage else { return }
        let cost = cgImage.bytesPerRow * cgImage.height
        guard cost <= byteLimit else { return }
        cache.setObject(image, forKey: key, cost: cost)
    }
}

/// Equality includes every entry field, not just the saved ID. Editing diary,
/// labels, timestamps or a template cannot return a stale cached card.
private final class CardRasterKey: NSObject {
    let entry: JournalEntry
    let template: CardTemplate
    let thumbnail: Bool
    let timeZoneIdentifier: String

    init(entry: JournalEntry, template: CardTemplate, thumbnail: Bool) {
        self.entry = entry
        self.template = template
        self.thumbnail = thumbnail
        timeZoneIdentifier = TimeZone.current.identifier
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(entry.id)
        hasher.combine(template)
        hasher.combine(thumbnail)
        hasher.combine(timeZoneIdentifier)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CardRasterKey else { return false }
        return entry == other.entry && template == other.template && thumbnail == other.thumbnail
            && timeZoneIdentifier == other.timeZoneIdentifier
    }
}

@MainActor
private struct CardArtPainter {
    let context: CGContext
    let entry: JournalEntry
    let template: CardTemplate
    private var copy: CardCopy { CardCopy(entry: entry) }
    private var canvasHeight: CGFloat { Self.height(entry: entry, template: template) }
    private var ink: UIColor { color(0x17151d) }
    private var palette: [UIColor] {
        switch sheet.number {
        case 1: return [color(0x3a1f5a), color(0x1d1130), color(0x9d7bd6)]
        case 3: return [color(0x5b3e7a), color(0x2a1c4a), color(0xc2a8e8)]
        case 4: return [color(0x7a6fa6), color(0x3e3863), color(0xddd0f3)]
        case 5: return [color(0x8b82bd), color(0x4a4577), color(0xe7dcf7)]
        default: return [color(0x6b5a8e), color(0x352c52), color(0xd2c8ec)]
        }
    }

    static func height(entry: JournalEntry, template: CardTemplate) -> CGFloat {
        let count = wrap(CardCopy(entry: entry).body, font: serif(64), width: template == .planetLetter ? 796 : 790).count
        return template == .planetLetter ? 1434 + CGFloat(max(0, count - 3)) * 88 : 1530 + CGFloat(max(0, count - 6)) * 88
    }

    func draw() {
        if template == .planetLetter { ticket() } else { theatre() }
    }

    private func ticket() {
        let extra = canvasHeight - 1434
        let tearY = 1092 + extra
        fill(CGRect(x: 0, y: 0, width: 1080, height: canvasHeight), color(0x0b0b12))
        radial(center: CGPoint(x: 799.2, y: 150), radius: 680,
               colors: [palette[0].withAlphaComponent(0.16), color(0x7e69b8, 0.08), .clear], locations: [0, 0.5, 1])
        stars(count: 76, tint: color(0xddd5f2))
        let paper = CGRect(x: 88, y: 44, width: 904, height: 1346 + extra)
        context.saveGState()
        context.addPath(rounded(paper, 58)); context.clip()
        fill(paper, color(0xf0eff2))
        gradient(in: CGRect(x: 88, y: 44, width: 904, height: tearY - 44),
                 colors: [color(0xb8a7e9), color(0xd6ccea), color(0xe4def3)], locations: [0, 0.5, 1],
                 start: CGPoint(x: 88, y: 44), end: CGPoint(x: 992, y: tearY))
        context.setFillColor(UIColor.white.withAlphaComponent(0.2).cgColor)
        context.beginPath(); context.move(to: CGPoint(x: 578, y: 44))
        context.addLine(to: CGPoint(x: 992, y: 44)); context.addLine(to: CGPoint(x: 992, y: 394))
        context.addLine(to: CGPoint(x: 418, y: 764)); context.closePath(); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset: .zero, blur: 42, color: UIColor.black.withAlphaComponent(0.38).cgColor)
        strokeRound(paper, radius: 58, color: .white.withAlphaComponent(0.12), width: 2)
        context.restoreGState()

        for x in [CGFloat(132), 456, 790] { text("MILO", x, 111, font: sans(29, .bold), color: ink) }
        hatch(x: 228, y: 101, width: 184); hatch(x: 556, y: 101, width: 186)
        artwork(x: 130, y: 130, width: 86)
        let secondary = entry.labels.first { $0 != entry.mood.title }
        let identity = entry.mood.title + (secondary.map { " · \($0)" } ?? "")
        text(fit(identity, font: sans(46, .bold), width: 480), 238, 204, font: sans(46, .bold), color: ink)
        text("PLANET ID: \(memoryTicketID(for: entry))", 238, 239, font: mono(24), color: ink.withAlphaComponent(0.66))
        context.saveGState(); context.translateBy(x: 846, y: 202); context.rotate(by: 0.045)
        stroke(CGRect(x: -94, y: -41, width: 188, height: 82), ink, 3)
        text("ORIGINAL", 0, -8, font: mono(16), color: ink, centered: true)
        text("MEMORY", 0, 18, font: mono(16), color: ink, centered: true)
        context.restoreGState()

        let showcase = CGRect(x: 140, y: 292, width: 800, height: 355)
        fillRound(showcase, radius: 34, color: color(0xf8f6fb, 0.7))
        strokeRound(showcase, radius: 34, color: ink, width: 5)
        context.saveGState()
        context.addPath(rounded(showcase.insetBy(dx: 4, dy: 4), 30)); context.clip()
        context.saveGState(); context.translateBy(x: 525, y: 465); context.rotate(by: -0.16)
        for index in 0..<3 {
            let rx = CGFloat(470 + index * 72), ry = CGFloat(80 + index * 30)
            ellipse(CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), color: color(0x5b4884, 0.2), width: 2)
        }
        context.restoreGState()
        artwork(x: 394, y: 239, width: 292)
        context.restoreGState()
        fillRound(CGRect(x: 320, y: 591, width: 440, height: 66), radius: 15, color: ink)
        text(fit(copy.heading, font: sans(40, .bold), width: 400), 540, 638, font: sans(40, .bold), color: .white, centered: true)

        let tags = entry.labels.isEmpty ? [entry.mood.title] : Array(entry.labels.prefix(3))
        var tagX: CGFloat = 140
        for tag in tags {
            let label = "# \(tag)", font = sans(34, .bold)
            let width = measure(label, font: font) + 36
            fillRound(CGRect(x: tagX, y: 694, width: width, height: 54), radius: 27, color: .white.withAlphaComponent(0.18))
            strokeRound(CGRect(x: tagX, y: 694, width: width, height: 54), radius: 27, color: ink.withAlphaComponent(0.58), width: 2)
            text(label, tagX + 18, 733, font: font, color: ink)
            tagX += width + 18
        }
        text("MEMORY NOTE / 025", 142, 766, font: mono(17), color: ink.withAlphaComponent(0.62), tracking: 4)
        for (index, line) in Self.wrap(copy.body, font: Self.serif(64), width: 796).enumerated() {
            text(line, 142, 860 + CGFloat(index) * 88, font: Self.serif(64), color: ink)
        }
        context.saveGState(); context.setLineDash(phase: 0, lengths: [16, 12])
        line(CGPoint(x: 144, y: tearY), CGPoint(x: 936, y: tearY), ink.withAlphaComponent(0.68), 3)
        context.restoreGState()
        for x in [CGFloat(88), 992] { circle(x, tearY, radius: 28, color: color(0x0b0b12)) }
        burst(x: 196, y: 1229 + extra)
        text("HEY~", 196, 1237 + extra, font: sans(21, .bold), color: ink, centered: true)
        text("收下这颗星", 284, 1209 + extra, font: sans(43, .bold), color: ink)
        text("记忆编号已与这颗星绑定。", 286, 1250 + extra, font: sans(30), color: ink.withAlphaComponent(0.7))
        text("MEMORY CODE", 720, 1164 + extra, font: mono(17), color: ink)
        strokeRound(CGRect(x: 720, y: 1180 + extra, width: 224, height: 58), radius: 14, color: ink.withAlphaComponent(0.48), width: 2)
        text(memoryTicketID(for: entry), 832, 1216 + extra, font: mono(17), color: ink, centered: true)
        text("\(CollectionDate.archive(entry.createdAt))  /  MILO ARCHIVE", 540, 1356 + extra, font: sans(32), color: ink.withAlphaComponent(0.72), centered: true)
        gradient(in: CGRect(x: 128, y: tearY + 2, width: 824, height: 2),
                 colors: [palette[1].withAlphaComponent(0), palette[0].withAlphaComponent(0.08), palette[1].withAlphaComponent(0)],
                 locations: [0, 0.5, 1], start: CGPoint(x: 88, y: tearY), end: CGPoint(x: 992, y: tearY))
    }

    private func theatre() {
        let extra = canvasHeight - 1530
        gradient(in: CGRect(x: 0, y: 0, width: 1080, height: canvasHeight),
                 colors: [color(0x332a59), color(0x171831), color(0x080b18)], locations: [0, 0.55, 1],
                 start: .zero, end: CGPoint(x: 1080, y: 1434))
        stars(count: 104, tint: color(0xe5def7))
        context.saveGState(); context.translateBy(x: 314, y: 300); context.rotate(by: -0.27)
        for index in 0..<3 {
            let rx = CGFloat(300 + index * 72), ry = CGFloat(100 + index * 23)
            ellipse(CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), color: color(0xc5b5ee, 0.46 - CGFloat(index) * 0.1), width: 2)
        }
        context.restoreGState()
        artwork(x: 160, y: 82, width: 264)
        // Preserve the brand line inside the 440-unit right column rather than
        // letting its last letters clip at the paper edge on iOS font metrics.
        text("ORBITAL MEMORY THEATRE", 566, 132, font: sans(19, .bold), color: color(0xe4dcf7, 0.76), tracking: 2.7)
        let heading = Self.wrap(copy.heading, font: sans(72, .bold), width: 440)
        for (index, line) in heading.prefix(3).enumerated() {
            let visible = index == 2 && heading.count > 3 ? String(line.dropLast()) + "…" : line
            text(fit(visible, font: sans(72, .bold), width: 440), 566, 224 + CGFloat(index) * 78, font: sans(72, .bold), color: .white)
        }
        if !copy.labels.isEmpty {
            fillRound(CGRect(x: 566, y: 450, width: 390, height: 52), radius: 26, color: color(0x0c0c1b))
            text(fit(copy.labels, font: sans(34, .bold), width: 338), 592, 487, font: sans(34, .bold), color: color(0xd5c9f1))
        }
        let panel = CGRect(x: 92, y: 634, width: 896, height: 640 + extra)
        fillRound(panel, radius: 34, color: color(0x070816, 0.58))
        strokeRound(panel, radius: 34, color: color(0xcabbef, 0.48), width: 2)
        text("PLAYBACK / MEMORY 07", 140, 694, font: sans(20, .bold), color: color(0xc6b4ed), tracking: 5)
        for (index, line) in Self.wrap(copy.body, font: Self.serif(64), width: 790).enumerated() {
            text(line, 140, 784 + CGFloat(index) * 88, font: Self.serif(64), color: color(0xf6f4fc, 0.9))
        }
        context.saveGState(); context.translateBy(x: 843, y: 1350 + extra); context.rotate(by: -0.07)
        stroke(CGRect(x: -126, y: -35, width: 252, height: 70), color(0xcdbfef, 0.8), 2)
        text("MILO ARCHIVE / 07", 0, 7, font: sans(18, .bold), color: color(0xd4c7f1), centered: true)
        context.restoreGState()
        text("\(CollectionDate.full(entry.createdAt)) · 记于米洛", 540, canvasHeight - 96, font: sans(36), color: color(0xddd5f1, 0.82), centered: true)
        text("M I L O", 540, canvasHeight - 50, font: sans(22, .bold), color: color(0xcdc1ec, 0.52), centered: true, tracking: 8)
    }

    private var sheet: (number: Int, panel: Int, offset: CGFloat) {
        let names = ["very-low", "low", "heavy", "calm", "okay", "bright", "joyful", "lonely", "sad", "angry", "afraid", "disappointed", "anxious", "aggrieved", "embarrassed"]
        let index = names.firstIndex(of: entry.mood.rawValue) ?? 3
        let panel = index % 3
        return (index / 3 + 1, panel, entry.mood.rawValue == "anxious" ? -9 : [-11, 0, 11][panel])
    }

    private func artwork(x: CGFloat, y: CGFloat, width: CGFloat) {
        let h = width * 2700 / 1748
        let rect = CGRect(x: x, y: y, width: width, height: h)
        radial(center: CGPoint(x: rect.midX, y: rect.midY), radius: max(width, h) * 0.72,
               colors: [palette[0].withAlphaComponent(0.24), palette[0].withAlphaComponent(0)], locations: [0.35, 1])
        if let image = UIImage(named: String(format: "mood_sheet_%02d", sheet.number)) {
            context.saveGState(); context.clip(to: rect)
            let left = CGFloat(sheet.panel) * -100 + sheet.offset
            image.draw(in: CGRect(x: x + left * width / 100, y: y, width: width * 3, height: h))
            context.restoreGState()
        } else {
            context.saveGState()
            context.addEllipse(in: CGRect(x: rect.midX - width * 0.43, y: rect.midY - width * 0.43, width: width * 0.86, height: width * 0.86)); context.clip()
            radial(center: CGPoint(x: rect.midX - width * 0.13, y: rect.midY - width * 0.14), radius: width * 0.57,
                   colors: [palette[2], palette[0], palette[1]], locations: [0, 0.55, 1])
            context.restoreGState()
        }
    }

    private func stars(count: Int, tint: UIColor) {
        var hash: UInt32 = 2_166_136_261
        for ch in entry.id.utf16 { hash = (hash ^ UInt32(ch)) &* 16_777_619 }
        var random = CardRandom(state: hash ^ (template == .planetLetter ? 0x2d16a43f : 0x418be2c7))
        for _ in 0..<count {
            let x = random.next() * 1080, y = random.next() * canvasHeight
            let radius = random.next() * 2.1 + 0.45, alpha = random.next() * 0.56 + 0.16
            circle(x, y, radius: radius, color: tint.withAlphaComponent(alpha))
        }
    }
    private func hatch(x: CGFloat, y: CGFloat, width: CGFloat) {
        for offset in stride(from: CGFloat.zero, to: width, by: 10) {
            line(CGPoint(x: x + offset, y: y + 6), CGPoint(x: x + offset + 5, y: y - 6), ink.withAlphaComponent(0.5), 2)
        }
    }
    private func burst(x: CGFloat, y: CGFloat) {
        let path = CGMutablePath()
        for index in 0..<24 {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 12
            let radius: CGFloat = index.isMultiple(of: 2) ? 63 : 48
            let point = CGPoint(x: x + cos(angle) * radius, y: y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath(); context.addPath(path)
        context.setFillColor(color(0xc5b5ee).cgColor); context.setStrokeColor(ink.cgColor); context.setLineWidth(4)
        context.drawPath(using: .fillStroke)
    }

    private static func serif(_ size: CGFloat) -> UIFont {
        UIFont(name: "SongtiSC-Regular", size: size) ?? UIFont(descriptor: UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) ?? UIFont.systemFont(ofSize: size).fontDescriptor, size: size)
    }
    private func sans(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont { .systemFont(ofSize: size, weight: weight) }
    private func mono(_ size: CGFloat) -> UIFont { .monospacedSystemFont(ofSize: size, weight: .bold) }
    private func measure(_ value: String, font: UIFont) -> CGFloat { (value as NSString).size(withAttributes: [.font: font]).width }
    private static func wrap(_ value: String, font: UIFont, width: CGFloat) -> [String] {
        value.components(separatedBy: "\n").flatMap { paragraph -> [String] in
            if paragraph.trimmingCharacters(in: .whitespaces).isEmpty { return [""] }
            var lines: [String] = [], line = ""
            for char in paragraph {
                let next = line + String(char)
                if !line.isEmpty && (next as NSString).size(withAttributes: [.font: font]).width > width {
                    lines.append(line); line = String(char)
                } else { line = next }
            }
            if !line.isEmpty { lines.append(line) }
            return lines
        }
    }
    private func fit(_ value: String, font: UIFont, width: CGFloat) -> String {
        if measure(value, font: font) <= width { return value }
        var visible = value
        while !visible.isEmpty && measure(visible + "…", font: font) > width { visible.removeLast() }
        return visible + "…"
    }
    private func text(_ value: String, _ x: CGFloat, _ baseline: CGFloat, font: UIFont, color: UIColor, centered: Bool = false, tracking: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: tracking]
        let string = NSAttributedString(string: value, attributes: attributes)
        let originX = centered ? x - string.size().width / 2 : x
        string.draw(at: CGPoint(x: originX, y: baseline - font.ascender))
    }
    private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    private func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath { UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath }
    private func fill(_ rect: CGRect, _ color: UIColor) { context.setFillColor(color.cgColor); context.fill(rect) }
    private func fillRound(_ rect: CGRect, radius: CGFloat, color: UIColor) { context.addPath(rounded(rect, radius)); context.setFillColor(color.cgColor); context.fillPath() }
    private func stroke(_ rect: CGRect, _ color: UIColor, _ width: CGFloat) { context.setStrokeColor(color.cgColor); context.setLineWidth(width); context.stroke(rect) }
    private func strokeRound(_ rect: CGRect, radius: CGFloat, color: UIColor, width: CGFloat) { context.addPath(rounded(rect, radius)); context.setStrokeColor(color.cgColor); context.setLineWidth(width); context.strokePath() }
    private func ellipse(_ rect: CGRect, color: UIColor, width: CGFloat) { context.setStrokeColor(color.cgColor); context.setLineWidth(width); context.strokeEllipse(in: rect) }
    private func circle(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, color: UIColor) { context.setFillColor(color.cgColor); context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)) }
    private func line(_ from: CGPoint, _ to: CGPoint, _ color: UIColor, _ width: CGFloat) { context.setStrokeColor(color.cgColor); context.setLineWidth(width); context.beginPath(); context.move(to: from); context.addLine(to: to); context.strokePath() }
    private func gradient(in rect: CGRect, colors: [UIColor], locations: [CGFloat], start: CGPoint, end: CGPoint) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: locations) else { return }
        context.saveGState(); context.clip(to: rect)
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
    private func radial(center: CGPoint, radius: CGFloat, colors: [UIColor], locations: [CGFloat]) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: locations) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
}

private struct CardRandom {
    var state: UInt32
    mutating func next() -> CGFloat {
        state &+= 0x6d2b79f5
        var value = (state ^ (state >> 15)) &* (state | 1)
        value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
        return CGFloat(value ^ (value >> 14)) / 4_294_967_296
    }
}

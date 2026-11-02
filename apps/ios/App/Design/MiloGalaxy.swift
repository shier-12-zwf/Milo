import SwiftUI
import UIKit
import Observation
import MetalKit

/// The Web renderer's clock and pointer easing, shared by the background and a
/// passive window observer. No gesture or hit-test surface sits above the app.
@MainActor @Observable
final class MiloGalaxyState {
    private(set) var time: Double = 0
    private(set) var pointer = CGPoint(x: 0.5, y: 0.5)
    private(set) var active: Double = 0
    private(set) var paused = true
    private(set) var inactiveDuration: Double = 0
    @ObservationIgnored var renderReady = false
    @ObservationIgnored private var inactiveStartedAt: CFTimeInterval?
    @ObservationIgnored private var applicationIsActive = UIApplication.shared.applicationState == .active
    @ObservationIgnored private var sceneIsActive = false
    @ObservationIgnored private var motionDisabled = true
    @ObservationIgnored private var target = CGPoint(x: 0.5, y: 0.5)
    @ObservationIgnored private var targetActive: Double = 0
    @ObservationIgnored private var previousTimestamp: CFTimeInterval?
    #if DEBUG
    @ObservationIgnored private let clockInstance = UInt32.random(in: 1...UInt32.max)
    @ObservationIgnored private var pauseTime: Double = 0
    @ObservationIgnored private var resumeTime: Double = 0
    @ObservationIgnored private var pauseCount = 0
    @ObservationIgnored private var resumeCount = 0
    @ObservationIgnored private var touchPeakActive: Double = 0
    @ObservationIgnored private var touchStartedAt: CFTimeInterval?
    @ObservationIgnored private var touchDuration: Double = 0
    @ObservationIgnored private var touchSequence = 0
    #endif

    func setSceneActive(_ active: Bool) {
        sceneIsActive = active
        refreshPaused()
    }

    func setMotionDisabled(_ disabled: Bool) {
        motionDisabled = disabled
        refreshPaused()
    }

    // SwiftUI may coalesce scene updates while an app is suspended. UIKit's
    // synchronous lifecycle notifications capture both edges before suspension.
    func setApplicationActive(_ active: Bool) {
        applicationIsActive = active
        if active {
            if let startedAt = inactiveStartedAt {
                inactiveDuration += max(0, CACurrentMediaTime() - startedAt)
                inactiveStartedAt = nil
            }
        } else if inactiveStartedAt == nil {
            inactiveStartedAt = CACurrentMediaTime()
        }
        refreshPaused()
    }

    private func refreshPaused() {
        setPaused(motionDisabled || !applicationIsActive || !sceneIsActive)
    }

    private func setPaused(_ value: Bool) {
        guard paused != value else { return }
        #if DEBUG
        // Sample the clock at the transition, before any resumed advance().
        // These observations cannot freeze or alter the production clock.
        if value { pauseTime = time; pauseCount += 1 }
        else { resumeTime = time; resumeCount += 1 }
        #endif
        paused = value
        previousTimestamp = nil
        // Reduce Motion/inactivity also ends deformation, including a held touch.
        active = 0
        targetActive = 0
    }

    func touch(at point: CGPoint, in size: CGSize, ended: Bool) {
        guard !paused, size.width > 0, size.height > 0 else { return }
        target = CGPoint(x: min(1, max(0, point.x / size.width)),
                         y: min(1, max(0, 1 - point.y / size.height)))
        #if DEBUG
        if !ended && targetActive == 0 {
            touchStartedAt = CACurrentMediaTime()
            touchPeakActive = 0
            touchDuration = 0
            touchSequence += 1
        } else if ended, let startedAt = touchStartedAt {
            touchDuration = max(0, CACurrentMediaTime() - startedAt)
            touchStartedAt = nil
        }
        #endif
        targetActive = ended ? 0 : 1
    }

    func advance(_ timestamp: CFTimeInterval) {
        guard !paused else { previousTimestamp = nil; return }
        let delta = min(0.05, max(0, timestamp - (previousTimestamp ?? timestamp)))
        previousTimestamp = timestamp
        time += delta
        // Web smooths by .12 at 60Hz. Preserve its response time at 30Hz.
        let smoothing = 1 - pow(0.88, delta * 60)
        pointer.x += (target.x - pointer.x) * smoothing
        pointer.y += (target.y - pointer.y) * smoothing
        active += (targetActive - active) * smoothing
        #if DEBUG
        if targetActive > 0 { touchPeakActive = max(touchPeakActive, active) }
        #endif
    }

    #if DEBUG
    var motionProbe: String {
        "{\"time\":\(time),\"active\":\(active),\"x\":\(pointer.x),\"y\":\(pointer.y),\"paused\":\(paused ? 1 : 0),\"renderReady\":\(renderReady ? 1 : 0),\"inactiveDuration\":\(inactiveDuration),\"clockInstance\":\(clockInstance),\"applicationState\":\(UIApplication.shared.applicationState.rawValue),\"sceneActive\":\(sceneIsActive ? 1 : 0),\"pauseTime\":\(pauseTime),\"resumeTime\":\(resumeTime),\"pauseCount\":\(pauseCount),\"resumeCount\":\(resumeCount),\"touchPeakActive\":\(touchPeakActive),\"touchDuration\":\(touchDuration),\"touchSequence\":\(touchSequence)}"
    }
    #endif
}

struct MiloBackground: View {
    let galaxy: MiloGalaxyState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motionDisabled: Bool {
        #if DEBUG
        if ParityFixture.id != nil && !ProcessInfo.processInfo.arguments.contains("--motion-test") { return true }
        #endif
        return reduceMotion
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MiloGalaxySurface(galaxy: galaxy, time: galaxy.time,
                                  pointer: galaxy.pointer, active: galaxy.active)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityHidden(true)
                MiloGalaxyTouchObserver(galaxy: galaxy, paused: galaxy.paused)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            galaxy.setSceneActive(scenePhase == .active)
            galaxy.setMotionDisabled(motionDisabled)
        }
        .onChange(of: scenePhase) { _, phase in galaxy.setSceneActive(phase == .active) }
        .onChange(of: motionDisabled) { _, newValue in galaxy.setMotionDisabled(newValue) }
        .onDisappear { galaxy.setSceneActive(false) }
    }
}

/// Observes touches already delivered to this app's window. A recognizer with
/// cancellation/delay/prevention disabled leaves buttons, scroll views and text
/// selection in charge. It never installs an overlay that receives user input.
private struct MiloGalaxyTouchObserver: UIViewRepresentable {
    let galaxy: MiloGalaxyState
    let paused: Bool
    func makeUIView(context: Context) -> GalaxyObserverView {
        GalaxyObserverView(galaxy: galaxy)
    }
    func updateUIView(_ view: GalaxyObserverView, context: Context) {
        view.refreshPauseState()
    }
    static func dismantleUIView(_ view: GalaxyObserverView, coordinator: ()) {
        view.stopObserving()
    }
}

@MainActor
private final class GalaxyObserverView: UIView {
    private let galaxy: MiloGalaxyState
    private var displayLink: CADisplayLink?
    private weak var observedWindow: UIWindow?
    private var observingLifecycle = false
    private lazy var touchObserver = GalaxyTouchRecognizer(observer: self)
    #if DEBUG
    private let probe = UILabel()
    #endif

    init(galaxy: MiloGalaxyState) {
        self.galaxy = galaxy
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--motion-test") {
            probe.isAccessibilityElement = true
            probe.accessibilityIdentifier = "galaxy-motion"
            probe.accessibilityLabel = "Galaxy motion state"
            probe.text = " "
            probe.textColor = .clear
            probe.frame = CGRect(x: 1, y: 70, width: 1, height: 1)
            addSubview(probe)
        }
        #endif
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if observedWindow !== window {
            observedWindow?.removeGestureRecognizer(touchObserver)
            observedWindow = window
            window?.addGestureRecognizer(touchObserver)
        }
        displayLink?.invalidate()
        displayLink = nil
        if window != nil {
            startLifecycleObservation()
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
            refreshPauseState()
        } else {
            stopObserving()
        }
    }

    private func startLifecycleObservation() {
        guard !observingLifecycle else { return }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(applicationWillResignActive),
                           name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
        // This app uses SwiftUI scenes. Observe the owning UIKit scene directly
        // as well as application notifications; SwiftUI phase updates can lag.
        center.addObserver(self, selector: #selector(sceneWillDeactivate(_:)),
                           name: UIScene.willDeactivateNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneDidActivate(_:)),
                           name: UIScene.didActivateNotification, object: nil)
        observingLifecycle = true
        galaxy.setApplicationActive(UIApplication.shared.applicationState == .active)
    }

    @objc private func applicationWillResignActive() {
        galaxy.setApplicationActive(false)
        refreshPauseState()
    }

    @objc private func applicationDidBecomeActive() {
        galaxy.setApplicationActive(true)
        refreshPauseState()
    }

    @objc private func sceneWillDeactivate(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene,
              scene === observedWindow?.windowScene else { return }
        galaxy.setSceneActive(false)
        galaxy.setApplicationActive(false)
        refreshPauseState()
    }

    @objc private func sceneDidActivate(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene,
              scene === observedWindow?.windowScene else { return }
        galaxy.setSceneActive(true)
        galaxy.setApplicationActive(true)
        refreshPauseState()
    }

    func stopObserving() {
        NotificationCenter.default.removeObserver(self)
        observingLifecycle = false
        displayLink?.invalidate()
        displayLink = nil
        observedWindow?.removeGestureRecognizer(touchObserver)
        observedWindow = nil
        touchObserver.isEnabled = false
    }

    func refreshPauseState() {
        displayLink?.isPaused = galaxy.paused
        if touchObserver.isEnabled == galaxy.paused { touchObserver.isEnabled = !galaxy.paused }
        updateProbe()
    }

    @objc private func tick(_ link: CADisplayLink) {
        galaxy.advance(link.timestamp)
        updateProbe()
    }
    private func updateProbe() {
        #if DEBUG
        probe.accessibilityValue = galaxy.motionProbe
        #endif
    }

    func observe(_ touch: UITouch, ended: Bool) {
        galaxy.touch(at: touch.location(in: self), in: bounds.size, ended: ended)
    }
}

@MainActor
private final class GalaxyTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var observer: GalaxyObserverView?
    private weak var trackedTouch: UITouch?

    init(observer: GalaxyObserverView) {
        self.observer = observer
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else { return }
        trackedTouch = touch
        observer?.observe(touch, ended: false)
        state = .began
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        observer?.observe(touch, ended: false)
        state = .changed
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        observer?.observe(touch, ended: true)
        trackedTouch = nil
        state = .ended
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = trackedTouch { observer?.observe(touch, ended: true) }
        trackedTouch = nil
        state = .cancelled
    }
    override func reset() {
        if let touch = trackedTouch { observer?.observe(touch, ended: true) }
        trackedTouch = nil
        super.reset()
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}

/// Compile the bundled, source-controlled Metal shader once on the device.
/// This keeps the same GPU renderer when Xcode's optional offline Metal
/// compiler component cannot be installed; no shader download is performed.
private struct MiloGalaxySurface: UIViewRepresentable {
    let galaxy: MiloGalaxyState
    let time: Double
    let pointer: CGPoint
    let active: Double

    func makeCoordinator() -> GalaxyMetalRenderer { GalaxyMetalRenderer() }
    func makeUIView(context: Context) -> GalaxyMetalView {
        let view = GalaxyMetalView(frame: .zero, device: context.coordinator.resources?.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.backgroundColor = .black
        view.isOpaque = true
        view.isUserInteractionEnabled = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = false
        view.framebufferOnly = true
        view.delegate = context.coordinator
        galaxy.renderReady = context.coordinator.resources != nil
        return view
    }
    func updateUIView(_ view: GalaxyMetalView, context: Context) {
        context.coordinator.time = Float(time)
        context.coordinator.pointer = SIMD2(Float(pointer.x), Float(pointer.y))
        context.coordinator.active = Float(active)
        view.setNeedsDisplay()
    }
    static func dismantleUIView(_ view: GalaxyMetalView, coordinator: GalaxyMetalRenderer) {
        view.delegate = nil
        view.releaseDrawables()
    }
}

@MainActor
private final class GalaxyMetalView: MTKView {
    override func layoutSubviews() {
        super.layoutSubviews()
        let ratio = min(1.5, max(1, window?.screen.scale ?? 1.5))
        let size = CGSize(width: max(1, (bounds.width * ratio).rounded()),
                          height: max(1, (bounds.height * ratio).rounded()))
        if drawableSize != size {
            drawableSize = size
            setNeedsDisplay()
        }
    }
}

@MainActor
private enum GalaxyMetalCache {
    struct Resources {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
    }
    static let result: Result<Resources, Error> = Result {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let url = Bundle.main.url(forResource: "MiloGalaxy", withExtension: "metal.txt") else {
            throw NSError(domain: "MiloGalaxy", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Metal device or bundled galaxy source is unavailable"])
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let options = MTLCompileOptions()
        if #available(iOS 18.0, *) { options.mathMode = .safe }
        else { options.fastMathEnabled = false }
        let library = try device.makeLibrary(source: source, options: options)
        guard let vertex = library.makeFunction(name: "miloGalaxyVertex"),
              let fragment = library.makeFunction(name: "miloGalaxyFragment") else {
            throw NSError(domain: "MiloGalaxy", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Galaxy shader functions are unavailable"])
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        return Resources(device: device, queue: queue, pipeline: pipeline)
    }
}

@MainActor
private final class GalaxyMetalRenderer: NSObject, MTKViewDelegate {
    let resources: GalaxyMetalCache.Resources?
    var time: Float = 0
    var pointer = SIMD2<Float>(0.5, 0.5)
    var active: Float = 0

    override init() {
        switch GalaxyMetalCache.result {
        case .success(let result): resources = result
        case .failure(let error):
            resources = nil
            NSLog("MILO galaxy shader unavailable: %@", error.localizedDescription)
        }
        super.init()
    }

    // Matches the Metal constant buffer's 32-byte layout exactly.
    private struct Uniforms {
        var size: SIMD2<Float>
        var drawableSize: SIMD2<Float>
        var pointer: SIMD2<Float>
        var time: Float
        var active: Float
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

    func draw(in view: MTKView) {
        guard let resources, view.bounds.width > 0, view.bounds.height > 0,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let command = resources.queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        var uniforms = Uniforms(size: SIMD2(Float(view.bounds.width), Float(view.bounds.height)),
                                drawableSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                                pointer: pointer, time: time, active: active)
        encoder.setRenderPipelineState(resources.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}

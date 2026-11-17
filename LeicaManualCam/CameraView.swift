import SwiftUI
import AVFoundation
import CoreMotion
import AVKit
import PhotosUI
import UniformTypeIdentifiers

private enum Dial: String, CaseIterable { case exp = "EV", iso = "ISO", shutter = "SHUTTER", focus = "FOCUS", wb = "WB", tint = "TINT" }
private enum Drawer: String, CaseIterable { case manual = "MANUAL", looks = "LOOKS", format = "FORMAT", tools = "TOOLS", presets = "PRESETS" }

/// Wraps chips onto new lines instead of overflowing.
private struct Flow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); w = max(w, x - spacing)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

private enum ModeGroup: String, CaseIterable {
    case photo = "PHOTO", video = "VIDEO", exposure = "EXPOSURE"
    var modes: [String] {
        switch self {
        case .photo: return ["PHOTO", "PORTRAIT", "PANO"]
        case .video: return ["VIDEO", "SLOW", "CINEMATIC", "TIMELAPSE"]
        case .exposure: return ["NIGHT", "STARS", "TRAIL", "LONG", "INTERVAL"]
        }
    }
    static func of(_ mode: String) -> ModeGroup { allCases.first { $0.modes.contains(mode) } ?? .photo }
}

private struct Hideable: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        content.opacity(hidden ? 0 : 1).offset(y: hidden ? 8 : 0).allowsHitTesting(!hidden)
            .animation(.easeInOut(duration: 0.28), value: hidden)
    }
}
private extension View { func hideable(_ hidden: Bool) -> some View { modifier(Hideable(hidden: hidden)) } }

private struct CamPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var look: String, strength: Double, aspect: String, grid: Int, timer: Int
    var frame: Bool, burst: Bool, bracket: Bool, peaking: Bool, zebra: Bool, histogram: Bool
    var manualExposure: Bool, iso: Float, shutter: Double
    var manualWB: Bool, temperature: Float, tint: Float
    var mode: String? = nil
    var ratio: String? = nil
    var sky: Bool? = nil
    var dark: Int? = nil
    var grain: Double? = nil, glow: Double? = nil, leak: Int? = nil, dust: Double? = nil, steady: Bool? = nil, bias: Float? = nil
}

private let accent = Theme.champagne
private let videoModes = ["VIDEO", "SLOW", "TIMELAPSE", "CINEMATIC"]

private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Horizon level + steadiness from device motion (publishes only meaningful changes).
private final class LevelMonitor: ObservableObject {
    @Published var angle: Double = 0
    /// 0 steady, 1 hold still, 2 too shaky
    @Published var shake = 0
    private var smoothed = 0.0
    private let motion = CMMotionManager()
    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 20
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            let g = m.gravity
            let a = atan2(g.x, -g.y) * 180 / .pi
            if abs(a - self.angle) > 0.25 { self.angle = a }
            let r = m.rotationRate
            let mag = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            self.smoothed = self.smoothed * 0.8 + mag * 0.2
            let level = self.smoothed < 0.08 ? 0 : self.smoothed < 0.22 ? 1 : 2
            if level != self.shake { self.shake = level }
        }
    }
    func stop() { motion.stopDeviceMotionUpdates() }
}

/// Own view: histogram updates redraw only this panel.
private struct HistogramPanel: View {
    @ObservedObject var model: HistogramModel
    @Binding var rgb: Bool
    var body: some View {
        let d = model.data
        ZStack(alignment: .topTrailing) {
            Canvas { ctx, size in
                let n = d.luma.count
                guard n > 0 else { return }
                let bw = size.width / CGFloat(n)
                func draw(_ values: [Float], _ color: Color) {
                    var path = Path()
                    for (i, v) in values.enumerated() {
                        let h = CGFloat(v) * size.height
                        path.addRect(CGRect(x: CGFloat(i) * bw, y: size.height - h, width: max(1, bw - 0.5), height: h))
                    }
                    ctx.fill(path, with: .color(color))
                }
                if rgb && d.r.count == n {
                    ctx.blendMode = .screen
                    draw(d.r, Color.red.opacity(0.85)); draw(d.g, Color.green.opacity(0.85)); draw(d.b, Color.blue.opacity(0.85))
                } else { draw(d.luma, Color.white.opacity(0.85)) }
            }
            .frame(width: 128, height: 36)
            HStack(spacing: 3) {
                if d.hi > 0.02 { Text("HL").font(.system(size: 8, weight: .heavy)).padding(.horizontal, 4).background(Color.red, in: Capsule()) }
                if d.lo > 0.05 { Text("SH").font(.system(size: 8, weight: .heavy)).padding(.horizontal, 4).background(Color.blue, in: Capsule()) }
            }.foregroundStyle(.white)
        }
        .padding(6)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(d.luma.isEmpty ? 0 : 1)
        .onTapGesture { haptic(.soft); rgb.toggle() }
    }
}

/// Steadiness indicator for slow shutter speeds.
private struct ShakeBadge: View {
    @ObservedObject var level: LevelMonitor
    var body: some View {
        let (text, color): (String, Color) = level.shake == 0 ? ("STEADY", .green) : level.shake == 1 ? ("HOLD STILL", .orange) : ("TOO SHAKY", .red)
        HStack(spacing: 6) {
            Image(systemName: "hand.raised.fill").font(.system(size: 10))
            Text(text).font(.system(size: 10, weight: .bold)).tracking(0.5)
        }
        .foregroundStyle(color).padding(.horizontal, 10).frame(height: 24)
        .background(.black.opacity(0.5), in: Capsule())
        .animation(.easeOut(duration: 0.15), value: level.shake)
    }
}

/// One-time tour of the main controls.
private struct GuideView: View {
    var done: () -> Void
    @State private var page = 0
    private let pages: [(String, String, String)] = [
        ("hand.tap", "Tap · hold · pinch", "Tap to focus and set exposure. Hold to lock exposure and focus. Pinch to zoom, or use the lens buttons — each one switches to the real camera."),
        ("camera.aperture", "Three mode groups", "PHOTO, VIDEO and EXPOSURE (Night, light trails, long exposure, interval). Pick a group, then a mode in the row below it."),
        ("slider.horizontal.3", "Five drawers", "MANUAL for ISO, shutter, focus and white balance. LOOKS for 50+ film and camera looks. FORMAT, TOOLS (peaking, zebra, HDR…) and PRESETS."),
        ("eye.slash", "Menus hide themselves", "Tap the eye button (next to the tabs) to hide the menus, or let them fade after 5 seconds. Tap the bottom-left corner to bring them back. RESET ALL in Presets or Tools puts everything back to normal."),
        ("sparkles", "You're ready", "Try a rain or night preset, or open LOOKS and tap a look to see it live. You can reopen this guide from TOOLS.")
    ]
    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: pages[page].0).font(.system(size: 54, weight: .light)).foregroundStyle(Theme.gold)
                Text(pages[page].1).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                Text(pages[page].2).font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7)).padding(.horizontal, 36)
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule().fill(i == page ? accent : Color.white.opacity(0.25)).frame(width: i == page ? 20 : 6, height: 6)
                    }
                }.padding(.top, 6)
                Spacer()
                HStack {
                    Button("Skip") { done() }.font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).frame(width: 80)
                    Spacer()
                    Button {
                        haptic(.light)
                        if page < pages.count - 1 { withAnimation(.easeInOut(duration: 0.2)) { page += 1 } } else { done() }
                    } label: {
                        Text(page < pages.count - 1 ? "NEXT" : "START").font(.system(size: 13, weight: .heavy)).foregroundStyle(.black)
                            .padding(.horizontal, 34).frame(height: 44).background(Capsule().fill(Theme.gold))
                    }.buttonStyle(PressStyle())
                    Spacer()
                    Color.clear.frame(width: 80, height: 1)
                }.padding(.horizontal, 24).padding(.bottom, 40)
            }
        }
    }
}

/// Own view so level updates redraw only this line, not the whole screen.
private struct LevelLine: View {
    @ObservedObject var level: LevelMonitor
    var body: some View {
        if abs(level.angle) < 15 {
            let flat = abs(level.angle) < 1.5
            Rectangle().fill(flat ? Color.yellow : Color.white.opacity(0.7))
                .frame(width: flat ? 80 : 56, height: 1.5)
                .rotationEffect(.degrees(-level.angle))
                .animation(.easeOut(duration: 0.12), value: flat)
        }
    }
}

/// Mutable box: changing it does not invalidate the view.
private final class TouchBox { var last = Date() }

struct CameraView: View {
    @StateObject private var camera = CameraEngine()
    @State private var level = LevelMonitor()
    @State private var dial: Dial = .shutter
    @State private var drawer: Drawer? = .manual
    @AppStorage("look") private var lookRaw = Look.original.rawValue
    @AppStorage("lookStrength") private var lookStrength = 1.0
    @AppStorage("peaking") private var peaking = false
    @AppStorage("zebra") private var zebra = false
    @AppStorage("histogram") private var showHistogram = false
    @AppStorage("burst") private var burstOn = false
    @AppStorage("frameOn") private var frameOn = false
    @AppStorage("bracket") private var bracketOn = false
    @AppStorage("portraitBlur") private var portraitBlur = 0.6
    @AppStorage("trailSeconds") private var trailSeconds = 10
    @AppStorage("intervalEvery") private var intervalEvery = 5
    @AppStorage("intervalShots") private var intervalShots = 25
    @AppStorage("hdr") private var hdrOn = false
    @AppStorage("extraGrain") private var extraGrain = 0.0
    @AppStorage("extraGlow") private var extraGlow = 0.0
    @AppStorage("seenGuide") private var seenGuide = false
    @AppStorage("leakKind") private var leakKind = 0
    @AppStorage("extraDust") private var extraDust = 0.0
    @AppStorage("steadyWait") private var steadyWait = false
    @AppStorage("quality") private var quality = 1
    @AppStorage("videoRange") private var videoRange = "SDR"
    @AppStorage("videoCodec") private var videoCodec = "HEVC"
    @AppStorage("nightSeconds") private var nightSeconds = 0
    @AppStorage("astroSeconds") private var astroSeconds = 20
    @AppStorage("astroTrails") private var astroTrails = false
    /// 0 natural, 1 dark, 2 black sky
    @AppStorage("skyDark") private var skyDark = 1
    private var skyDarkness: Float { [0, 0.6, 1][min(max(skyDark, 0), 2)] }
    @AppStorage("askNightTime") private var askNightTime = true
    @AppStorage("skyMap") private var skyMap = false
    @ObservedObject private var quick = QuickAction.shared
    @State private var pendingSelfie = false
    @AppStorage("skyBurn") private var skyBurn = true
    @State private var aligningSky = false
    @State private var alignLast = CGSize.zero
    @State private var sky = SkyTracker()
    @State private var showNightSheet = false
    @AppStorage("suggest") private var suggestOn = true
    @State private var histRGB = false
    @State private var waitingSteady = false
    @State private var pickingWB = false
    @State private var showPDF = false
    @State private var activePreset: CamPreset?
    @Environment(\.scenePhase) private var scenePhase
    /// Name of the applied preset while its look / strength / mode are still what it set.
    private var activePresetName: String? {
        guard let p = activePreset, lookRaw == p.look, abs(lookStrength - p.strength) < 0.01, mode == (p.mode ?? mode) else { return nil }
        return p.name
    }
    private var activeBadgeText: String? {
        if let n = activePresetName { return "PRESET · \(n)" }
        if look != .original { return "LOOK · \(look.rawValue)" + (lookStrength < 0.99 ? " \(Int(lookStrength * 100))%" : "") }
        return nil
    }
    private func activeBadge(_ text: String) -> some View {
        Button { haptic(.soft); drawer = activePresetName != nil ? .presets : .looks } label: {
            HStack(spacing: 6) {
                Image(systemName: activePresetName != nil ? "checkmark.seal.fill" : "camera.filters").font(.system(size: 10))
                Text(text).font(.system(size: 10, weight: .bold)).tracking(0.4).lineLimit(1)
            }
            .foregroundStyle(accent).padding(.horizontal, 10).frame(height: 26)
            .background(.black.opacity(0.5), in: Capsule())
        }.buttonStyle(PressStyle())
    }
    @State private var presetCategory = "FOOD"
    private var showShake: Bool { camera.shutter > 1.0 / 50 || ["NIGHT", "TRAIL", "LONG", "INTERVAL"].contains(mode) }
    private func syncExtras() { camera.setLookExtras(grain: Float(extraGrain), glow: Float(extraGlow), leak: leakKind, dust: Float(extraDust)) }
    private var showLoupe: Bool { drawer == .manual && dial == .focus && !uiHidden }
    @AppStorage("favLooks") private var favRaw = ""
    @AppStorage("presets") private var presetsJSON = "[]"
    @AppStorage("cl_sat") private var clSat = 1.0
    @AppStorage("cl_con") private var clCon = 1.0
    @AppStorage("cl_br") private var clBr = 0.0
    @AppStorage("cl_k") private var clK = 6500.0
    @AppStorage("cl_grain") private var clGrain = 0.0
    @AppStorage("cl_vig") private var clVig = 0.0
    @State private var comparing = false
    @State private var lastInGroup: [String: String] = [:]
    @State private var lookThumbs: [String: UIImage] = [:]
    private let thumbTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private func refreshThumbs() {
        if lookThumbs.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async {
                let t = LookProcessor.thumbnails(for: LookProcessor.fallbackScene())
                DispatchQueue.main.async { if lookThumbs.isEmpty { lookThumbs = t } }
            }
        }
        camera.requestLookThumbnails { lookThumbs = $0 }
    }
    @AppStorage("autoHide") private var autoHide = true
    @State private var uiHidden = false
    @State private var touch = TouchBox()
    private let idleTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private func bump() { touch.last = Date() }
    /// Hide the menus right now (the bottom-left button brings them back).
    private func hideMenus() { haptic(.soft); withAnimation(.easeInOut(duration: 0.28)) { uiHidden = true } }
    private func reveal() { haptic(.soft); bump(); withAnimation(.easeInOut(duration: 0.28)) { uiHidden = false } }
    private var look: Look { get { Look(rawValue: lookRaw) ?? .original } nonmutating set { lookRaw = newValue.rawValue } }
    @AppStorage("gridStyle") private var gridStyle = 1 // 0 off, 1 thirds, 2 cross
    @AppStorage("aspect") private var aspect = "16:9"
    @AppStorage("aspectDefault169") private var aspectMigrated = false
    @AppStorage("timerDelay") private var timerDelay = 0
    @State private var countdown: Int?
    @State private var mode = "PHOTO"
    @AppStorage("timestamp") private var addTimestamp = false
    @State private var macroActive = false
    @State private var focusPoint: CGPoint?
    @State private var focusLocked = false
    @State private var focusToken = 0
    @State private var biasAtDragStart: Float?
    @State private var pinchBase: CGFloat = 1
    @State private var flash = false
    @Namespace private var modeNS

    private func syncMetering() {
        camera.meteringEnabled = drawer == .manual && !uiHidden
        camera.magnifierEnabled = drawer == .manual && dial == .focus && !uiHidden
    }
    private var needMotion: Bool { gridStyle > 0 || showShake || steadyWait }
    private func syncMotion() { if needMotion && scenePhase == .active { level.start() } else { level.stop() } }
    /// After the resolution changes, keep the frame rate on one the new resolution supports.
    private func clampFrameRate() {
        let rates = camera.videoRates(for: camera.videoResolution)
        if !rates.contains(camera.videoFPS) { camera.videoFPS = rates.contains(30) ? 30 : (rates.first ?? 30) }
        clampVideoOptions()
    }
    private func clampVideoOptions() {
        let ranges = camera.videoRanges(for: camera.videoResolution, fps: camera.videoFPS)
        if !ranges.contains(videoRange) { videoRange = "SDR" }
        let codecs = camera.videoCodecs(for: camera.videoResolution, fps: camera.videoFPS, range: videoRange)
        if !codecs.contains(videoCodec) { videoCodec = "HEVC" }
    }
    private func fpsLabel(_ v: Int) -> String {
        switch v { case 24: return "24 cine"; case 25: return "25 PAL"; case 30: return "30"; case 50: return "50 PAL"; case 60: return "60"; default: return "\(v)" }
    }
    /// Starts / stops the constellation map (location + motion) and tells the engine how to label the finished photo.
    private func syncSky() {
        let tracker = sky
        camera.skyBurn = skyBurn
        camera.skyProvider = { tracker.snapshot() }
        tracker.fovProvider = { [camera] in camera.effectiveFOV() }
        if skyMap && scenePhase == .active && !camera.isFront { tracker.start() } else { tracker.stop(); aligningSky = false }
    }
    /// Home-screen quick action → the matching mode (selfie waits until the camera is running).
    private func handleQuickAction() {
        guard let type = quick.pending else { return }
        quick.pending = nil
        switch type {
        case "com.upravind.lumepro.video": selectMode("VIDEO")
        case "com.upravind.lumepro.portrait": selectMode("PORTRAIT")
        case "com.upravind.lumepro.night": selectMode("NIGHT")
        case "com.upravind.lumepro.selfie":
            selectMode("PHOTO")
            if camera.isFront { break }
            if camera.running { camera.flipCamera() } else { pendingSelfie = true }
        default: break
        }
    }
    private func syncAnalysis() { camera.setAnalysis(peaking: peaking, zebra: zebra, histogram: showHistogram) }
    private var isVideo: Bool { videoModes.contains(mode) }

    private var isFull: Bool { aspect == "16:9" }
    private var previewRatio: CGFloat { aspect == "3:2" ? 1.5 : aspect == "1:1" ? 1.0 : 4.0 / 3.0 }

    private var bottomStack: some View {
        VStack(spacing: 0) {
            if isFull { HStack { Spacer(); lensBar; Spacer() }.padding(.bottom, 10).hideable(uiHidden) }
            AnyView(modeSelector).hideable(uiHidden)
            AnyView(drawerTabs).padding(.top, 8).hideable(uiHidden)
            AnyView(drawerContent).padding(.top, 8).hideable(uiHidden)
            AnyView(shutterRow).padding(.top, 6).padding(.bottom, 6)
        }
    }

    /// Invisible view that only carries observers / sheets (keeps the screen's type shallow: a very deep type overflows the iPhone's stack).
    private var hooksA: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
            .onReceive(idleTimer) { _ in
                guard autoHide, !uiHidden, !comparing, Date().timeIntervalSince(touch.last) > 5 else { return }
                withAnimation(.easeInOut(duration: 0.3)) { uiHidden = true }
            }
            .sheet(isPresented: $showNightSheet) {
                NightTimeSheet(astro: mode == "STARS", seconds: mode == "STARS" ? $astroSeconds : $nightSeconds, trails: $astroTrails, askEachTime: $askNightTime, skyDark: $skyDark) {
                    showNightSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { beginNightOrAstro() }
                }
            }
            .onAppear {
                if !aspectMigrated { aspect = "16:9"; aspectMigrated = true }
                camera.start(); syncMotion()
                camera.previewLook = look; camera.lookStrength = Float(lookStrength)
                camera.frameStyle = frameOn ? 1 : 0; camera.burstEnabled = burstOn; camera.portraitBlurAmount = Float(portraitBlur); camera.hdrMerge = hdrOn; camera.qualityPriority = quality; camera.videoRange = videoRange; camera.videoCodec = videoCodec; camera.nightSeconds = nightSeconds; camera.astroSeconds = astroSeconds; camera.astroTrails = astroTrails; camera.astroSkyDarkness = skyDarkness; camera.suggestionsEnabled = suggestOn; syncExtras()
                syncAnalysis(); syncMetering(); syncSky()
                handleQuickAction()
                #if targetEnvironment(simulator)
                if let forced = ProcessInfo.processInfo.environment["FORCE_ASPECT"] { aspect = forced; autoHide = false; seenGuide = true }
                if ProcessInfo.processInfo.environment["LEAK_TEST"] == "1" { DispatchQueue.global(qos: .userInitiated).async { runLeakTest() } }
                if ProcessInfo.processInfo.environment["PEAK_TEST"] == "1" { DispatchQueue.global(qos: .userInitiated).async { runPeakingTest() } }
                if ProcessInfo.processInfo.environment["STAR_TEST"] == "1" { DispatchQueue.global(qos: .userInitiated).async { runStarToneTest() } }
                if ProcessInfo.processInfo.environment["STACK_TEST"] == "1" {
                    // The iPhone gives the main thread ~1 MB of stack (a Mac gives 8 MB): build the screen's type on a thread with 1 MB.
                    let t = Thread {
                        let size = String(reflecting: type(of: CameraView().body)).count
                        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        try? "ok: type description \(size) characters".write(to: docs.appendingPathComponent("stack_report.txt"), atomically: true, encoding: .utf8)
                    }
                    t.stackSize = 1 << 20
                    t.start()
                }
                if ProcessInfo.processInfo.environment["SKY_SELFTEST"] == "1" { DispatchQueue.global(qos: .userInitiated).async { runSkySelfTest() } }
                if ProcessInfo.processInfo.environment["PANO_SELFTEST"] == "1" { DispatchQueue.global(qos: .userInitiated).async { runPanoSelfTest() } }
                if ProcessInfo.processInfo.environment["PRESET_SELFTEST"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { runPresetSelfTest() }
                }
                #endif
            }
            .onChange(of: zebra) { _ in syncAnalysis() }
            .onChange(of: hdrOn) { new in camera.hdrMerge = new }
            .onChange(of: skyBurn) { _ in syncSky() }
            .onChange(of: nightSeconds) { new in camera.nightSeconds = new }
            .onChange(of: extraGrain) { _ in syncExtras() }
            .onChange(of: suggestOn) { new in camera.suggestionsEnabled = new }
            .onChange(of: camera.message) { new in
                guard new != nil else { return }
                Task { try? await Task.sleep(nanoseconds: 3_500_000_000); camera.message = nil }
            }
    }
    /// Invisible view that only carries observers / sheets (keeps the screen's type shallow: a very deep type overflows the iPhone's stack).
    private var hooksB: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
            .onChange(of: autoHide) { on in if !on { reveal() } }
            .onChange(of: drawer) { d in syncMetering(); if d == .looks { refreshThumbs() } }
            .onChange(of: lookRaw) { _ in camera.previewLook = look }
            .onChange(of: showHistogram) { _ in syncAnalysis() }
            .onChange(of: skyMap) { _ in syncSky() }
            .onChange(of: quality) { new in camera.qualityPriority = new }
            .onChange(of: astroSeconds) { new in camera.astroSeconds = new }
            .onChange(of: extraGlow) { _ in syncExtras() }
            .onChange(of: dial) { _ in syncMetering() }
    }
    /// Invisible view that only carries observers / sheets (keeps the screen's type shallow: a very deep type overflows the iPhone's stack).
    private var hooksC: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
            .onChange(of: scenePhase) { phase in
                camera.isForeground = phase == .active
                if phase == .active { bump() }
                syncMotion(); syncSky()
            }
            .onChange(of: uiHidden) { _ in syncMetering() }
            .onChange(of: lookStrength) { new in camera.lookStrength = Float(new) }
            .onChange(of: frameOn) { new in camera.frameStyle = new ? 1 : 0 }
            .onChange(of: quick.pending) { _ in handleQuickAction() }
            .onChange(of: videoRange) { new in camera.videoRange = new }
            .onChange(of: astroTrails) { new in camera.astroTrails = new }
            .onChange(of: skyDark) { _ in camera.astroSkyDarkness = skyDarkness }
            .onChange(of: leakKind) { _ in syncExtras() }
            .onChange(of: portraitBlur) { new in camera.portraitBlurAmount = Float(new) }
    }
    /// Invisible view that only carries observers / sheets (keeps the screen's type shallow: a very deep type overflows the iPhone's stack).
    private var hooksD: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
            .sheet(isPresented: $showPDF) { PDFExportView(sessionURLs: camera.sessionShotURLs()) }
            .onReceive(thumbTimer) { _ in if drawer == .looks && !uiHidden { camera.requestLookThumbnails { lookThumbs = $0 } } }
            .onChange(of: peaking) { _ in syncAnalysis() }
            .onChange(of: burstOn) { new in camera.burstEnabled = new }
            .onChange(of: camera.running) { running in
                if running, pendingSelfie { pendingSelfie = false; if !camera.isFront { camera.flipCamera() } }
            }
            .onChange(of: videoCodec) { new in camera.videoCodec = new }
            .onChange(of: needMotion) { _ in syncMotion() }
            .onChange(of: extraDust) { _ in syncExtras() }
            .onDisappear { level.stop() }
    }

    var body: some View {
        GeometryReader { geo in
            
            let top = geo.safeAreaInsets.top
            let fullH = geo.size.height + top + geo.safeAreaInsets.bottom
            let landscapeHold = camera.orientationCode == 1 || camera.orientationCode == 2
            let wideW = geo.size.width - 20
            let tallH = min(wideW * previewRatio, geo.size.height * (drawer == nil ? 0.62 : 0.5))
            let maxH = landscapeHold ? wideW / previewRatio : tallH
            let normalW = landscapeHold ? wideW : tallH / previewRatio
            // 16:9 is shaped exactly like the saved 16:9 photo (not stretched to the whole screen), so what you see is what you get.
            let wide169 = wideW * 9 / 16
            let rect = isFull
                ? (landscapeHold
                    ? CGRect(x: 10, y: top + 52, width: wideW, height: wide169)
                    : CGRect(x: 0, y: 0, width: geo.size.width, height: min(fullH, geo.size.width * 16 / 9)))
                : CGRect(x: (geo.size.width - normalW) / 2, y: top + 52, width: normalW, height: maxH)
            let showScrim = isFull && !uiHidden
            ZStack {
                Theme.backdrop.ignoresSafeArea()
                // One viewfinder for both layouts, so switching ratio never rebuilds the camera preview.
                previewArea(corner: isFull && !landscapeHold ? 0 : 26, showLens: !isFull, topInset: isFull && !landscapeHold ? top + 52 : 0)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .ignoresSafeArea()
                    .transaction { $0.animation = nil }
                VStack(spacing: 0) {
                    topBar
                        .background(LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top).opacity(showScrim ? 1 : 0))
                        .hideable(uiHidden)
                    Spacer(minLength: 4)
                    bottomStack.padding(.top, isFull ? 24 : 0)
                        .background(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.82), location: 0.22), .init(color: .black.opacity(0.96), location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom).opacity(showScrim ? 1 : 0))
                }
                if uiHidden {
                    VStack {
                        Spacer()
                        HStack {
                            Button { reveal() } label: {
                                Image(systemName: "slider.horizontal.3").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                                    .frame(width: 50, height: 50).neuRaisedCircle()
                                    .frame(width: 96, height: 110, alignment: .center).contentShape(Rectangle())
                            }.buttonStyle(PressStyle())
                            Spacer()
                        }.padding(.leading, 14)
                    }.transition(.opacity)
                }
                if !seenGuide { GuideView { withAnimation { seenGuide = true } }.transition(.opacity).zIndex(10) }
                if let msg = camera.message {
                    VStack { Spacer(); Text(msg).font(.system(size: 13, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 11).neuPill().padding(.bottom, 150) }
                        .transition(.opacity).allowsHitTesting(false)
                }
                hooksA; hooksB; hooksC; hooksD
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isFull)
            .animation(.easeInOut(duration: 0.28), value: uiHidden)
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in bump() })
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: drawer)
            .animation(.easeOut(duration: 0.2), value: camera.message)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Top bar
    private var topBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Flash Auto") { camera.flashMode = "AUTO" }
                Button("Flash On") { camera.flashMode = "ON" }
                Button("Flash Off") { camera.flashMode = "OFF" }
            } label: {
                roundIcon(camera.flashMode == "OFF" ? "bolt.slash.fill" : "bolt.fill", tint: camera.flashMode == "ON" ? .yellow : .white)
            }.disabled(!camera.flashAvailable || isVideo)
            Button { haptic(); camera.toggleTorch() } label: { roundIcon(camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill", tint: camera.torchOn ? .yellow : .white) }
                .buttonStyle(PressStyle())
            Button { haptic(); camera.flipCamera() } label: { roundIcon("arrow.triangle.2.circlepath.camera", tint: .white) }
                .buttonStyle(PressStyle()).disabled(camera.isRecording)
            Spacer()
            Button { haptic(); aspect = isFull ? "4:3" : "16:9" } label: {
                Text(isFull ? "16:9" : aspect).font(.system(size: 11, weight: .heavy)).foregroundStyle(isFull ? Color.black : .white)
                    .padding(.horizontal, 11).frame(height: 36).neuToggle(isFull)
            }.buttonStyle(PressStyle())
            if camera.supportsRAW && mode == "PHOTO" {
                Button { haptic(); camera.rawEnabled.toggle() } label: {
                    Text("RAW").font(.system(size: 11, weight: .heavy, design: .default)).foregroundStyle(camera.rawEnabled ? .black : .white)
                        .padding(.horizontal, 11).frame(height: 36).neuToggle(camera.rawEnabled)
                }.buttonStyle(PressStyle())
            }
            Button { hideMenus() } label: { roundIcon("eye.slash", tint: accent) }.buttonStyle(PressStyle())
            Button { haptic(); gridStyle = (gridStyle + 1) % 5; camera.message = "Guide: " + Self.gridNames[gridStyle] } label: {
                roundIcon(["square", "grid", "plus.viewfinder", "rectangle.split.3x1", "xmark.square"][gridStyle], tint: gridStyle == 0 ? .white.opacity(0.6) : .white)
            }.buttonStyle(PressStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
    private func roundIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 36, height: 36).neuRaisedCircle()
    }
    private var infoPill: some View {
        let text: String
        if isVideo {
            text = "\(mode == "SLOW" ? "HD" : camera.videoResolution) · \(mode == "SLOW" ? camera.slowMotionFPS : camera.videoFPS) FPS" + (mode == "VIDEO" && videoRange != "SDR" ? " · \(videoRange)" : "") + (mode == "VIDEO" && videoCodec != "HEVC" ? " · \(videoCodec == "PRORES" ? "ProRes" : videoCodec)" : "")
        } else {
            text = "\(camera.rawEnabled ? "DNG" : camera.photoFormat) · \(camera.photoResolutionMP) MP · " + String(format: "%+.1f EV", camera.exposureBias)
        }
        return HStack(spacing: 6) {
            if camera.isRecording { Circle().fill(.red).frame(width: 7, height: 7) }
            Text(camera.isRecording ? ("REC" + (camera.recordingInfo.map { " · " + $0 } ?? "")) : text).font(.system(size: 11, weight: .bold, design: .default)).monospacedDigit()
        }
        .padding(.horizontal, 10).frame(height: 26).background(.black.opacity(0.45), in: Capsule())
    }

    // MARK: Preview
    private func previewArea(corner: CGFloat, showLens: Bool, topInset: CGFloat = 0) -> AnyView {
        AnyView(previewAreaContent(corner: corner, showLens: showLens, topInset: topInset))
    }
    private func previewAreaContent(corner: CGFloat, showLens: Bool, topInset: CGFloat = 0) -> some View {
        GeometryReader { g in
            ZStack {
                CameraPreview(session: camera.session, engine: camera, refreshKey: camera.orientationCode + (camera.running ? 10 : 0), onShutter: { shutterPressed() },
                              onFocus: { layerPt, devicePt, lock in handleFocus(layerPt, devicePt, lock) },
                              onPinchBegan: { pinchBase = camera.zoom },
                              onPinch: { scale in camera.setZoom(min(max(pinchBase * scale, 0.5), 15), sticky: true) })
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Theme.bevel, lineWidth: 1.4))
                    .shadow(color: .black.opacity(corner == 0 ? 0 : 0.85), radius: 16, x: 0, y: 10)
                if skyMap && !camera.isFront {
                    SkyOverlay(tracker: sky).clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    if aligningSky {
                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture()
                                .onChanged { v in
                                    let side = g.size.width / g.size.height >= 0.75 ? g.size.width * 4 / 3 : g.size.height
                                    sky.offset.x += (v.translation.width - alignLast.width) / side
                                    sky.offset.y += (v.translation.height - alignLast.height) / side
                                    alignLast = v.translation
                                }
                                .onEnded { _ in alignLast = .zero })
                    }
                }
                if gridStyle > 0 { gridOverlay.clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous)).allowsHitTesting(false) }
                if gridStyle > 0 { LevelLine(level: level).allowsHitTesting(false) }
                if let p = focusPoint { focusIndicator.position(x: min(max(p.x, 50), g.size.width - 50), y: min(max(p.y, 50), g.size.height - 50)).transition(.scale(scale: 1.4).combined(with: .opacity)) }
                VStack {
                    HStack(spacing: 6) { statusPill; Spacer(); infoPill; if look != .original || extraGrain > 0 || extraGlow > 0 || leakKind > 0 || extraDust > 0 { compareButton } }
                    if aligningSky {
                        HStack(spacing: 8) {
                            Text("Drag to line the map up with the stars").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            Button { sky.offset = .zero; haptic(.soft) } label: { Text("RESET").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white.opacity(0.8)) }
                            Button { aligningSky = false; haptic(.soft) } label: { Text("DONE").font(.system(size: 10, weight: .heavy)).foregroundStyle(accent) }
                        }.padding(.horizontal, 12).frame(height: 30).background(.black.opacity(0.6), in: Capsule())
                    }
                    if let text = activeBadgeText { HStack { activeBadge(text); Spacer() } }
                    if camera.panoSweeping, let strip = camera.panoStrip {
                        Image(uiImage: strip).resizable().scaledToFit().frame(maxWidth: 320, maxHeight: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(accent, lineWidth: 1))
                            .padding(4).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    if showShake { HStack { ShakeBadge(level: level); Spacer() } }
                    if suggestOn, let sug = camera.suggestedLook, sug != lookRaw, !isVideo, let suggested = Look(rawValue: sug) {
                        HStack {
                            Button { haptic(.medium); withAnimation { lookRaw = sug }; camera.suggestedLook = nil; camera.message = "Look applied: \(suggested.rawValue)" } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles").font(.system(size: 10))
                                    Text("TRY \(suggested.rawValue)").font(.system(size: 10, weight: .heavy)).tracking(0.4)
                                }
                                .foregroundStyle(Color.black).padding(.horizontal, 12).frame(height: 32)
                                .background(Capsule().fill(Theme.gold))
                                .contentShape(Capsule())
                            }.buttonStyle(PressStyle())
                            Spacer()
                        }.transition(.opacity)
                    }
                    if showHistogram { HStack { HistogramPanel(model: camera.hist, rgb: $histRGB); Spacer() } }
                    if showLoupe {
                        LoupeView(engine: camera).frame(width: 120, height: 120)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent, lineWidth: 1.5))
                            .overlay(Image(systemName: "plus").font(.system(size: 14, weight: .light)).foregroundStyle(.white.opacity(0.6)))
                            .shadow(color: .black.opacity(0.6), radius: 8)
                            .allowsHitTesting(false)
                    }
                    Spacer()
                    if showLens { HStack { Spacer(); lensBar; Spacer() }.hideable(uiHidden) }
                }.padding(12).padding(.top, topInset).allowsHitTesting(true)
                if flash { Color.white.clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous)).transition(.opacity).allowsHitTesting(false) }
                if let countdown { Text("\(countdown)").font(.system(size: 88, weight: .thin, design: .default).monospacedDigit()).foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 14).transition(.scale.combined(with: .opacity)).allowsHitTesting(false) }
                if mode == "PANO" { Text(camera.panoSweeping ? "SWEEP SLOWLY · LINE UP THE GHOST EDGE · TAP SHUTTER TO FINISH" : "TAP THE SHUTTER, THEN SWEEP SLOWLY").font(.system(size: 10, weight: .bold, design: .default)).padding(10).background(.black.opacity(0.55), in: Capsule()).allowsHitTesting(false) }
                if !camera.authorized { permissionPrompt }
            }
        }
    }
    private var compareButton: some View {
        Image(systemName: comparing ? "eye.fill" : "eye")
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(comparing ? Color.black : .white)
            .frame(width: 30, height: 26).background(comparing ? accent : Color.black.opacity(0.45), in: Capsule())
            .onLongPressGesture(minimumDuration: 0, maximumDistance: 60, pressing: { down in
                comparing = down
                camera.compareRaw = down
                if down { haptic(.soft) }
            }, perform: {})
    }
    private var statusPill: some View {
        let label = camera.panoSweeping ? "PANORAMA · \(camera.panoramaShotCount)" : camera.isInterval ? "INTERVAL \(camera.intervalShot)/\(camera.intervalCount)" : camera.isTrailing ? "\(mode == "LONG" ? "LONG" : "TRAIL") \(camera.trailElapsed)/\(camera.trailDuration)s" : camera.nightBusy ? (mode == "STARS" ? "STARS · SHOOTING" : "NIGHT · SHOOTING") : mode == "STARS" ? "STARS" : mode == "INTERVAL" ? "INTERVAL" : mode == "LONG" ? "LONG EXPOSURE" : mode == "TRAIL" ? "LIGHT TRAIL" : mode == "NIGHT" ? "NIGHT" : camera.isRecording ? "RECORDING" : mode == "PANO" ? "PANORAMA" : mode == "PORTRAIT" ? "PORTRAIT" : isVideo ? "\(mode) READY" : (camera.autoExposure ? "AUTO" : "MANUAL")
        return HStack(spacing: 6) {
            Circle().fill(camera.isRecording || camera.isTrailing || camera.isInterval ? Color.red : (camera.autoExposure ? Color.green : accent)).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .bold, design: .default)).tracking(0.6)
        }.padding(.horizontal, 10).frame(height: 26).background(.black.opacity(0.45), in: Capsule())
    }
    private var permissionPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill").font(.system(size: 24))
            Text("Camera access is needed for live preview").font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
            Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8).background(accent, in: Capsule()).foregroundStyle(.black)
        }.padding(18).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
    }
    private static let gridNames = ["Off", "Rule of thirds", "Centre cross", "Golden ratio", "Diagonals"]
    private var gridOverlay: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            Path { p in
                func vline(_ x: CGFloat) { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)) }
                func hline(_ y: CGFloat) { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                switch gridStyle {
                case 1: vline(w / 3); vline(w * 2 / 3); hline(h / 3); hline(h * 2 / 3)
                case 3: vline(w * 0.382); vline(w * 0.618); hline(h * 0.382); hline(h * 0.618)
                case 4:
                    p.move(to: .zero); p.addLine(to: CGPoint(x: w, y: h))
                    p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: 0, y: h))
                    p.move(to: CGPoint(x: w / 2, y: 0)); p.addLine(to: CGPoint(x: 0, y: h / 2))
                    p.move(to: CGPoint(x: w, y: h / 2)); p.addLine(to: CGPoint(x: w / 2, y: h))
                default:
                    let c = CGPoint(x: w / 2, y: h / 2)
                    p.move(to: CGPoint(x: c.x - 14, y: c.y)); p.addLine(to: CGPoint(x: c.x + 14, y: c.y))
                    p.move(to: CGPoint(x: c.x, y: c.y - 14)); p.addLine(to: CGPoint(x: c.x, y: c.y + 14))
                }
            }.stroke(.white.opacity(0.28), lineWidth: 0.7)
        }
    }
    private var focusIndicator: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4).stroke(focusLocked ? Color.orange : Color.yellow, lineWidth: 1.5).frame(width: 66, height: 66)
                .overlay { if focusLocked { Text("AE/AF LOCK").font(.system(size: 7, weight: .heavy)).foregroundStyle(.black).padding(3).background(Color.orange, in: Capsule()).offset(y: 44) } }
            Image(systemName: "sun.max.fill").font(.system(size: 16)).foregroundStyle(.yellow)
                .frame(width: 30, height: 66)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                    if biasAtDragStart == nil { biasAtDragStart = camera.exposureBias }
                    let b = min(max((biasAtDragStart ?? 0) - Float(v.translation.height / 40), -3), 3)
                    camera.setAutoBias(b)
                    scheduleFocusHide()
                }.onEnded { _ in biasAtDragStart = nil })
        }
    }
    private func handleFocus(_ layerPt: CGPoint, _ devicePt: CGPoint, _ lock: Bool) {
        if pickingWB { pickingWB = false; haptic(.medium); camera.pickWhiteBalance(devicePoint: devicePt); return }
        haptic(lock ? .medium : .light)
        camera.focus(atDevicePoint: devicePt, lock: lock)
        camera.autoFocus = true
        focusLocked = lock
        withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) { focusPoint = layerPt }
        scheduleFocusHide()
    }
    private func scheduleFocusHide() {
        focusToken += 1
        let token = focusToken
        Task {
            try? await Task.sleep(nanoseconds: focusLocked ? 4_000_000_000 : 2_200_000_000)
            if token == focusToken { withAnimation(.easeOut(duration: 0.25)) { focusPoint = nil } }
        }
    }

    // MARK: Lenses
    private var lensBar: some View {
        HStack(spacing: 4) {
            ForEach(camera.lensButtons, id: \.self) { z in lensButton(z) }
        }.padding(4).background(.black.opacity(0.55), in: Capsule()).overlay(Capsule().stroke(Theme.bevel, lineWidth: 1))
    }
    private func lensButton(_ z: Double) -> some View {
        let selected = abs(Double(camera.zoom) - z) < 0.08
        let title = z == 0.5 ? "0.5" : "\(Int(z))"
        return Button { haptic(); withAnimation(.easeOut(duration: 0.2)) { camera.selectLens(CGFloat(z)) } } label: {
            Text(selected ? title + "×" : title).font(.system(size: 12, weight: .bold, design: .default))
                .foregroundStyle(selected ? Color.black : .white)
                .frame(width: selected ? 40 : 34, height: 32)
                .background { if selected { Circle().fill(Theme.gold) } }
        }.buttonStyle(PressStyle())
    }

    // MARK: Mode selector
    private func available(_ m: String) -> Bool {
        switch m {
        case "SLOW": return camera.slowMotionSupported
        case "CINEMATIC": return camera.supportsCinematic
        case "PORTRAIT": return camera.supportsPortrait
        default: return true
        }
    }
    private var modeSelector: some View {
        let group = ModeGroup.of(mode)
        let subs = group.modes.filter(available)
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(ModeGroup.allCases, id: \.self) { g in
                    Button {
                        let target = lastInGroup[g.rawValue].flatMap { available($0) ? $0 : nil } ?? g.modes[0]
                        selectMode(target)
                    } label: {
                        Text(g.rawValue).font(.system(size: 11, weight: .bold)).tracking(0.6)
                            .foregroundStyle(group == g ? Color.black : .white.opacity(0.6))
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .background { if group == g { Capsule().fill(Theme.gold).matchedGeometryEffect(id: "modePill", in: modeNS) } }
                    }.buttonStyle(PressStyle())
                }
            }
            .padding(4).neuTrack().padding(.horizontal, 14)
            if subs.count > 1 {
                HStack(spacing: 0) {
                    ForEach(subs, id: \.self) { m in
                        Button { selectMode(m) } label: {
                            VStack(spacing: 3) {
                                Text(m).font(.system(size: 10, weight: mode == m ? .heavy : .semibold)).tracking(0.5)
                                    .foregroundStyle(mode == m ? accent : Theme.muted)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Capsule().fill(mode == m ? accent : .clear).frame(width: 14, height: 2)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(PressStyle())
                    }
                }.padding(.horizontal, 22).frame(height: 28)
            }
        }
        .disabled(camera.isRecording || camera.isTrailing || camera.nightBusy || camera.isInterval || camera.panoSweeping)
        .opacity(camera.isRecording || camera.isTrailing || camera.nightBusy || camera.isInterval ? 0.4 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: mode)
    }
    private func selectMode(_ name: String) {
        guard mode != name else { return }
        haptic(.light)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { mode = name }
        lastInGroup[ModeGroup.of(name).rawValue] = name
        camera.panoramaMode = name == "PANO"
        camera.portraitMode = name == "PORTRAIT"
        camera.nightMode = name == "NIGHT"
        camera.astroMode = name == "STARS"
        camera.videoMode = videoModes.contains(name)
        if ["PANO", "PORTRAIT", "NIGHT", "STARS"].contains(name) { camera.rawEnabled = false }
        camera.resetPanorama()
    }

    // MARK: Drawer
    private var drawerTabs: some View {
        HStack(spacing: 4) {
            ForEach(Drawer.allCases, id: \.self) { d in
                Button { haptic(); drawer = drawer == d ? nil : d } label: {
                    Text(d.rawValue).font(.system(size: 10, weight: .bold)).tracking(0.4)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(drawer == d ? Color.black : Theme.muted)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background { if drawer == d { Capsule().fill(Theme.gold) } }
                }.buttonStyle(PressStyle())
            }
            Button { haptic(.soft); drawer = drawer == nil ? .manual : nil } label: {
                Image(systemName: drawer == nil ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted).frame(width: 30, height: 30)
            }.buttonStyle(PressStyle())
            Button { hideMenus() } label: {
                Image(systemName: "eye.slash").font(.system(size: 12, weight: .bold)).foregroundStyle(accent).frame(width: 30, height: 30)
            }.buttonStyle(PressStyle())
        }
        .padding(4).neuTrack().padding(.horizontal, 14)
    }
    @ViewBuilder private var drawerContent: some View {
        switch drawer {
        case .manual: AnyView(manualPanel).transition(.move(edge: .bottom).combined(with: .opacity))
        case .looks: AnyView(lookPicker).transition(.move(edge: .bottom).combined(with: .opacity))
        case .format: AnyView(formatPanel).transition(.move(edge: .bottom).combined(with: .opacity))
        case .tools: AnyView(toolsPanel).transition(.move(edge: .bottom).combined(with: .opacity))
        case .presets: AnyView(presetsPanel).transition(.move(edge: .bottom).combined(with: .opacity))
        case nil: EmptyView()
        }
    }

    private var manualPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Dial.allCases, id: \.self) { d in
                    Button { haptic(.soft); dial = d } label: {
                        VStack(spacing: 5) {
                            Text(d.rawValue).font(.system(size: 10, weight: .bold, design: .default)).tracking(0.5)
                            Capsule().fill(dial == d ? accent : .clear).frame(width: 18, height: 2)
                        }.foregroundStyle(dial == d ? accent : .white.opacity(0.45)).frame(maxWidth: .infinity)
                    }.buttonStyle(PressStyle())
                }
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(controlValue).font(.system(size: 24, weight: .semibold, design: .default).monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
                    Text(controlDescription).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                }.frame(width: 92, alignment: .leading)
                VStack(spacing: 4) {
                    Slider(value: sliderBinding, in: sliderRange).tint(accent)
                    HStack { Text(sliderMinLabel); Spacer(); Text(sliderMaxLabel) }.font(.system(size: 9, weight: .medium, design: .default)).foregroundStyle(.white.opacity(0.35))
                }
                Button { haptic(); autoPressed() } label: {
                    Text(isAuto ? "AUTO" : "MANUAL").font(.system(size: 9, weight: .heavy, design: .default))
                        .foregroundStyle(isAuto ? Color.black : accent)
                        .frame(width: 52, height: 28)
                        .neuToggle(isAuto)
                }.buttonStyle(PressStyle())
            }
            if dial == .focus, let h = camera.hyperfocal() {
                let f: (Double) -> String = { $0 >= 10 ? String(format: "%.0f m", $0) : String(format: "%.1f m", $0) }
                Text("Hyperfocal ≈ \(f(h.hyper)): focus there and everything from ≈\(f(h.near)) to infinity stays sharp (estimate).")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
            if dial == .wb {
                Button { haptic(.soft); pickingWB.toggle() } label: {
                    chip("eyedropper", pickingWB ? "TAP A GREY OR WHITE OBJECT IN THE VIEW…" : "PICK FROM SCENE", highlighted: pickingWB)
                }.buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .neuCard(22)
        .padding(.horizontal, 14)
    }
    private var isAuto: Bool {
        switch dial { case .exp: return camera.exposureBias == 0 && camera.autoExposure; case .iso, .shutter: return camera.autoExposure; case .focus: return camera.autoFocus; case .wb, .tint: return camera.autoWB }
    }
    private func autoPressed() {
        switch dial {
        case .exp: camera.resetBias()
        case .iso, .shutter: camera.setAuto("EXP"); camera.resetBias()
        case .focus: camera.setAuto("FOCUS")
        case .wb, .tint: camera.setAuto("WB")
        }
    }
    private var controlValue: String {
        switch dial {
        case .exp: return String(format: "%+.1f", camera.exposureBias)
        case .iso: return "\(Int(camera.iso))"
        case .shutter: return camera.shutter >= 0.5 ? String(format: "%.1fs", camera.shutter) : "1/\(max(1, Int((1 / camera.shutter).rounded())))"
        case .focus: return camera.focus < 0.02 ? "Macro" : String(format: "%.0f%%", camera.focus * 100)
        case .wb: return "\(Int(camera.temperature))K"
        case .tint: return String(format: "%+.0f", camera.tint)
        }
    }
    private var controlDescription: String {
        switch dial { case .exp: return "Exposure bias"; case .iso: return "Sensor sensitivity"; case .shutter: return "Shutter speed"; case .focus: return "Lens position"; case .wb: return "White balance"; case .tint: return "Green – magenta tint" }
    }
    // Shutter uses a log2 scale so fast speeds are reachable.
    private var sliderRange: ClosedRange<Double> {
        switch dial { case .exp: return -3...3; case .iso: return 25...3200; case .shutter: return -13...0; case .focus: return 0...1; case .wb: return 2500...9000; case .tint: return -150...150 }
    }
    private var sliderBinding: Binding<Double> {
        Binding(get: {
            switch dial {
            case .exp: return Double(camera.exposureBias)
            case .iso: return Double(camera.iso)
            case .shutter: return min(max(log2(max(camera.shutter, 1.0 / 8192)), -13), 0)
            case .focus: return Double(camera.focus)
            case .wb: return Double(camera.temperature)
            case .tint: return Double(camera.tint)
            }
        }, set: { v in
            switch dial {
            case .exp: camera.setBias(Float(v))
            case .iso: camera.setISO(Float(v))
            case .shutter: camera.setShutter(pow(2, v))
            case .focus: camera.setFocus(Float(v))
            case .wb: camera.setWhiteBalance(Float(v))
            case .tint: camera.setTint(Float(v))
            }
        })
    }
    private var sliderMinLabel: String { switch dial { case .exp: return "−3"; case .iso: return "25"; case .shutter: return "1/8000"; case .focus: return "NEAR"; case .wb: return "2500K"; case .tint: return "−150" } }
    private var sliderMaxLabel: String { switch dial { case .exp: return "+3"; case .iso: return "3200"; case .shutter: return "1s"; case .focus: return "∞"; case .wb: return "9000K"; case .tint: return "+150" } }

    // MARK: Looks
    private var lookPicker: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(orderedLooks, id: \.self) { item in
                        Button { haptic(.soft); withAnimation(.easeOut(duration: 0.15)) { look = item } } label: {
                            VStack(spacing: 6) {
                                Group {
                                    if let img = lookThumbs[item.rawValue] { Image(uiImage: img).resizable().scaledToFill() }
                                    else { Rectangle().fill(lookColor(item)) }
                                }.frame(width: 76, height: 52).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay { if item == look { Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white) } }
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(item == look ? accent : Color.white.opacity(0.1), lineWidth: item == look ? 2 : 0.7))
                                    .overlay(alignment: .topTrailing) { if favSet.contains(item.rawValue) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(accent).padding(4) } }
                                Text(item.rawValue).font(.system(size: 8, weight: .bold, design: .default)).lineLimit(1).minimumScaleFactor(0.6)
                                    .foregroundStyle(item == look ? .white : .white.opacity(0.5)).frame(width: 78)
                            }
                        }.buttonStyle(PressStyle())
                        .contextMenu { Button(favSet.contains(item.rawValue) ? "Remove favourite" : "Add to favourites", systemImage: "star") { toggleFav(item) } }
                    }
                }.padding(.horizontal, 14)
            }
            Text(look.blurb).font(.system(size: 10, weight: .medium, design: .default)).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 14).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Text("STRENGTH").font(.system(size: 9, weight: .bold, design: .default)).foregroundStyle(.white.opacity(0.5))
                Slider(value: $lookStrength, in: 0...1).tint(accent).disabled(look == .original)
                Text("\(Int(lookStrength * 100))%").font(.system(size: 11, weight: .bold, design: .default).monospacedDigit()).frame(width: 40, alignment: .trailing)
            }.padding(.horizontal, 14)
            HStack(spacing: 14) { miniSlider("GRAIN", $extraGrain, 0...1); miniSlider("GLOW", $extraGlow, 0...1) }.padding(.horizontal, 14)
            HStack(spacing: 8) {
                Text("LIGHT LEAK").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                ForEach(Array(["OFF", "WARM", "SUN", "PINK"].enumerated()), id: \.offset) { i, name in
                    Button { haptic(.soft); leakKind = i } label: {
                        Text(name).font(.system(size: 9, weight: .bold)).foregroundStyle(leakKind == i ? Color.black : .white.opacity(0.7))
                            .padding(.horizontal, 9).frame(height: 24).background { if leakKind == i { Capsule().fill(Theme.gold) } else { Capsule().fill(Color.white.opacity(0.08)) } }
                    }.buttonStyle(PressStyle())
                }
                miniSlider("DUST", $extraDust, 0...1)
            }.padding(.horizontal, 14)
            if look == .custom { customEditor }
        }
    }
    private var favSet: Set<String> { Set(favRaw.split(separator: ",").map(String.init)) }
    private var orderedLooks: [Look] {
        let f = favSet
        let rest = Look.allCases.filter { $0 != .original }
        return [.original] + rest.filter { f.contains($0.rawValue) } + rest.filter { !f.contains($0.rawValue) }
    }
    private func toggleFav(_ l: Look) {
        var f = favSet
        if f.contains(l.rawValue) { f.remove(l.rawValue) } else { f.insert(l.rawValue) }
        favRaw = f.sorted().joined(separator: ",")
        haptic(.medium)
    }
    private var customEditor: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) { miniSlider("SATURATION", $clSat, 0...2); miniSlider("CONTRAST", $clCon, 0.5...1.6) }
            HStack(spacing: 14) { miniSlider("WARM ↔ COOL", $clK, 4500...9000); miniSlider("BRIGHTNESS", $clBr, -0.2...0.2) }
            HStack(spacing: 14) { miniSlider("GRAIN", $clGrain, 0...1); miniSlider("VIGNETTE", $clVig, 0...1.5) }
            Button("Reset") { clSat = 1; clCon = 1; clBr = 0; clK = 6500; clGrain = 0; clVig = 0 }
                .font(.system(size: 10, weight: .bold, design: .default)).foregroundStyle(accent)
        }.padding(.horizontal, 14)
    }
    private func miniSlider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 8, weight: .bold, design: .default)).foregroundStyle(.white.opacity(0.5))
            Slider(value: value, in: range).tint(accent)
        }
    }
    private func lookColor(_ l: Look) -> Color { l.spec.swatch }

    // MARK: Presets
    private var presets: [CamPreset] {
        get { (try? JSONDecoder().decode([CamPreset].self, from: Data(presetsJSON.utf8))) ?? [] }
        nonmutating set { presetsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }
    private var presetsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STARTER").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { resetAll() } label: { chip("arrow.counterclockwise", "RESET ALL") }.buttonStyle(PressStyle())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.presetCategories, id: \.self) { c in
                        Button { haptic(.soft); presetCategory = c } label: {
                            Text(c).font(.system(size: 9, weight: .bold)).tracking(0.5)
                                .foregroundStyle(presetCategory == c ? Color.black : Theme.muted)
                                .padding(.horizontal, 10).frame(height: 24)
                                .background { if presetCategory == c { Capsule().fill(Theme.gold) } else { Capsule().fill(Color.white.opacity(0.07)) } }
                        }.buttonStyle(PressStyle())
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(starters.filter { $0.cat == presetCategory }, id: \.preset.name) { item in
                        Button { applyPreset(item.preset) } label: { chip(presetIcon(item.preset), item.preset.name, highlighted: activePresetName == item.preset.name) }.buttonStyle(PressStyle())
                    }
                }
            }
            Text("MY PRESETS").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.45))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { saveCurrentPreset() } label: { chip("plus", "SAVE CURRENT", highlighted: true) }.buttonStyle(PressStyle())
                    ForEach(presets) { p in
                        Button { applyPreset(p) } label: { chip(presetIcon(p), p.name, highlighted: activePresetName == p.name) }.buttonStyle(PressStyle())
                            .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { presets = presets.filter { $0.id != p.id } } }
                    }
                }
            }
            Text(presets.isEmpty ? "Save your look, exposure, white balance and tools as a one-tap preset." : "Tap to apply. Press and hold a preset to delete it.")
                .font(.system(size: 10, weight: .medium, design: .default)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .neuCard(22)
        .padding(.horizontal, 14)
    }
    private static let presetCategories = ["FOOD", "PEOPLE", "INDOOR", "LANDSCAPE", "NIGHT", "STREET", "WEATHER", "CREATIVE", "PRO"]
    private var starters: [(cat: String, preset: CamPreset)] {
        func st(_ cat: String, _ name: String, _ look: Look, _ strength: Double, mode: String = "PHOTO", grid: Int = 1,
                peaking: Bool = false, zebra: Bool = false, hist: Bool = false, frame: Bool = false,
                manual: (iso: Float, shutter: Double)? = nil, burst: Bool = false,
                ratio: String? = nil, sky: Bool? = nil, dark: Int? = nil, grain: Double = 0, glow: Double = 0, leak: Int = 0, dust: Double = 0, steady: Bool = false, bias: Float = 0) -> (cat: String, preset: CamPreset) {
            (cat, CamPreset(name: name, look: look.rawValue, strength: strength, aspect: "4:3", grid: grid, timer: 0, frame: frame, burst: burst, bracket: false,
                            peaking: peaking, zebra: zebra, histogram: hist, manualExposure: manual != nil, iso: manual?.iso ?? 100, shutter: manual?.shutter ?? 1.0 / 120,
                            manualWB: false, temperature: 5200, tint: 0, mode: mode, ratio: ratio, sky: sky, dark: dark,
                            grain: grain, glow: glow, leak: leak, dust: dust, steady: steady, bias: bias))
        }
        return [
            // FOOD (cloud kitchen / restaurant)
            st("FOOD", "Menu Shot · Delivery Apps", .menuClean, 1, grid: 1, ratio: "1:1", steady: true, bias: 0.3),
            st("FOOD", "Flat Lay · Overhead", .foodFresh, 0.9, grid: 1, ratio: "1:1", steady: true),
            st("FOOD", "45° Plated Dish", .foodWarm, 0.9, grid: 3, ratio: "4:3", glow: 0.1),
            st("FOOD", "Dark & Moody Food", .foodMoody, 0.9, grid: 0, ratio: "4:3", steady: true, bias: -0.3),
            st("FOOD", "Rustic Table", .foodRustic, 0.9, grid: 1, ratio: "4:3", grain: 0.15),
            st("FOOD", "Close-up Texture", .foodFresh, 0.9, grid: 0, ratio: "4:3", steady: true),
            st("FOOD", "Steam & Sizzle", .foodWarm, 0.85, grid: 0, manual: (iso: 400, shutter: 1.0 / 250), burst: true, ratio: "4:3"),
            st("FOOD", "Drinks & Beverages", .foodFresh, 0.85, grid: 1, ratio: "4:3", glow: 0.15, bias: 0.3),
            st("FOOD", "Bakery & Desserts", .pastel, 0.6, grid: 1, ratio: "4:3", glow: 0.2, bias: 0.3),
            st("FOOD", "Pizza & Burgers", .foodWarm, 1, grid: 1, ratio: "4:3"),
            st("FOOD", "Packaged Food & Boxes", .menuClean, 1, grid: 4, zebra: true, ratio: "1:1", steady: true),
            st("FOOD", "Kitchen Interior", .menuClean, 0.9, grid: 4, ratio: "3:2", steady: true, bias: 0.3),
            // PEOPLE
            st("PEOPLE", "Portrait", .portra, 0.9, mode: "PORTRAIT"),
            st("PEOPLE", "Soft Skin", .astia, 0.9, mode: "PORTRAIT"),
            st("PEOPLE", "Sunkissed Portrait", .sunkissed, 0.9, mode: "PORTRAIT", glow: 0.2),
            st("PEOPLE", "Soft Romance", .blush, 0.9, mode: "PORTRAIT", glow: 0.25),
            st("PEOPLE", "Backlit Silhouette", .sunset, 0.8, bias: -1.0),
            // LANDSCAPE
            st("LANDSCAPE", "Landscape", .velvia, 0.8),
            st("LANDSCAPE", "Golden Hour", .gold200, 0.85),
            st("LANDSCAPE", "Golden Hour Landscape", .sunset, 0.8, grid: 3),
            st("LANDSCAPE", "Travel", .ektar, 0.8),
            st("LANDSCAPE", "Winter Snow", .frost, 0.8, bias: 0.7),
            st("LANDSCAPE", "Desert Dunes", .desert, 0.85, grid: 3),
            st("LANDSCAPE", "Mountain Peaks", .alpine, 0.9, grid: 3, steady: true),
            st("LANDSCAPE", "Sunrise Glow", .sunset, 0.7, grid: 3, glow: 0.2, bias: -0.3),
            st("LANDSCAPE", "Sunset Sky", .sunset, 0.9, grid: 3, bias: -0.7),
            st("LANDSCAPE", "Blue Hour Landscape", .blueHour, 0.8, grid: 3, steady: true),
            st("LANDSCAPE", "Seascape", .beach, 0.9, grid: 3),
            st("LANDSCAPE", "Ocean Waves Silk", .beach, 0.8, mode: "LONG", grid: 3),
            st("LANDSCAPE", "Forest Trail", .forest, 0.9, grid: 1),
            st("LANDSCAPE", "Autumn Foliage", .autumn, 0.9, grid: 3),
            st("LANDSCAPE", "Waterfall Day", .forest, 0.8, mode: "LONG", grid: 0),
            st("LANDSCAPE", "City Skyline", .tealOrange, 0.7, grid: 3, steady: true),
            st("LANDSCAPE", "Wide Vista", .velvia, 0.7, grid: 3),
            st("LANDSCAPE", "Panorama Landscape", .velvia, 0.7, mode: "PANO", grid: 1),
            st("LANDSCAPE", "Lake Reflections", .provia, 0.9, grid: 2, steady: true),
            st("LANDSCAPE", "Golden Fields", .sunkissed, 0.8, grid: 3, bias: -0.3),
            // NIGHT & LONG EXPOSURE
            // INDOOR (home, cafe, restaurant, office light)
            st("INDOOR", "Indoor · Warm Bulbs", .indoorTrue, 1, grid: 1, steady: true, bias: 0.3),
            st("INDOOR", "Indoor · Cozy Lamp Light", .indoorCozy, 0.9, grid: 1, steady: true, bias: 0.3),
            st("INDOOR", "Indoor · Window Light", .airy, 0.7, grid: 1, bias: -0.3),
            st("INDOOR", "Indoor · Low Light", .indoorTrue, 1, grid: 0, steady: true, bias: 0.7),
            st("INDOOR", "Indoor · Room & Interior", .indoorTrue, 0.9, grid: 4, ratio: "3:2", steady: true, bias: 0.3),
            st("INDOOR", "Indoor · Fluorescent / Office", .menuClean, 0.9, grid: 1, steady: true),
            st("INDOOR", "Indoor · Restaurant & Cafe", .indoorCozy, 0.9, grid: 1, glow: 0.1, steady: true, bias: 0.3),
            st("INDOOR", "Indoor · Party & Events", .indoorTrue, 0.8, grid: 0, manual: (iso: 800, shutter: 1.0 / 125), burst: true, glow: 0.15),
            st("NIGHT", "Night", .cinestill, 0.6, mode: "NIGHT"),
            st("NIGHT", "Black Sky Stars", .midnight, 0.5, mode: "STARS", grid: 0, dark: 2, steady: true),
            st("NIGHT", "Milky Way", .midnight, 0.6, mode: "STARS", grid: 0, dark: 1, steady: true),
            st("NIGHT", "Night Sky", .midnight, 0.7, mode: "STARS", grid: 0, steady: true),
            st("NIGHT", "Constellations", .midnight, 0.6, mode: "STARS", grid: 0, sky: true, steady: true),
            st("NIGHT", "Moonlit Landscape", .blueHour, 0.8, mode: "NIGHT", grid: 3, steady: true),
            st("NIGHT", "Blue Hour City", .blueHour, 0.85, steady: true),
            st("NIGHT", "Neon Night Walk", .neon, 0.9, manual: (iso: 800, shutter: 1.0 / 60), steady: true),
            st("NIGHT", "Light Trails", .original, 1, mode: "TRAIL", grid: 0),
            st("NIGHT", "Fireworks", .original, 1, mode: "TRAIL", grid: 0),
            st("NIGHT", "Waterfall Silk", .original, 1, mode: "LONG", grid: 0),
            // STREET
            st("STREET", "Street", .leica, 0.9),
            st("STREET", "B&W Classic", .triX, 1),
            st("STREET", "Moody B&W", .drama, 1, grid: 0, grain: 0.2),
            st("STREET", "Architecture", .provia, 1, grid: 4),
            st("STREET", "Cinema", .arri, 1, grid: 0),
            st("STREET", "Concert", .moody, 0.7, manual: (iso: 1600, shutter: 1.0 / 60), burst: true),
            // WEATHER
            st("WEATHER", "Rain · Freeze Drops", .moody, 0.85, manual: (iso: 800, shutter: 1.0 / 1000), burst: true),
            st("WEATHER", "Rain · Soft Streaks", .blueHour, 0.7, manual: (iso: 200, shutter: 1.0 / 30)),
            st("WEATHER", "Rain · Light Streaks", .moody, 0.8, mode: "TRAIL", grid: 0),
            st("WEATHER", "Rainy Night Street", .cinestill, 0.85, manual: (iso: 640, shutter: 1.0 / 125), burst: true),
            st("WEATHER", "Foggy Morning", .airy, 0.8, grid: 0, glow: 0.3, bias: 0.4),
            st("WEATHER", "Storm Clouds", .storm, 0.9, grid: 3, bias: -0.3),
            st("WEATHER", "Lightning Capture", .storm, 0.8, mode: "TRAIL", grid: 0),
            st("WEATHER", "Rainbow & Sky", .vividSky, 0.8, grid: 3, bias: -0.3),
            st("WEATHER", "Snowfall", .frost, 0.8, grid: 0, manual: (iso: 400, shutter: 1.0 / 500), burst: true, bias: 0.7),
            st("WEATHER", "Rain on Glass", .misty, 0.9, grid: 0, steady: true, bias: -0.3),
            st("WEATHER", "Misty Forest", .misty, 0.9, grid: 3, glow: 0.2, bias: 0.3),
            st("WEATHER", "Soft Overcast", .provia, 0.9, grid: 1, bias: 0.3),
            st("WEATHER", "Harsh Sun Control", .desert, 0.7, grid: 1, zebra: true, bias: -0.7),
            st("WEATHER", "Moving Clouds", .vividSky, 0.8, mode: "LONG", grid: 3),
            st("WEATHER", "Sunset After Rain", .sunset, 0.9, grid: 3, glow: 0.2, bias: -0.3),
            // CREATIVE
            st("CREATIVE", "Polaroid", .polaroid, 1, frame: true),
            st("CREATIVE", "Vintage Film", .vintage70, 0.9, grain: 0.3, leak: 1, dust: 0.5),
            st("CREATIVE", "Dreamy Pastel", .pastel, 0.9, glow: 0.35),
            st("CREATIVE", "Y2K Digicam", .digicam, 1, grain: 0.3),
            st("CREATIVE", "Sun Leak", .sunkissed, 0.8, leak: 2, dust: 0.3),
            st("CREATIVE", "Cyber Neon", .neon, 1, glow: 0.3, leak: 3),
            // PRO
            st("PRO", "Pro Manual", .original, 1, zebra: true),
            st("PRO", "Macro Detail", .ektar, 0.7, steady: true),
            st("PRO", "Food", .airy, 0.8, grid: 0, glow: 0.1),
            st("PRO", "Action Burst", .velvia, 0.6, manual: (iso: 800, shutter: 1.0 / 1000), burst: true),
            st("PRO", "Tripod Sharp", .original, 1, grid: 1, steady: true)
        ]
    }
    private func presetIcon(_ p: CamPreset) -> String {
        if p.name.hasPrefix("Rain") { return "cloud.rain" }
        if p.name.hasPrefix("Indoor") { return p.name.contains("Window") ? "window.vertical.open" : p.name.contains("Party") ? "party.popper" : p.name.contains("Restaurant") ? "fork.knife" : "lightbulb" }
        let byName: [String: String] = ["Winter Snow": "snowflake", "Action Burst": "figure.run", "Food": "fork.knife", "Macro Detail": "camera.macro",
                                        "Fireworks": "sparkle", "Constellations": "sparkles", "Black Sky Stars": "sparkles", "Milky Way": "moon.stars", "Moonlit Landscape": "moon.stars", "Waterfall Silk": "drop.fill", "Night Sky": "moon.stars", "Foggy Morning": "cloud.fog",
                                        "Concert": "music.mic",
                                        "Storm Clouds": "cloud.bolt", "Lightning Capture": "bolt.fill", "Rainbow & Sky": "rainbow", "Snowfall": "snowflake", "Rain on Glass": "drop",
                                        "Misty Forest": "cloud.fog", "Soft Overcast": "cloud", "Harsh Sun Control": "sun.max", "Moving Clouds": "wind", "Sunset After Rain": "sunset",
                                        "Mountain Peaks": "mountain.2", "Sunrise Glow": "sunrise", "Sunset Sky": "sunset", "Blue Hour Landscape": "moon", "Seascape": "water.waves",
                                        "Ocean Waves Silk": "water.waves", "Forest Trail": "tree", "Autumn Foliage": "leaf", "Waterfall Day": "drop.fill", "City Skyline": "building.2",
                                        "Wide Vista": "arrow.left.and.right", "Panorama Landscape": "pano", "Lake Reflections": "water.waves", "Golden Fields": "sun.haze", "Menu Shot · Delivery Apps": "fork.knife", "Flat Lay · Overhead": "square.grid.2x2", "45° Plated Dish": "fork.knife",
                                        "Dark & Moody Food": "moon.stars", "Rustic Table": "fork.knife", "Close-up Texture": "camera.macro", "Steam & Sizzle": "flame",
                                        "Drinks & Beverages": "cup.and.saucer", "Bakery & Desserts": "birthday.cake", "Pizza & Burgers": "flame",
                                        "Packaged Food & Boxes": "shippingbox", "Kitchen Interior": "building.2", "Architecture": "building.2", "Tripod Sharp": "scope", "Desert Dunes": "sun.dust"]
        if let icon = byName[p.name] { return icon }
        switch p.mode { case "NIGHT": return "moon.stars"; case "TRAIL": return "car.rear.road.lane"; case "PORTRAIT": return "person.crop.circle"; default: return "camera.aperture" }
    }
    /// Back to a clean, normal camera. Saved presets and your custom look are kept.
    private func resetAll() {
        haptic(.medium)
        lookRaw = Look.original.rawValue; lookStrength = 1
        peaking = false; zebra = false; showHistogram = false
        burstOn = false; bracketOn = false; hdrOn = false; frameOn = false; addTimestamp = false
        timerDelay = 0; gridStyle = 1; aspect = "16:9"
        portraitBlur = 0.6; trailSeconds = 10; intervalEvery = 5; intervalShots = 25
        quality = 1; videoRange = "SDR"; videoCodec = "HEVC"; nightSeconds = 0; astroSeconds = 20; astroTrails = false; skyDark = 1; extraGrain = 0; extraGlow = 0; leakKind = 0; extraDust = 0; steadyWait = false; suggestOn = true
        macroActive = false
        activePreset = nil
        skyMap = false; aligningSky = false
        selectMode("PHOTO")
        camera.resetCamera()
        camera.message = "Settings reset to normal"
    }
    #if targetEnvironment(simulator)
    /// Debug-only: applies every starter preset and checks that every setting really took effect.
    private func runPresetSelfTest() {
        var lines: [String] = [], fails = 0, count = 0
        func check(_ ok: Bool, _ msg: @autoclosure () -> String) { if !ok { fails += 1; lines.append("FAIL " + msg()) } }
        for l in Look.allCases {
            let sp = l.spec
            check(sp.sat >= 0 && sp.contrast > 0 && sp.kelvin > 2000 && sp.kelvin < 12000, "look \(l.rawValue): spec out of range")
            check(!l.blurb.isEmpty, "look \(l.rawValue): missing blurb")
        }
        let names = starters.map { $0.preset.name }
        check(Set(names).count == names.count, "duplicate preset names: \(names.filter { n in names.filter { $0 == n }.count > 1 })")
        for item in starters {
            let p = item.preset, tag = "[\(p.name)]"
            count += 1
            check(Look(rawValue: p.look) != nil, "\(tag) unknown look \(p.look)")
            check(ModeGroup.allCases.contains { $0.modes.contains(p.mode ?? "PHOTO") }, "\(tag) unknown mode \(p.mode ?? "nil")")
            check((0...4).contains(p.grid), "\(tag) grid \(p.grid)")
            check(Self.presetCategories.contains(item.cat), "\(tag) category \(item.cat)")
            check(p.strength >= 0 && p.strength <= 1, "\(tag) strength")
            if let r = p.ratio { check(["1:1", "4:3", "3:2", "16:9"].contains(r), "\(tag) ratio \(r)") }
            if p.manualExposure {
                check(p.iso >= 25 && p.iso <= 3200, "\(tag) iso \(p.iso)")
                check(p.shutter >= 1.0 / 8000 && p.shutter <= 1, "\(tag) shutter \(p.shutter)")
            }
            let before = aspect
            applyPreset(p)
            check(lookRaw == p.look, "\(tag) look not applied: \(lookRaw)")
            check(abs(lookStrength - p.strength) < 0.001, "\(tag) strength not applied")
            check(mode == (p.mode ?? "PHOTO"), "\(tag) mode not applied: \(mode)")
            check(camera.nightMode == (p.mode == "NIGHT"), "\(tag) camera.nightMode")
            check(camera.portraitMode == (p.mode == "PORTRAIT"), "\(tag) camera.portraitMode")
            check(gridStyle == p.grid, "\(tag) grid not applied")
            check(peaking == p.peaking && zebra == p.zebra && showHistogram == p.histogram, "\(tag) assist tools not applied")
            check(burstOn == p.burst && bracketOn == p.bracket && frameOn == p.frame, "\(tag) capture options not applied")
            check(camera.autoExposure == !p.manualExposure, "\(tag) exposure mode wrong (autoExposure=\(camera.autoExposure))")
            if p.manualExposure {
                check(abs(camera.iso - p.iso) < 0.5, "\(tag) iso not applied: \(camera.iso)")
                check(abs(camera.shutter - p.shutter) < 1e-6, "\(tag) shutter not applied: \(camera.shutter)")
            }
            check(abs(camera.exposureBias - (p.bias ?? 0)) < 0.01, "\(tag) bias not applied: \(camera.exposureBias)")
            check(abs(extraGrain - (p.grain ?? 0)) < 0.001 && abs(extraGlow - (p.glow ?? 0)) < 0.001, "\(tag) grain/glow")
            check(leakKind == (p.leak ?? 0) && abs(extraDust - (p.dust ?? 0)) < 0.001, "\(tag) leak/dust")
            check(steadyWait == (p.steady ?? false), "\(tag) steady")
            check(aspect == before, "\(tag) changed the aspect ratio: \(before) → \(aspect)")
            check(activePresetName == p.name, "\(tag) not shown as active (\(activePresetName ?? "nil"))")
            check(!presetIcon(p).isEmpty, "\(tag) icon")
        }
        // saved presets must survive a save / load round trip, including the new optional fields
        if let first = starters.first?.preset, let data = try? JSONEncoder().encode([first]),
           let back = try? JSONDecoder().decode([CamPreset].self, from: data), let b = back.first {
            check(b.name == first.name && b.ratio == first.ratio && b.bias == first.bias && b.steady == first.steady, "JSON round trip changed the preset")
        } else { check(false, "JSON round trip failed") }
        // presets saved by older versions (no new fields) must still load
        let old = #"[{"id":"11111111-1111-1111-1111-111111111111","name":"Old","look":"LEICA","strength":0.9,"aspect":"4:3","grid":1,"timer":0,"frame":false,"burst":false,"bracket":false,"peaking":false,"zebra":false,"histogram":false,"manualExposure":false,"iso":100,"shutter":0.008,"manualWB":false,"temperature":5200,"tint":0}]"#
        check((try? JSONDecoder().decode([CamPreset].self, from: Data(old.utf8)))?.first?.name == "Old", "old saved presets no longer decode")
        lines.insert("starter presets: \(count)   looks: \(Look.allCases.count)   failures: \(fails)", at: 0)
        if fails == 0 { lines.append("ALL CHECKS PASSED") }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("preset_report.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        resetAll()
    }
    #endif
    private func saveCurrentPreset() {
        haptic(.medium)
        let p = CamPreset(name: "\(look.rawValue) \(presets.count + 1)", look: look.rawValue, strength: lookStrength, aspect: aspect, grid: gridStyle, timer: timerDelay,
                          frame: frameOn, burst: burstOn, bracket: bracketOn, peaking: peaking, zebra: zebra, histogram: showHistogram,
                          manualExposure: !camera.autoExposure, iso: camera.iso, shutter: camera.shutter,
                          manualWB: !camera.autoWB, temperature: camera.temperature, tint: camera.tint, mode: mode, ratio: aspect,
                          grain: extraGrain, glow: extraGlow, leak: leakKind, dust: extraDust, steady: steadyWait, bias: camera.exposureBias)
        presets = presets + [p]
        camera.message = "Preset saved"
    }
    private func applyPreset(_ p: CamPreset) {
        haptic(.medium)
        activePreset = p
        lookRaw = p.look; lookStrength = p.strength; gridStyle = p.grid; timerDelay = p.timer   // aspect ratio is left as you set it
        frameOn = p.frame; burstOn = p.burst; bracketOn = p.bracket; peaking = p.peaking; zebra = p.zebra; showHistogram = p.histogram
        if p.manualExposure { camera.setISO(p.iso); camera.setShutter(p.shutter) } else { camera.setAuto("EXP") }
        if p.manualWB { camera.setWhiteBalance(p.temperature); camera.setTint(p.tint) } else { camera.setAuto("WB") }
        extraGrain = p.grain ?? 0; extraGlow = p.glow ?? 0; leakKind = p.leak ?? 0; extraDust = p.dust ?? 0
        steadyWait = p.steady ?? false
        if let sk = p.sky { skyMap = sk }
        if let d = p.dark { skyDark = d }
        camera.setBias(p.bias ?? 0)
        if let m = p.mode { selectMode(m) }
        let tips: [String: String] = [
            "Rain · Freeze Drops": "Rain · 1/1000s freezes each drop. Shoot against a dark background with light behind the rain; raise ISO if too dark.",
            "Rain · Soft Streaks": "Rain · 1/30s turns drops into soft streaks. Steady the phone; lower ISO if bright.",
            "Rain · Light Streaks": "Rain · Trail stacks the brightest drops into lines. Use a tripod and a dark backdrop with a light behind.",
            "Rainy Night Street": "Rainy night · 1/125s keeps reflections sharp. Look for wet roads and neon.",
            "Menu Shot · Delivery Apps": "Menu · Pick 1:1 in FORMAT for delivery apps. True whites: daylight by a window, no flash, set WB with PICK on a white plate.",
            "Flat Lay · Overhead": "Flat lay · Hold the phone straight above the dish, parallel to the table. Window light from the side; peaking shows sharp edges.",
            "45° Plated Dish": "45° shot · Keep the camera at table-edge height, tilted down about 45°. Try the 2× crop for flattering perspective.",
            "Dark & Moody Food": "Moody · Use one soft side light, dark backdrop. −0.3 EV keeps the shadows rich; the app waits for a steady moment.",
            "Rustic Table": "Rustic · Wood, linen, natural light. Soft grain adds a homely feel.",
            "Close-up Texture": "Close-up · Move back slightly and use 2×, or 0.5× very close. Tap to focus on the best detail; peaking helps.",
            "Steam & Sizzle": "Sizzle · 1/250s with burst catches steam and drips. Put a dark backdrop behind the steam and light from behind.",
            "Drinks & Beverages": "Drinks · Backlight the glass so liquid glows; +0.3 EV keeps it bright and fresh.",
            "Bakery & Desserts": "Desserts · Soft, bright pastel tone. Shoot near a window; +0.3 EV keeps whites clean.",
            "Pizza & Burgers": "Pizza and burgers · Warm tone makes cheese and crust look hot. Use the 2× crop for a tight, appetising frame.",
            "Indoor · Warm Bulbs": "Warm bulbs · Corrects the orange cast of normal bulbs. Tap a white wall to set white balance for exact colour; hold steady, +0.3 EV.",
            "Indoor · Cozy Lamp Light": "Cozy light · Keeps the warm lamp mood but cleans the colour. Stand near a lamp and face the light for soft, flattering shots.",
            "Indoor · Window Light": "Window light · Put the subject beside the window, not in front of it. −0.3 EV protects the bright window; the light is soft and free.",
            "Indoor · Low Light": "Low light · Brightens dim rooms with +0.7 EV. Hold still (steady wait), brace on a wall, and use Night mode if it is very dark.",
            "Indoor · Room & Interior": "Room · Use 0.5× ultra-wide and the diagonal guides. Keep the phone level; turn all lights on and shoot from a corner.",
            "Indoor · Fluorescent / Office": "Office light · Neutral look that removes the greenish tube-light tint. Tap a white wall to lock white balance.",
            "Indoor · Restaurant & Cafe": "Cafe · Keeps the warm ambience. Tap the food or face to expose it, and steady wait avoids blur in dim light.",
            "Indoor · Party & Events": "Party · Fast 1/125s freezes movement; burst takes 5. Glow softens lights. Stay close — no zoom in dim rooms.",
            "Packaged Food & Boxes": "Packaging · Pick 1:1 in FORMAT; zebra warns about blown whites. Diagonal guides help line up boxes straight.",
            "Kitchen Interior": "Interior · Use 0.5× ultra-wide and the diagonal guides. Keep the phone level and steady; +0.3 EV for bright kitchens.",
            "Storm Clouds": "Storm · Tap the brightest cloud edge so the sky keeps its detail; −0.3 EV adds drama. Watch the HL badge.",
            "Lightning Capture": "Lightning · Use a tripod at night, press the shutter, and let Trail stack each flash. Stop after a few strikes.",
            "Rainbow & Sky": "Rainbow · Keep the sun behind you and the rain in front. −0.3 EV deepens the colours.",
            "Snowfall": "Snowfall · 1/500s freezes the flakes, burst takes 5. A dark background makes flakes stand out; +0.7 EV keeps snow white.",
            "Rain on Glass": "Rain on glass · Focus on the drops (tap them) and let lights behind blur into bokeh. Peaking shows what is sharp.",
            "Misty Forest": "Mist · Shoot into the light with +0.3 EV, and use trees as layers for depth. Soft glow adds atmosphere.",
            "Soft Overcast": "Overcast · Flat light is great for even colour. +0.3 EV stops grey skies looking dull; keep the sky out of frame if it's bland.",
            "Harsh Sun Control": "Harsh sun · −0.7 EV protects highlights; zebra shows blown areas. Shoot in open shade or use side light.",
            "Moving Clouds": "Moving clouds · Long mode averages the sky over time. Use a tripod and 10–30 seconds.",
            "Sunset After Rain": "After rain · Look for wet reflections and breaking light. −0.3 EV keeps the sky colour.",
            "Mountain Peaks": "Mountains · Use the telephoto for compression or 0.5× for scale. Golden-ratio guides help place the peak; wait for steady.",
            "Sunrise Glow": "Sunrise · Arrive early, expose for the sky (−0.3 EV). Glow adds soft light around the sun.",
            "Sunset Sky": "Sunset · −0.7 EV keeps the colours rich instead of washed out. Tap the sky near the sun to set exposure.",
            "Blue Hour Landscape": "Blue hour · Use a tripod; the app waits for a steady moment. Check the histogram so shadows are not crushed.",
            "Seascape": "Seascape · Keep the horizon on a golden-ratio line and level (use the level line). Beach look keeps blues clean.",
            "Ocean Waves Silk": "Waves · Long mode averages the water into silky texture. Use a tripod and 5–10 seconds.",
            "Forest Trail": "Forest · Look for a path or light beams. Green look keeps foliage natural; watch for dark shadows in the histogram.",
            "Autumn Foliage": "Autumn · Backlit leaves glow. Shoot in soft light and keep some sky for contrast.",
            "Waterfall Day": "Waterfall · Long mode makes water silky. Use a tripod, 5–10 seconds, and shade the lens from bright sun.",
            "City Skyline": "Skyline · Use a tripod at dusk, wait for steady. Teal & orange look adds a cinematic feel.",
            "Wide Vista": "Wide vista · Use 0.5× for big scenes with a strong foreground. Keep the horizon level.",
            "Panorama Landscape": "Panorama · Pan slowly left to right, keep the phone level and overlap each frame.",
            "Lake Reflections": "Reflections · Centre the horizon for symmetry. Wait for calm water and a steady moment.",
            "Golden Fields": "Golden fields · Low sun from the side gives texture. −0.3 EV protects the sky.",
            "Winter Snow": "Snow · +0.7 EV keeps snow white instead of grey. Watch the HL badge for blown highlights.",
            "Backlit Silhouette": "Silhouette · −1 EV darkens the subject against a bright sky. Tap the sky to set exposure.",
            "Fireworks": "Fireworks · Trail stacks each burst. Use a tripod, press the shutter, then stop after the show.",
            "Waterfall Silk": "Waterfall · Long mode averages the scene so moving water turns silky. Use a tripod.",
            "Black Sky Stars": "Black sky · Tripod on, away from lights. Shoots for the time you choose (try 60 s+) and removes the sky glow so the stars stand out on black. Pick NATURAL / DARK / BLACK in FORMAT.",
            "Milky Way": "Milky Way · Needs a very dark sky (far from cities), moon down, tripod, 2 minutes or more. The faint band shows best in summer facing the galactic centre (south in the northern hemisphere).",
            "Night Sky": "Night sky · Stars mode: tripod required. Pick how long to shoot in FORMAT (try 30s+). Tap the shutter again to finish early.",
            "Constellations": "Constellations · Sky map is on: allow location, hold the phone upright, tripod on. Use ALIGN MAP if the lines are a few degrees off. Shoot 60 s or more away from city lights.",
            "Moonlit Landscape": "Moonlight · Night mode with a longer time (try 20–30s in FORMAT) on a tripod for clean shadows.",
            "Action Burst": "Action · 1/1000s freezes motion; burst takes 5 shots. Add light if it looks dark.",
            "Macro Detail": "Macro · Use the ultra-wide (0.5×) up close. Peaking shows what is sharp."
        ]
        camera.message = tips[p.name] ?? "Preset: \(p.name)"
    }

    // MARK: Tools
    private func toolSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(0.9).foregroundStyle(Theme.muted)
            Flow(spacing: 8) { content() }
        }
    }
    private var toolsPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                toolSection("FOCUS & EXPOSURE ASSIST") {
                    toggleChip("scope", "PEAKING", $peaking)
                    toggleChip("circle.lefthalf.striped.horizontal", "ZEBRA", $zebra)
                    toggleChip("chart.bar.fill", "HISTOGRAM", $showHistogram)
                    toggleChip("hand.raised", "WAIT FOR STEADY", $steadyWait)
                    toggleChip("sparkles", "LOOK SUGGESTIONS", $suggestOn)
                }
                toolSection("SKY MAP") {
                    toggleChip("sparkles", "CONSTELLATIONS", $skyMap)
                    toggleChip("hand.draw", "ALIGN MAP", Binding(get: { aligningSky }, set: { on in aligningSky = on; if on { skyMap = true } }))
                    toggleChip("textformat", "LABELS IN PHOTO", $skyBurn)
                }
                toolSection("LOCKS") {
                    toggleChip("lock", "AE LOCK", Binding(get: { camera.aeLocked }, set: { camera.setAELock($0) }))
                    toggleChip("scope", "AF LOCK", Binding(get: { camera.afLocked }, set: { camera.setAFLock($0) }))
                }
                toolSection("MULTI-SHOT") {
                    toggleChip("square.stack.3d.down.right", "BURST ×5", $burstOn)
                    toggleChip("plusminus", "BRACKET ±2EV", $bracketOn)
                    toggleChip("sparkles", "HDR MERGE", $hdrOn)
                }
                toolSection("OUTPUT") {
                    toggleChip("rectangle.inset.filled", "PHOTO FRAME", $frameOn)
                }
                toolSection("EXPORT") {
                    Button { haptic(); showPDF = true } label: { chip("doc.richtext", camera.sessionCount > 0 ? "PHOTOS → PDF (\(camera.sessionCount))" : "PHOTOS → PDF") }.buttonStyle(PressStyle())
                }
                toolSection("INTERFACE") {
                    toggleChip("eye.slash", "AUTO-HIDE UI", $autoHide)
                    Button { seenGuide = false } label: { chip("questionmark.circle", "SHOW GUIDE") }.buttonStyle(PressStyle())
                    Button { resetAll() } label: { chip("arrow.counterclockwise", "RESET ALL") }.buttonStyle(PressStyle())
                }
                Text("Peaking outlines sharp edges; zebra marks blown highlights. Tap the histogram to switch between brightness and RGB (HL / SH badges warn of clipped highlights and shadows). Wait for Steady holds the shutter until the phone stops moving. HDR Merge fuses the 3 bracket shots. Tap the viewfinder to set the exposure point (iOS has no separate spot-metering mode). A volume button also shoots. Auto-hide fades menus after 5 s — tap the bottom-left corner to bring them back.")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 190)
        .padding(14)
        .neuCard(22)
        .padding(.horizontal, 14)
    }
    private func toggleChip(_ icon: String, _ title: String, _ binding: Binding<Bool>) -> some View {
        Button { haptic(); binding.wrappedValue.toggle() } label: { chip(icon, title, highlighted: binding.wrappedValue) }.buttonStyle(PressStyle())
    }

    // MARK: Format
    private var formatPanel: some View {
        VStack(spacing: 10) {
            if isVideo {
                VStack(alignment: .leading, spacing: 10) {
                    if mode != "SLOW" {
                        HStack(spacing: 8) {
                            Text("RESOLUTION").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                            ForEach(camera.supportedVideoResolutions, id: \.self) { v in
                                Button { haptic(.soft); camera.videoResolution = v; clampFrameRate() } label: { chip("video", v, highlighted: camera.videoResolution == v) }.buttonStyle(PressStyle())
                            }
                            Spacer(minLength: 0)
                        }
                    } else { HStack { chip("video", "HD"); Spacer(minLength: 0) } }
                    if mode != "TIMELAPSE" {
                        let rates = mode == "SLOW" ? camera.supportedSlowMotionRates : mode == "CINEMATIC" ? camera.supportedCinematicFrameRates : camera.videoRates(for: camera.videoResolution)
                        let current = mode == "SLOW" ? camera.slowMotionFPS : camera.videoFPS
                        Text("FRAME RATE").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                        Flow(spacing: 6) {
                            ForEach(rates, id: \.self) { v in
                                Button { haptic(.soft); if mode == "SLOW" { camera.slowMotionFPS = v } else { camera.videoFPS = v; clampVideoOptions() } } label: { chip("speedometer", fpsLabel(v) + " fps", highlighted: current == v) }.buttonStyle(PressStyle())
                            }
                        }
                        if mode == "VIDEO" {
                            let ranges = camera.videoRanges(for: camera.videoResolution, fps: camera.videoFPS)
                            let codecs = camera.videoCodecs(for: camera.videoResolution, fps: camera.videoFPS, range: videoRange)
                            Text("DYNAMIC RANGE").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                            HStack(spacing: 6) {
                                ForEach(ranges, id: \.self) { r in
                                    Button { haptic(.soft); videoRange = r; clampVideoOptions() } label: { chip("circle.lefthalf.filled", r == "HDR" ? "HDR" : r == "LOG" ? "APPLE LOG" : "SDR", highlighted: videoRange == r) }.buttonStyle(PressStyle())
                                }
                                Spacer(minLength: 0)
                            }
                            Text("CODEC").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                            HStack(spacing: 6) {
                                ForEach(codecs, id: \.self) { c in
                                    Button { haptic(.soft); videoCodec = c } label: { chip("film", c == "PRORES" ? "ProRes" : c, highlighted: videoCodec == c) }.buttonStyle(PressStyle())
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        Text("PAL regions use 25 / 50 fps, NTSC 30 / 60, film 24. Only what your iPhone supports at the chosen resolution is shown. HDR and Apple Log need a 10-bit format; Log looks flat until graded. ProRes files are very large (a minute of 4K can be several GB). While recording, the exact resolution, frame rate and codec that started are shown at the top.")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    } else { HStack { chip("speedometer", "30 fps capture"); Spacer(minLength: 0) } }
                }.disabled(camera.isRecording)
            } else {
                if mode == "PORTRAIT" {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle").foregroundStyle(accent)
                        Text("BLUR").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        Slider(value: $portraitBlur, in: 0...1).tint(accent)
                        Text("\(Int(portraitBlur * 100))%").font(.system(size: 11, weight: .bold).monospacedDigit()).frame(width: 40, alignment: .trailing)
                    }
                    Text("Blurs the background around people when you shoot. Works on the main and selfie cameras.")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                if mode == "TRAIL" || mode == "LONG" {
                    HStack(spacing: 8) {
                        ForEach([5, 10, 20, 30], id: \.self) { sec in
                            Button { haptic(.soft); trailSeconds = sec } label: { chip("timer", "\(sec)s", highlighted: trailSeconds == sec) }.buttonStyle(PressStyle())
                        }
                        Spacer(minLength: 0)
                    }
                    Text(mode == "LONG" ? "Averages the live view over the chosen time — silky water, clouds and crowds fade away. Use a tripod. Output is about 3 MP." : "Stacks the brightest parts of the live view over the chosen time — cars, stars, sparklers. Use a tripod. Output is about 3 MP.")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                if mode == "INTERVAL" {
                    HStack(spacing: 8) {
                        Text("EVERY").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        ForEach([2, 5, 10, 30], id: \.self) { sec in
                            Button { haptic(.soft); intervalEvery = sec } label: { chip("timer", "\(sec)s", highlighted: intervalEvery == sec) }.buttonStyle(PressStyle())
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Text("SHOTS").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        ForEach([10, 25, 50, 100], id: \.self) { n in
                            Button { haptic(.soft); intervalShots = n } label: { chip("photo.stack", "\(n)", highlighted: intervalShots == n) }.buttonStyle(PressStyle())
                        }
                        Spacer(minLength: 0)
                    }
                    Text("Takes a photo automatically on a timer. Screen stays awake. Tap the shutter again to stop.")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                if mode == "NIGHT" {
                    HStack(spacing: 6) {
                        Text("SHOOT FOR").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                        ForEach([0, 5, 10, 20, 30, 60], id: \.self) { sec in
                            Button { haptic(.soft); nightSeconds = sec } label: {
                                Text(sec == 0 ? "AUTO" : "\(sec)s").font(.system(size: 10, weight: .bold)).foregroundStyle(nightSeconds == sec ? Color.black : .white.opacity(0.7))
                                    .padding(.horizontal, 9).frame(height: 28)
                                    .background { if nightSeconds == sec { Capsule().fill(Theme.gold) } else { Capsule().fill(Color.white.opacity(0.1)) } }
                            }.buttonStyle(PressStyle())
                        }
                        Spacer(minLength: 0)
                    }
                    Text("AUTO takes about 6 quick frames (≈3 s). A longer time keeps merging more frames for less noise and brighter shadows. Tap the shutter again to finish early.")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                if mode == "STARS" {
                    HStack(spacing: 6) {
                        Text("SHOOT FOR").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                        ForEach([10, 20, 30, 60, 120], id: \.self) { sec in
                            Button { haptic(.soft); astroSeconds = sec } label: {
                                Text(sec >= 60 ? "\(sec / 60)m" : "\(sec)s").font(.system(size: 10, weight: .bold)).foregroundStyle(astroSeconds == sec ? Color.black : .white.opacity(0.7))
                                    .padding(.horizontal, 9).frame(height: 28)
                                    .background { if astroSeconds == sec { Capsule().fill(Theme.gold) } else { Capsule().fill(Color.white.opacity(0.1)) } }
                            }.buttonStyle(PressStyle())
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Text("STYLE").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                        chip("sparkles", "STARS", highlighted: !astroTrails)
                            .onTapGesture { haptic(.soft); astroTrails = false }
                        chip("circle.dotted", "STAR TRAILS", highlighted: astroTrails)
                            .onTapGesture { haptic(.soft); astroTrails = true }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Text("SKY").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                        ForEach(Array(["NATURAL", "DARK", "BLACK"].enumerated()), id: \.offset) { i, name in
                            Button { haptic(.soft); skyDark = i } label: { chip("moon.stars", name, highlighted: skyDark == i) }.buttonStyle(PressStyle())
                        }
                        Spacer(minLength: 0)
                    }
                    Flow(spacing: 8) {
                        toggleChip("sparkles", "CONSTELLATIONS", $skyMap)
                        toggleChip("hand.draw", "ALIGN MAP", Binding(get: { aligningSky }, set: { on in aligningSky = on; if on { skyMap = true } }))
                        toggleChip("textformat", "LABELS IN PHOTO", $skyBurn)
                    }
                    Text("Constellations draws the sky above you over the live view (uses your location, compass and tilt, so hold the phone upright). If the compass is a few degrees off, tap ALIGN MAP and drag until a bright star sits on its dot. LABELS IN PHOTO also draws the lines and names onto the finished picture.")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    Text("Tripod required. Shoots long, high-ISO frames with focus locked at infinity. STARS averages them for clean, bright stars; STAR TRAILS keeps every streak. The longer you shoot, the better. Tap the shutter again to finish early.")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                HStack(spacing: 8) {
                    Menu {
                        Button("HEIF") { camera.setPhotoFormat("HEIF") }
                        Button("JPEG") { camera.setPhotoFormat("JPEG") }
                        if camera.supportsRAW { Button("RAW + processed") { camera.setPhotoFormat("RAW") } }
                    } label: { chip("photo", camera.rawEnabled ? "DNG" : camera.photoFormat) }
                    Menu {
                        Button("12 MP") { camera.setPhotoResolution(12) }
                        if camera.has48MP { Button("48 MP · Main 1× lens") { macroActive = false; camera.setPhotoResolution(48) } }
                    } label: { chip("viewfinder", "\(camera.photoResolutionMP) MP") }
                    if camera.supportsMacro {
                        Button { haptic(); macroActive.toggle(); camera.setPhotoResolution(12); camera.setMacroMode(macroActive) } label: { chip("camera.macro", macroActive ? "MACRO ON" : "MACRO", highlighted: macroActive) }.buttonStyle(PressStyle())
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text("SHUTTER").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                    ForEach(Array(["FAST", "BALANCED", "BEST"].enumerated()), id: \.offset) { i, name in
                        Button { haptic(.soft); quality = i } label: {
                            Text(name).font(.system(size: 10, weight: .bold)).foregroundStyle(quality == i ? Color.black : .white.opacity(0.7))
                                .padding(.horizontal, 10).frame(height: 28)
                                .background { if quality == i { Capsule().fill(Theme.gold) } else { Capsule().fill(Color.white.opacity(0.1)) } }
                        }.buttonStyle(PressStyle())
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        ForEach(["1:1", "4:3", "3:2", "16:9"], id: \.self) { v in
                            Button { haptic(.soft); aspect = v } label: {
                                Text(v).font(.system(size: 11, weight: .bold, design: .default)).foregroundStyle(aspect == v ? Color.black : .white.opacity(0.6))
                                    .padding(.horizontal, 11).frame(height: 30).background { if aspect == v { Capsule().fill(Theme.gold) } }
                            }.buttonStyle(PressStyle())
                        }
                    }.padding(3).neuTrack()
                    Button { haptic(); timerDelay = timerDelay == 0 ? 3 : timerDelay == 3 ? 10 : 0 } label: { chip("timer", timerDelay == 0 ? "OFF" : "\(timerDelay)S", highlighted: timerDelay > 0) }.buttonStyle(PressStyle())
                    Button { haptic(); addTimestamp.toggle() } label: { chip("clock", "STAMP", highlighted: addTimestamp) }.buttonStyle(PressStyle())
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .neuCard(22)
        .padding(.horizontal, 14)
    }
    private func chip(_ icon: String, _ value: String, highlighted: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(value).font(.system(size: 11, weight: .bold, design: .default))
        }
        .foregroundStyle(highlighted ? Color.black : .white.opacity(0.88))
        .padding(.horizontal, 12).frame(height: 32)
        .neuToggle(highlighted)
    }

    // MARK: Shutter row
    private var capturing: Bool { camera.isRecording || camera.isTrailing || camera.isInterval || camera.nightBusy || camera.panoSweeping }
    private var shutterRow: some View {
        HStack {
            thumbnailView.hideable(uiHidden)
            Spacer()
            Button { shutterPressed() } label: {
                ZStack {
                    Circle().fill(Theme.raised).frame(width: 88, height: 88)
                        .overlay(Circle().stroke(Theme.bevel, lineWidth: 1.2))
                        .shadow(color: .black.opacity(0.85), radius: 10, x: 6, y: 8)
                        .shadow(color: .white.opacity(0.06), radius: 6, x: -4, y: -4)
                    Circle().stroke(capturing ? Color.red : Theme.champagne, lineWidth: 2.5).frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: capturing ? 8 : 31, style: .continuous)
                        .fill(capturing ? Color.red : (isVideo ? Color.red.opacity(0.9) : Theme.champagneLight))
                        .frame(width: capturing ? 28 : 58, height: capturing ? 28 : 58)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: capturing)
            }
            .buttonStyle(PressStyle())
            .disabled(countdown != nil || (mode == "SLOW" && !camera.slowMotionSupported) || (mode == "PANO" && camera.panoramaProcessing))
            .opacity(countdown != nil ? 0.5 : 1)
            Spacer()
            Button { haptic(); drawer = drawer == .looks ? .manual : .looks } label: {
                Image(systemName: "camera.filters").font(.system(size: 20)).foregroundStyle(drawer == .looks ? accent : .white)
                    .frame(width: 50, height: 50).neuRaisedCircle()
            }.buttonStyle(PressStyle()).hideable(uiHidden)
        }.padding(.horizontal, 28).padding(.top, 4)
    }
    private var thumbnailView: some View {
        Group {
            if let img = camera.lastThumbnail {
                Button { if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) } } label: {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.4), lineWidth: 1.5))
                }.buttonStyle(PressStyle())
                .contextMenu { Button("Photos → PDF…", systemImage: "doc.richtext") { showPDF = true } }
                .id(img.hashValue)
                .transition(.scale.combined(with: .opacity))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.1)).frame(width: 50, height: 50)
                    .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.4)))
            }
        }
        .overlay { if camera.isSaving { ProgressView().tint(accent).padding(8).background(.black.opacity(0.55), in: Circle()) } }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: camera.lastThumbnail)
    }

    private func shutterPressed() {
        if isVideo {
            haptic(.heavy)
            camera.toggleRecording(slowMotion: mode == "SLOW", timeLapse: mode == "TIMELAPSE", cinematic: mode == "CINEMATIC")
            return
        }
        camera.panoramaMode = mode == "PANO"
        camera.portraitMode = mode == "PORTRAIT"
        camera.selectedLook = look.rawValue
        camera.selectedAspect = aspect == "3:2" ? 3.0 / 2.0 : aspect == "16:9" ? 16.0 / 9.0 : aspect == "1:1" ? 1.0 : 4.0 / 3.0
        camera.timestampEnabled = addTimestamp
        if mode == "NIGHT" || mode == "STARS" {
            if camera.nightBusy { haptic(.medium); camera.stopNight(); return }      // tap again to finish early
            haptic(.medium)
            if askNightTime { showNightSheet = true } else { beginNightOrAstro() }
            return
        }
        if mode == "INTERVAL" {
            haptic(.heavy)
            camera.intervalSeconds = intervalEvery; camera.intervalCount = intervalShots
            if camera.isInterval { camera.stopInterval() } else { camera.startInterval() }
            return
        }
        if mode == "TRAIL" || mode == "LONG" {
            haptic(.heavy)
            camera.trailAverage = mode == "LONG"
            camera.trailDuration = trailSeconds
            if camera.isTrailing { camera.stopTrail() } else { camera.startTrail() }
            return
        }
        if mode == "PANO" {
            haptic(.medium)
            if camera.panoSweeping { camera.finishPanoSweep() } else { camera.startPanoSweep() }
            return
        }
        startCountdown { fireShutter() }
    }
    /// Starts Night / Stars with the chosen time (after the self-timer and the steady wait, if they are on).
    private func beginNightOrAstro() {
        camera.nightSeconds = nightSeconds; camera.astroSeconds = astroSeconds; camera.astroTrails = astroTrails; camera.astroSkyDarkness = skyDarkness
        let astro = mode == "STARS"
        startCountdown { whenSteady { if astro { camera.startAstro() } else { camera.startNight() } } }
    }
    /// Runs the action after the self-timer (immediately when the timer is off).
    private func startCountdown(then action: @escaping () -> Void) {
        guard timerDelay > 0 else { action(); return }
        countdown = timerDelay
        Task {
            while let current = countdown, current > 0 {
                haptic(.soft)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { countdown = max(0, current - 1) }
            }
            countdown = nil
            action()
        }
    }
    private func flashNow() { flash = true; withAnimation(.easeOut(duration: 0.18)) { flash = false } }
    private func fireShutter() {
        whenSteady {
            haptic(.rigid)
            flashNow()      // instant visual feedback, before any camera work
            if bracketOn { camera.bracket() } else if burstOn { camera.burst() } else { camera.capture() }
        }
    }
    /// Waits (up to 3 s) until the phone has been steady for 0.3 s, then runs the action.
    private func whenSteady(_ action: @escaping () -> Void) {
        guard steadyWait, !waitingSteady else { action(); return }
        waitingSteady = true
        camera.message = "Waiting for a steady moment…"
        Task {
            var waited = 0.0, steadyFor = 0.0
            while waited < 3.0 && steadyFor < 0.3 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                waited += 0.05
                steadyFor = level.shake == 0 ? steadyFor + 0.05 : 0
            }
            waitingSteady = false
            action()
        }
    }
}

// MARK: Preview view with tap / long-press / pinch
#if targetEnvironment(simulator)
/// Simulator-only: renders Vintage Film / Sun Leak / Cyber Neon on a sample picture so the effects can be looked at.
private func runLeakTest() {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let size = CGSize(width: 800, height: 1000)
    let f = UIGraphicsImageRendererFormat(); f.scale = 1
    let base = CIImage(image: UIGraphicsImageRenderer(size: size, format: f).image { r in
        let c = r.cgContext
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(red: 0.55, green: 0.7, blue: 0.9, alpha: 1).cgColor, UIColor(red: 0.8, green: 0.75, blue: 0.65, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        UIColor(red: 0.35, green: 0.5, blue: 0.3, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 650, width: 800, height: 350))
        UIColor(red: 0.85, green: 0.3, blue: 0.25, alpha: 1).setFill(); c.fill(CGRect(x: 250, y: 400, width: 300, height: 300))
    })!
    let ctx = CIContext()
    var lines: [String] = []
    func avg(_ i: CIImage) -> [Float] {
        let a = i.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: i.extent)])
        var px = [Float](repeating: 0, count: 4)
        ctx.render(a, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        return px
    }
    let cases: [(String, Look, Float, Int, Float, Float)] = [("original", .original, 1, 0, 0, 0), ("vintage_preset", .vintage70, 0.9, 1, 0.5, 0.3), ("sunleak_preset", .sunkissed, 0.8, 2, 0.3, 0), ("neon_preset", .neon, 1, 3, 0, 0), ("pixel", .pixel, 1, 0, 0, 0), ("glass", .glass, 1, 0, 0, 0), ("crt", .crt, 1, 0, 0, 0), ("grain", .filmGrain, 1, 0, 0, 0), ("neongreen", .neonGreen, 1, 0, 0, 0), ("mono", .mono, 1, 0, 0, 0)]
    for (name, look, strength, leak, dust, grain) in cases {
        LookProcessor.extraLeak = leak; LookProcessor.extraDust = dust; LookProcessor.extraGrain = grain
        let out = LookProcessor.apply(look, to: base, strength: strength)
        lines.append("\(name): avg rgb \(avg(out).prefix(3).map { String(format: "%.3f", $0) })")
        if let d = ctx.pngRepresentation(of: out, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) { try? d.write(to: docs.appendingPathComponent("leak_\(name).png")) }
    }
    let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: base.extent)
    lines.append("dust only over black (0.3): avg \(avg(LookProcessor.dust(black, amount: 0.3)).prefix(3).map { String(format: "%.4f", $0) })")
    do {
        let n = CIFilter.randomGenerator().outputImage!.cropped(to: base.extent)
        let opaque = n.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        lines.append("opaque noise avg: \(avg(opaque.cropped(to: base.extent)).map { String(format: "%.3f", $0) })")
        let th = opaque.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 27, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 27, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 27, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: -26.8, y: -26.8, z: -26.8, w: 1)])
        lines.append("thresholded avg: \(avg(th.cropped(to: base.extent)).map { String(format: "%.4f", $0) })  clamped: \(avg(th.applyingFilter("CIColorClamp").cropped(to: base.extent)).map { String(format: "%.4f", $0) })")
    }
    lines.append("noise raw avg: \(avg(CIFilter.randomGenerator().outputImage!.cropped(to: base.extent)).map { String(format: "%.3f", $0) })")
    LookProcessor.extraLeak = 0; LookProcessor.extraDust = 0; LookProcessor.extraGrain = 0
    try? lines.joined(separator: "\n").write(to: docs.appendingPathComponent("leak_report.txt"), atomically: true, encoding: .utf8)
}

/// Simulator-only: how much of the picture the OLD and NEW focus peaking paint on sharp, blurry-noisy and dense-texture pictures.
private func runPeakingTest() {
    var lines: [String] = []
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let ctx = CIContext()
    var seed: UInt64 = 777
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10_000) / 10_000 }
    let size = CGSize(width: 540, height: 720), format: UIGraphicsImageRendererFormat = { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()
    func render(_ draw: (CGContext) -> Void) -> CIImage {
        CIImage(image: UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) })!
    }
    func noise(_ c: CGContext, _ amount: CGFloat) { for _ in 0..<90_000 { c.setFillColor(UIColor(white: rnd(), alpha: amount).cgColor); c.fill(CGRect(x: rnd() * size.width, y: rnd() * size.height, width: 1.5, height: 1.5)) } }
    let sharp = render { c in
        UIColor(white: 0.45, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: size))
        for _ in 0..<40 { c.setFillColor(UIColor(white: rnd(), alpha: 1).cgColor); c.fill(CGRect(x: rnd() * 500, y: rnd() * 680, width: 40 + rnd() * 120, height: 30 + rnd() * 100)) }
    }
    let blurryNoisy = render { c in
        UIColor(white: 0.45, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: size))
        for _ in 0..<40 { c.setFillColor(UIColor(white: rnd(), alpha: 1).cgColor); c.fillEllipse(in: CGRect(x: rnd() * 500, y: rnd() * 680, width: 60 + rnd() * 120, height: 60 + rnd() * 100)) }
    }.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 14]).cropped(to: CGRect(origin: .zero, size: size))
    let blurryNoisyOverlay = render { c in noise(c, 0.35) }
    let blurryWithNoise = blurryNoisyOverlay.composited(over: blurryNoisy).cropped(to: CGRect(origin: .zero, size: size))
    let texture = render { c in                        // a keyboard / fabric: dense fine detail plus noise (the screenshot's scene)
        UIColor(white: 0.5, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: size))
        for y in stride(from: 0, to: 720, by: 9) { for x in stride(from: 0, to: 540, by: 9) {
            c.setFillColor(UIColor(white: 0.25 + 0.5 * rnd(), alpha: 1).cgColor); c.fill(CGRect(x: x, y: y, width: 6, height: 6)) } }
        noise(c, 0.3)
    }
    func lumaOf(_ i: CIImage) -> CIImage { i.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0]) }
    func coverage(_ mask: CIImage) -> Double {          // share of pixels the overlay turns visibly red
        let box = CGRect(origin: .zero, size: size)
        let w = Int(box.width), h = Int(box.height)
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: box)
        let out = mask.composited(over: black).cropped(to: box)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(out, toBitmap: &px, rowBytes: w * 4, bounds: box, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var n = 0
        for i in stride(from: 0, to: px.count, by: 4) where Int(px[i]) - Int(px[i + 1]) > 60 { n += 1 }
        return Double(n) / Double(w * h)
    }
    func oldMask(_ luma: CIImage) -> CIImage {
        let edges = luma.applyingFilter("CIConvolution3X3", parameters: ["inputWeights": CIVector(values: [-1, -1, -1, -1, 8, -1, -1, -1, -1], count: 9), "inputBias": 0.0])
        return edges.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 9, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 1, y: 0.15, z: 0.1, w: -0.9)]).applyingFilter("CIColorClamp")
    }
    func save(_ img: CIImage, over base: CIImage, _ name: String) {
        let out = img.composited(over: base).cropped(to: base.extent)
        if let d = ctx.pngRepresentation(of: out, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) { try? d.write(to: docs.appendingPathComponent(name)) }
    }
    for (name, img) in [("sharp scene", sharp), ("blurry + noisy", blurryWithNoise), ("dense texture + noise", texture)] as [(String, CIImage)] {
        let l = lumaOf(img)
        let o = oldMask(l), n = CameraEngine.peakingMask(l)
        lines.append("\(name): old peaking paints \(String(format: "%.1f", coverage(o) * 100))% of the picture, new paints \(String(format: "%.1f", coverage(n) * 100))%")
        let tag = name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "+", with: "and")
        save(o, over: img, "peak_old_\(tag).png"); save(n, over: img, "peak_new_\(tag).png")
    }
    try? lines.joined(separator: "\n").write(to: docs.appendingPathComponent("peak_report.txt"), atomically: true, encoding: .utf8)
}

/// Simulator-only: a city-glow sky with stars, run through the real star processing at each sky-darkness level.
private func runStarToneTest() {
    var lines: [String] = []
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let ctx = CIContext()
    var seed: UInt64 = 424242
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10_000) / 10_000 }
    let size = CGSize(width: 1200, height: 1600)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { r in
        let c = r.cgContext
        // dim orange city glow, brighter near the horizon (bottom), plus sensor noise
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 1).cgColor, UIColor(red: 0.30, green: 0.20, blue: 0.14, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(glow, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        for _ in 0..<60_000 { c.setFillColor(UIColor(white: rnd(), alpha: 0.05).cgColor); c.fill(CGRect(x: rnd() * size.width, y: rnd() * size.height, width: 2, height: 2)) }
        for _ in 0..<420 {
            let b = 0.45 + 0.55 * rnd() * rnd(), d = 2 + 3.5 * b
            c.setFillColor(UIColor(white: b, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: rnd() * size.width, y: rnd() * size.height * 0.85, width: d, height: d))
        }
    }
    guard let input = CIImage(image: image) else { return }
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    func value(_ img: CIImage, _ filter: String) -> Double {
        let r = img.applyingFilter(filter, parameters: [kCIInputExtentKey: CIVector(cgRect: img.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(r, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: srgb)
        return Double(max(px[0], px[1], px[2])) / 255
    }
    func stats(_ img: CIImage) -> (mean: Double, peak: Double, bright: Double) {
        // fraction of pixels brighter than 0.25 (as seen on screen): the stars (and any glow)
        let marked = img.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 80, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 80, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 80, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputBiasVector": CIVector(x: -20, y: -20, z: -20, w: 0)])
        let avg = img.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: img.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: srgb)
        return ((Double(px[0]) + Double(px[1]) + Double(px[2])) / 3 / 255, value(img, "CIAreaMaximum"), value(marked, "CIAreaAverage"))
    }
    func save(_ img: CIImage, _ name: String) { if let d = ctx.pngRepresentation(of: img, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) { try? d.write(to: docs.appendingPathComponent(name)) } }
    let before = stats(input)
    lines.append("original: average brightness \(String(format: "%.3f", before.mean)), brightest \(String(format: "%.2f", before.peak)), star-bright area \(String(format: "%.4f", before.bright))")
    save(input, "star_0_original.png")
    for (name, d) in [("natural", 0.0), ("dark", 0.6), ("black", 1.0)] as [(String, Float)] {
        let out = CameraEngine.starTone(input, darkness: d, trails: false)
        let st = stats(out)
        lines.append("\(name): average brightness \(String(format: "%.3f", st.mean)), brightest \(String(format: "%.2f", st.peak)), star-bright area \(String(format: "%.4f", st.bright))")
        save(out, "star_\(name).png")
    }
    try? lines.joined(separator: "\n").write(to: docs.appendingPathComponent("star_report.txt"), atomically: true, encoding: .utf8)
}

/// Simulator-only: checks the astronomy and the sensor → camera projection against known sky geometry, and draws a test picture.
private func runSkySelfTest() {
    var lines: [String] = [], fails = 0
    func check(_ ok: Bool, _ text: String) { if !ok { fails += 1; lines.append("FAIL " + text) } }
    // Catalogue integrity
    let ids = SkyCatalog.stars.map { $0.id }
    check(Set(ids).count == ids.count, "duplicate star ids")
    for c in SkyCatalog.constellations { for (a, b) in c.lines { check(ids.contains(a) && ids.contains(b), "\(c.name): unknown star \(a) / \(b)") } }
    // A star on the meridian is due south, at altitude 90° − latitude + declination
    if let bet = SkyCatalog.stars.first(where: { $0.id == "ori_bet" }) {
        let r = SkyMath.altAz(raHours: bet.ra, decDeg: bet.dec, latDeg: 40, lstDeg: bet.ra * 15)
        check(abs(abs(r.az) - .pi) < 0.01, "meridian star should be due south, got \(r.az * 180 / .pi)°")
        check(abs(r.alt * 180 / .pi - (90 - 40 + bet.dec)) < 0.01, "meridian altitude wrong: \(r.alt * 180 / .pi)°")
    }
    // Polaris stays at about your latitude, due north
    if let pol = SkyCatalog.stars.first(where: { $0.id == "umi_pol" }) {
        for hour in stride(from: 0.0, to: 24.0, by: 3.0) {
            let r = SkyMath.altAz(raHours: pol.ra, decDeg: pol.dec, latDeg: 40.7, lstDeg: hour * 15)
            check(abs(r.alt * 180 / .pi - 40.7) < 1.0, "Polaris altitude at LST \(hour)h: \(r.alt * 180 / .pi)°")
        }
    }
    // Projection: phone upright facing north, with CoreMotion's matrix read either way round
    let facingNorth = CMRotationMatrix(m11: 0, m12: -1, m13: 0, m21: 0, m22: 0, m23: 1, m31: -1, m32: 0, m33: 0)
    let transposed = CMRotationMatrix(m11: 0, m12: 0, m13: -1, m21: -1, m22: 0, m23: 0, m31: 0, m32: 1, m33: 0)
    for (name, m) in [("matrix as ref→device", facingNorth), ("matrix as device→ref", transposed)] {
        let up = (0.0, -1.0, 0.0)          // gravity as the phone measures it when upright
        let g = (0.0, -1.0, 0.0)
        _ = up
        func device(_ az: Double, _ alt: Double) -> (Double, Double, Double) {
            // the reading of the matrix is auto-detected from gravity, so the true-gravity vector must agree with the chosen convention
            let ref = (cos(alt) * cos(az), -cos(alt) * sin(az), sin(alt))
            return SkyTracker.toDevice(ref, r: m, gravity: g)
        }
        let straight = device(0, 0), east = device(20 * .pi / 180, 0), high = device(0, 20 * .pi / 180)
        check(straight.2 < -0.99, "\(name): north on the horizon should be straight ahead, got \(straight)")
        check(east.0 > 0.3 && east.2 < 0, "\(name): a star 20° east of north should be on the right, got \(east)")
        check(high.1 > 0.3 && high.2 < 0, "\(name): a star 20° up should be above centre, got \(high)")
    }
    // A real sky: New York, 22:00 on 15 January, phone tilted up 45° facing south — Orion should be in view,
    // with Betelgeuse upper-left of Rigel (east is on the left when facing south).
    let alpha = 45.0 * .pi / 180
    let rot = CMRotationMatrix(m11: 0, m12: 1, m13: 0, m21: sin(alpha), m22: 0, m23: cos(alpha), m31: cos(alpha), m32: 0, m33: -sin(alpha))
    let gravity = (0.0, -cos(alpha), sin(alpha))
    var comps = DateComponents(); comps.year = 2026; comps.month = 1; comps.day = 15; comps.hour = 3; comps.timeZone = TimeZone(identifier: "UTC")
    let date = Calendar(identifier: .gregorian).date(from: comps)!
    let frame = SkyTracker.project(date: date, latitude: 40.7, longitude: -74.0, rotation: rot, gravity: gravity, fovDegrees: 69, offset: .zero)
    check(frame.labels.contains { $0.text == "Orion" }, "Orion should be in view; labels: \(frame.labels.map { $0.text })")
    let bet = frame.dots.first { $0.name == "Betelgeuse" }?.p, rig = frame.dots.first { $0.name == "Rigel" }?.p
    if let bet, let rig {
        check(bet.x < rig.x, "Betelgeuse should be left of Rigel (facing south), got \(bet) vs \(rig)")
        check(bet.y < rig.y, "Betelgeuse should be above Rigel, got \(bet) vs \(rig)")
    } else { check(false, "Betelgeuse / Rigel not visible") }
    lines.append("visible stars \(frame.dots.count), segments \(frame.segments.count), labels \(frame.labels.map { $0.text }.joined(separator: ", "))")
    // Draw it
    let size = CGSize(width: 900, height: 1200)
    if let overlay = SkyRender.overlayImage(frame: frame, size: size) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let composite = UIGraphicsImageRenderer(size: size, format: format).image { r in
            UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1).setFill(); r.fill(CGRect(origin: .zero, size: size))
            overlay.draw(at: .zero)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? composite.pngData()?.write(to: docs.appendingPathComponent("sky_test.png"))
    }
    lines.insert("sky checks: failures \(fails)", at: 0)
    if fails == 0 { lines.append("ALL SKY CHECKS PASSED") }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? lines.joined(separator: "\n").write(to: docs.appendingPathComponent("sky_report.txt"), atomically: true, encoding: .utf8)
}

/// Simulator-only: splits a synthetic scene into overlapping, jittered frames, stitches them back with the real stitcher and measures the error.
private func runPanoSelfTest() {
    var lines: [String] = []
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let ctx = CIContext()
    var seed: UInt64 = 987654321
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10_000) / 10_000 }
    let size = CGSize(width: 5200, height: 1500)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { r in
        let c = r.cgContext
        let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1).cgColor, UIColor(red: 0.95, green: 0.8, blue: 0.6, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(sky, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        for _ in 0..<1100 {
            c.setFillColor(UIColor(hue: rnd(), saturation: 0.3 + rnd() * 0.7, brightness: 0.3 + rnd() * 0.7, alpha: 0.85).cgColor)
            let d = 18 + rnd() * 130, x = rnd() * size.width, y = rnd() * size.height
            if rnd() > 0.5 { c.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d)) } else { c.fill(CGRect(x: x, y: y, width: d, height: d * (0.4 + rnd()))) }
        }
        c.setLineWidth(3)
        for _ in 0..<320 {
            c.setStrokeColor(UIColor(white: rnd(), alpha: 0.8).cgColor)
            c.move(to: CGPoint(x: rnd() * size.width, y: rnd() * size.height)); c.addLine(to: CGPoint(x: rnd() * size.width, y: rnd() * size.height)); c.strokePath()
        }
    }
    guard let scene = CIImage(image: image) else { return }
    let W: CGFloat = 1500, H: CGFloat = 1200
    let X: [CGFloat] = [0, 700, 1380, 2100, 2780]
    let Y: [CGFloat] = [100, 112, 95, 108, 122]
    let frames: [CIImage] = (0..<X.count).map { i in
        scene.cropped(to: CGRect(x: X[i], y: Y[i], width: W, height: H)).transformed(by: CGAffineTransform(translationX: -X[i], y: -Y[i]))
    }
    let exact: [CGPoint] = (1..<X.count).map { CGPoint(x: (X[$0] - X[$0 - 1]) / W, y: (Y[$0] - Y[$0 - 1]) / H) }
    let noisy: [CGPoint] = exact.map { CGPoint(x: $0.x + (rnd() - 0.5) * 0.04, y: $0.y + (rnd() - 0.5) * 0.04) }   // ±2 % error, like a rough live estimate
    let bottom = Y.max()! , top = Y.min()! + H
    let truth = scene.cropped(to: CGRect(x: X[0], y: bottom, width: X.last! + W - X[0], height: top - bottom))
        .transformed(by: CGAffineTransform(translationX: -X[0], y: -bottom))
    func mad(_ a: CIImage, _ b: CIImage) -> Double {
        let rect = a.extent.intersection(b.extent)
        let d = a.cropped(to: rect).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: b.cropped(to: rect)])
        let avg = d.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return (Double(px[0]) + Double(px[1]) + Double(px[2])) / 3 / 255
    }
    func save(_ img: CIImage, _ name: String) {
        if let data = ctx.pngRepresentation(of: img, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) { try? data.write(to: docs.appendingPathComponent(name)) }
    }
    lines.append("truth size \(Int(truth.extent.width))x\(Int(truth.extent.height))")
    save(truth, "pano_truth.png")
    for (name, predicted) in [("A_exact_prediction", Optional(exact)), ("B_noisy_prediction", Optional(noisy)), ("C_no_prediction", nil)] as [(String, [CGPoint]?)] {
        guard let result = CameraEngine.stitchCore(frames, predicted: predicted) else { lines.append("\(name): FAILED (nil)"); continue }
        lines.append("\(name): size \(Int(result.extent.width))x\(Int(result.extent.height))  mean error \(String(format: "%.4f", mad(result, truth)))  (0 = identical)")
        save(result, "pano_\(name).png")
    }
    // Simulated live sweeps: same tracker as the app (small frame-to-frame steps, summed), key frame every 0.4 of a frame.
    for stepPx in [100, 180, 300] as [CGFloat] {
        var xs: [CGFloat] = [], x: CGFloat = 0
        while x + W <= size.width - 10 { xs.append(x); x += stepPx }
        let ys: [CGFloat] = xs.indices.map { 100 + CGFloat((($0 * 7) % 13)) - 6 }       // hand-shake wobble of ±6 px
        let smallW: CGFloat = 320, k = smallW / W
        func small(_ i: Int) -> CGImage? {
            let f = scene.cropped(to: CGRect(x: xs[i], y: ys[i], width: W, height: H)).transformed(by: CGAffineTransform(translationX: -xs[i], y: -ys[i])).transformed(by: CGAffineTransform(scaleX: k, y: k))
            return ctx.createCGImage(f, from: f.extent)
        }
        var keys: [Int] = [0], shifts: [CGPoint] = [], accum = CGPoint.zero
        var prev = small(0)
        var totalTracked: CGFloat = 0
        for i in 1..<xs.count {
            guard let cur = small(i), let p = prev, let step = CameraEngine.estimateStep(p, cur) else { prev = small(i); continue }
            prev = cur
            accum = CGPoint(x: accum.x + step.x, y: accum.y + step.y)
            totalTracked += step.x
            if abs(accum.x) >= 0.4 * smallW {
                keys.append(i); shifts.append(CGPoint(x: accum.x / smallW, y: accum.y / (H * k))); accum = .zero
            }
        }
        let trueTotal = (xs.last! - xs[0]) * k
        lines.append("sweep step \(Int(stepPx))px (\(Int(stepPx / W * 100))% of a frame): \(xs.count) frames, \(keys.count) key frames, tracked \(Int(totalTracked)) vs true \(Int(trueTotal)) px (small units)")
        let kf: [CIImage] = keys.map { i in scene.cropped(to: CGRect(x: xs[i], y: ys[i], width: W, height: H)).transformed(by: CGAffineTransform(translationX: -xs[i], y: -ys[i])) }
        let kx = keys.map { xs[$0] }, ky = keys.map { ys[$0] }
        let tb = ky.max()!, tt = ky.min()! + H
        let tr = scene.cropped(to: CGRect(x: kx[0], y: tb, width: kx.last! + W - kx[0], height: tt - tb)).transformed(by: CGAffineTransform(translationX: -kx[0], y: -tb))
        if let result = CameraEngine.stitchCore(kf, predicted: shifts) {
            lines.append("    stitched \(Int(result.extent.width))x\(Int(result.extent.height)) vs truth \(Int(tr.extent.width))x\(Int(tr.extent.height)), mean error \(String(format: "%.4f", mad(result, tr)))")
            save(result, "pano_sweep\(Int(stepPx)).png")
        } else { lines.append("    stitch FAILED") }
    }
    try? lines.joined(separator: "\n").write(to: docs.appendingPathComponent("pano_report.txt"), atomically: true, encoding: .utf8)
}
#endif

// MARK: - Photos → PDF

/// Memory-friendly load: decodes straight to a downsampled image.
private func downsampleImage(_ url: URL, maxPixel: CGFloat) -> UIImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                 kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    return UIImage(cgImage: cg)
}

/// System photo picker: runs out of process, so the app needs no photo-library permission.
private struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: ([UIImage]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration()
        cfg.filter = .images; cfg.selectionLimit = 0; cfg.selection = .ordered
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([UIImage]) -> Void
        init(onPick: @escaping ([UIImage]) -> Void) { self.onPick = onPick }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            var out = [UIImage?](repeating: nil, count: results.count)
            let lock = NSLock(), group = DispatchGroup()
            for (i, r) in results.enumerated() {
                group.enter()
                r.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                    if let url, let img = downsampleImage(url, maxPixel: 2400) { lock.lock(); out[i] = img; lock.unlock() }
                    group.leave()
                }
            }
            group.notify(queue: .main) { self.onPick(out.compactMap { $0 }) }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

private enum PDFBuilder {
    private static func scaled(_ img: UIImage, _ maxSide: CGFloat) -> UIImage {
        let m = max(img.size.width, img.size.height)
        guard m > maxSide else { return img }
        let k = maxSide / m, size = CGSize(width: img.size.width * k, height: img.size.height * k)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        let k = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * k, h = size.height * k
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
    /// pageMode: 0 A4, 1 square, 2 fit-to-image (one photo per page). perPage: 1, 2 or 4.
    /// (columns, rows) for a page holding `n` photos.
    private static func grid(_ n: Int, landscape: Bool) -> (Int, Int) {
        let portrait: (Int, Int)
        switch n { case 1: portrait = (1, 1); case 2: portrait = (1, 2); case 4: portrait = (2, 2); case 6: portrait = (2, 3)
                   case 9: portrait = (3, 3); case 12: portrait = (3, 4); default: portrait = (4, 4) }
        return landscape ? (portrait.1, portrait.0) : portrait
    }
    static func build(images: [UIImage], perPage: Int, pageMode: Int, highQuality: Bool, title: String, landscape: Bool = false) -> URL? {
        guard !images.isEmpty else { return nil }
        let prepared: [UIImage] = images.compactMap { img in
            scaled(img, highQuality ? 2400 : 1400).jpegData(compressionQuality: highQuality ? 0.85 : 0.6).flatMap(UIImage.init(data:))
        }
        let fit = pageMode == 2 && perPage == 1
        let pageSize = pageMode == 1 ? CGSize(width: 612, height: 612) : landscape ? CGSize(width: 841.89, height: 595.28) : CGSize(width: 595.28, height: 841.89)
        let margin: CGFloat = perPage >= 9 ? 20 : 28, gap: CGFloat = perPage >= 9 ? 8 : 14
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Photos-\(Int(Date().timeIntervalSince1970)).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        do {
            try renderer.writePDF(to: url) { ctx in
                var index = 0, first = true
                while index < prepared.count {
                    if fit {
                        let img = prepared[index]
                        let k = min(1, 842 / max(img.size.width, img.size.height))
                        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
                        ctx.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                        img.draw(in: CGRect(origin: .zero, size: size))
                        index += 1
                        continue
                    }
                    ctx.beginPage()
                    var top = margin
                    if first, !title.isEmpty {
                        (title as NSString).draw(in: CGRect(x: margin, y: margin, width: pageSize.width - 2 * margin, height: 34),
                                                 withAttributes: [.font: UIFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: UIColor.black])
                        top += 48
                    }
                    first = false
                    let area = CGRect(x: margin, y: top, width: pageSize.width - 2 * margin, height: pageSize.height - top - margin)
                    let (cols, rows) = grid(perPage, landscape: landscape && pageMode != 1)
                    let slotW = (area.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
                    let slotH = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
                    for slot in 0..<perPage where index < prepared.count {
                        let r = slot / cols, c = slot % cols
                        let slotRect = CGRect(x: area.minX + CGFloat(c) * (slotW + gap), y: area.minY + CGFloat(r) * (slotH + gap), width: slotW, height: slotH)
                        let img = prepared[index]
                        img.draw(in: aspectFit(img.size, in: slotRect))
                        index += 1
                    }
                }
            }
        } catch { return nil }
        return url
    }
}

private struct PDFExportView: View {
    let sessionURLs: [URL]
    @Environment(\.dismiss) private var dismiss
    @State private var images: [UIImage] = []
    @State private var perPage = 1
    @State private var pageMode = 0
    @State private var landscape = false
    @State private var highQuality = true
    @State private var title = ""
    @State private var showPicker = false
    @State private var building = false
    @State private var shareURL: URL?
    @State private var showShare = false

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { haptic(.soft); action() } label: {
            Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(on ? Color.black : .white.opacity(0.75))
                .padding(.horizontal, 14).frame(height: 32)
                .background { if on { Capsule().fill(Theme.gold) } else { Capsule().fill(Color.white.opacity(0.1)) } }
        }.buttonStyle(PressStyle())
    }
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(0.9).foregroundStyle(Theme.muted)
            content()
        }
    }
    var body: some View {
        ZStack {
            Theme.backdrop.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Photos → PDF").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36).neuRaisedCircle() }
                        .buttonStyle(PressStyle())
                }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("PHOTOS") {
                            HStack(spacing: 8) {
                                Button { haptic(); images = sessionURLs.compactMap { downsampleImage($0, maxPixel: 2400) } } label: {
                                    Text("THIS SESSION (\(sessionURLs.count))").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                                        .padding(.horizontal, 14).frame(height: 36).neuPill()
                                }.buttonStyle(PressStyle()).disabled(sessionURLs.isEmpty).opacity(sessionURLs.isEmpty ? 0.4 : 1)
                                Button { haptic(); showPicker = true } label: {
                                    Text("PICK FROM PHOTOS").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                                        .padding(.horizontal, 14).frame(height: 36).neuPill()
                                }.buttonStyle(PressStyle())
                            }
                            if images.isEmpty {
                                Text("Use the photos you just shot, or pick any from your library — you can choose several, in the order you tap them.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                                            Image(uiImage: img).resizable().scaledToFill().frame(width: 64, height: 64)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .overlay(alignment: .topTrailing) {
                                                    Button { images.remove(at: i) } label: {
                                                        Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white, .black.opacity(0.7))
                                                    }.offset(x: 5, y: -5)
                                                }
                                        }
                                    }.padding(.top, 6).padding(.trailing, 6)
                                }
                                Text("\(images.count) photo\(images.count == 1 ? "" : "s") · tap ✕ to remove one").font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                        }
                        section("PHOTOS PER PAGE") {
                            Flow(spacing: 8) { ForEach([1, 2, 4, 6, 9, 12, 16], id: \.self) { n in chip("\(n)", on: perPage == n) { perPage = n; if pageMode == 2 { pageMode = 0 } } } }
                            Text("Up to 16 photos on one page — handy for contact sheets and menus.").font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                        section("PAGE") {
                            HStack(spacing: 8) {
                                chip("A4", on: pageMode == 0) { pageMode = 0 }
                                chip("SQUARE", on: pageMode == 1) { pageMode = 1 }
                                chip("FIT TO PHOTO", on: pageMode == 2 && perPage == 1) { pageMode = 2; perPage = 1 }
                            }
                        }
                        if pageMode == 0 {
                            section("A4 ORIENTATION") {
                                HStack(spacing: 8) {
                                    chip("PORTRAIT", on: !landscape) { landscape = false }
                                    chip("LANDSCAPE", on: landscape) { landscape = true }
                                }
                            }
                        }
                        section("FILE SIZE") {
                            HStack(spacing: 8) {
                                chip("SMALL · easy to share", on: !highQuality) { highQuality = false }
                                chip("HIGH QUALITY", on: highQuality) { highQuality = true }
                            }
                        }
                        section("TITLE ON FIRST PAGE (OPTIONAL)") {
                            TextField("e.g. Spring Menu", text: $title)
                                .font(.system(size: 15)).padding(.horizontal, 14).frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                                .foregroundStyle(.white)
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 24)
                }
                Button {
                    haptic(.medium); building = true
                    let snapshot = images, pp = perPage, pm = pageMode, hq = highQuality, t = title, land = landscape
                    DispatchQueue.global(qos: .userInitiated).async {
                        let url = PDFBuilder.build(images: snapshot, perPage: pp, pageMode: pm, highQuality: hq, title: t, landscape: land)
                        DispatchQueue.main.async { building = false; if let url { shareURL = url; showShare = true } }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if building { ProgressView().tint(.black) }
                        Text(building ? "CREATING…" : "CREATE PDF").font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(Theme.gold))
                }
                .buttonStyle(PressStyle()).disabled(images.isEmpty || building).opacity(images.isEmpty ? 0.4 : 1)
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPicker) { PhotoPicker { images += $0 } }
        .sheet(isPresented: $showShare) { if let shareURL { ShareSheet(items: [shareURL]) } }
        .onAppear { if images.isEmpty && !sessionURLs.isEmpty { images = sessionURLs.compactMap { downsampleImage($0, maxPixel: 2400) } } }
    }
}

/// Pop-up shown before Night / Stars start: Auto or a custom time.
private struct NightTimeSheet: View {
    let astro: Bool
    @Binding var seconds: Int
    @Binding var trails: Bool
    @Binding var askEachTime: Bool
    @Binding var skyDark: Int
    var start: () -> Void
    @State private var custom: Bool
    @State private var value: Double
    init(astro: Bool, seconds: Binding<Int>, trails: Binding<Bool>, askEachTime: Binding<Bool>, skyDark: Binding<Int>, start: @escaping () -> Void) {
        self.astro = astro; self._seconds = seconds; self._trails = trails; self._askEachTime = askEachTime; self._skyDark = skyDark; self.start = start
        let quick = astro ? [10, 20, 30, 60, 120] : [0, 5, 10, 20, 30, 60]
        let isCustom = !quick.contains(seconds.wrappedValue)
        _custom = State(initialValue: isCustom)
        _value = State(initialValue: Double(seconds.wrappedValue == 0 ? 30 : seconds.wrappedValue))
    }
    private var quick: [Int] { astro ? [10, 20, 30, 60, 120] : [5, 10, 20, 30, 60] }
    private func label(_ s: Int) -> String { s >= 120 ? "\(s / 60) min" : s >= 60 ? "1 min" : "\(s) s" }
    var body: some View {
        ZStack {
            Theme.backdrop.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text(astro ? "How long should it shoot the sky?" : "How long should Night mode shoot?").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                if !astro {
                    HStack(spacing: 8) {
                        pill("AUTO", on: !custom) { custom = false; seconds = 0 }
                        pill("CUSTOM", on: custom) { custom = true; seconds = Int(value) }
                    }
                    if !custom {
                        Text("Auto takes about 6 quick frames (about 3 seconds) and merges them.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                }
                if astro || custom {
                    Text(label(Int(value))).font(.system(size: 34, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.champagne)
                    Slider(value: Binding(get: { value }, set: { value = ($0 / 5).rounded() * 5; seconds = Int(value) }), in: astro ? 10...600 : 5...180).tint(accent)
                    Flow(spacing: 8) { ForEach(quick, id: \.self) { q in pill(label(q), on: Int(value) == q) { value = Double(q); seconds = q; custom = true } } }
                    Text(astro ? "Longer shows more stars. Use a tripod." : "Longer merges more frames: less noise, brighter shadows. Hold still or use a tripod.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                if astro {
                    HStack(spacing: 8) {
                        pill("STARS", on: !trails) { trails = false }
                        pill("STAR TRAILS", on: trails) { trails = true }
                    }
                    HStack(spacing: 8) {
                        pill("NATURAL SKY", on: skyDark == 0) { skyDark = 0 }
                        pill("DARK SKY", on: skyDark == 1) { skyDark = 1 }
                        pill("BLACK SKY", on: skyDark == 2) { skyDark = 2 }
                    }
                }
                Toggle("Ask me every time", isOn: $askEachTime).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).tint(accent)
                Button { haptic(.medium); start() } label: {
                    Text("START").font(.system(size: 15, weight: .heavy)).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(Theme.gold))
                }.buttonStyle(PressStyle())
            }.padding(22)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.height(astro ? 540 : custom ? 470 : 360)])
        .presentationDragIndicator(.visible)
    }
    private func pill(_ text: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { haptic(.soft); action() } label: {
            Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(on ? Color.black : .white.opacity(0.75))
                .padding(.horizontal, 16).frame(height: 34)
                .background { if on { Capsule().fill(Theme.gold) } else { Capsule().fill(Color.white.opacity(0.1)) } }
        }.buttonStyle(PressStyle())
    }
}

/// Magnified centre crop for manual focusing.
private struct LoupeView: UIViewRepresentable {
    let engine: CameraEngine
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.layer.contentsGravity = .resizeAspectFill
        v.layer.cornerRadius = 14
        v.layer.masksToBounds = true
        v.backgroundColor = .black
        engine.loupeHandler = { [weak v] cg in v?.layer.contents = cg }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let engine: CameraEngine
    /// Changes when the phone is rotated or the session starts, so the preview re-applies its rotation.
    var refreshKey: Int = 0
    var onShutter: () -> Void
    var onFocus: (CGPoint, CGPoint, Bool) -> Void
    var onPinchBegan: () -> Void
    var onPinch: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        engine.displayHandler = { [weak view] image in view?.show(image) }
        engine.overlayHandler = { [weak view] image in view?.showOverlay(image) }
        engine.panoGhostHandler = { [weak view] image, index, dx, dy in view?.showGhost(image, index: index, dx: dx, dy: dy) }
        view.onShutter = { onShutter() }
        view.installVolumeShutter()
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.5
        view.addGestureRecognizer(press)
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))))
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.parent = self
        if uiView.previewLayer.session !== session { uiView.previewLayer.session = session }
        engine.applyOrientation(to: uiView.previewLayer.connection)
    }

    final class Coordinator: NSObject {
        var parent: CameraPreview
        init(_ parent: CameraPreview) { self.parent = parent }
        private func focus(_ g: UIGestureRecognizer, lock: Bool) {
            guard let v = g.view as? PreviewView else { return }
            let p = g.location(in: v)
            parent.onFocus(p, v.previewLayer.captureDevicePointConverted(fromLayerPoint: p), lock)
        }
        @objc func tap(_ g: UITapGestureRecognizer) { focus(g, lock: false) }
        @objc func press(_ g: UILongPressGestureRecognizer) { if g.state == .began { focus(g, lock: true) } }
        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began: parent.onPinchBegan()
            case .changed: parent.onPinch(g.scale)
            default: break
            }
        }
    }
}
private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private let filtered = CALayer()
    private let analysis = CALayer()
    private let ghost = CALayer()
    private var ghostIndex = -1
    func showGhost(_ image: CGImage?, index: Int, dx: CGFloat, dy: CGFloat) {
        guard let image else { ghost.isHidden = true; ghostIndex = -1; return }
        CATransaction.begin(); CATransaction.setAnimationDuration(0.1)
        if index != ghostIndex { ghost.contents = image; ghostIndex = index }
        ghost.isHidden = false
        ghost.frame = bounds.offsetBy(dx: dx * bounds.width, dy: dy * bounds.height)
        CATransaction.commit()
    }
    var onShutter: (() -> Void)?
    func installVolumeShutter() {
        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction { [weak self] event in
                if event.phase == .ended { self?.onShutter?() }
            }
            addInteraction(interaction)
        }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        filtered.contentsGravity = .resizeAspectFill
        filtered.masksToBounds = true
        filtered.isHidden = true
        layer.addSublayer(filtered)
        ghost.contentsGravity = .resizeAspectFill
        ghost.opacity = 0.38
        ghost.isHidden = true
        layer.addSublayer(ghost)
        analysis.contentsGravity = .resizeAspectFill
        analysis.masksToBounds = true
        analysis.isHidden = true
        layer.addSublayer(analysis)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        filtered.frame = bounds
        analysis.frame = bounds
        CATransaction.commit()
    }
    func showOverlay(_ image: CGImage?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        analysis.contents = image
        analysis.isHidden = image == nil
        CATransaction.commit()
    }
    func show(_ image: CGImage?) {
        if image == nil, !filtered.isHidden {
            // Fade the frozen / filtered picture out instead of cutting to the live camera.
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.filtered.opacity == 0 else { return }
                self.filtered.isHidden = true; self.filtered.contents = nil; self.filtered.opacity = 1
            }
            filtered.opacity = 0
            CATransaction.commit()
            return
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        filtered.opacity = 1
        filtered.contents = image
        filtered.isHidden = image == nil
        CATransaction.commit()
    }
}

import AVFoundation
import Photos
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import AVKit
import ImageIO

final class CameraEngine: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let frameQueue = DispatchQueue(label: "camera.frames", qos: .userInteractive)
    /// Look applied to the live preview (frames are filtered with the same pipeline as saved photos).
    var previewLook: Look = .original { didSet { if previewLook == .original { DispatchQueue.main.async { self.displayHandler?(nil) } } } }
    /// Set by the preview view; receives filtered frames (nil = show the raw preview).
    var displayHandler: ((CGImage?) -> Void)?
    /// Focus-peaking / zebra overlay (transparent image), nil = none.
    var overlayHandler: ((CGImage?) -> Void)?
    var peakingEnabled = false
    var zebraEnabled = false
    var histogramEnabled = false
    var lookStrength: Float = 1
    var frameStyle = 0
    var burstEnabled = false
    var portraitBlurAmount: Float = 0.6
    var nightMode = false
    /// SDR / HDR (HLG, Dolby Vision) / LOG (Apple Log) and HEVC / H.264 / PRORES for plain VIDEO mode.
    @Published var videoRange = "SDR"
    @Published var videoCodec = "HEVC"
    @Published var recordingInfo: String?
    private var savedColorSpace: AVCaptureColorSpace?
    // Continuous panorama sweep (like video): key frames are picked automatically as you pan.
    @Published var panoSweeping = false
    @Published var panoStrip: UIImage?
    /// (previous key frame, its index, dx, dy) — drawn translucent over the live view where that frame currently sits.
    var panoGhostHandler: ((CGImage?, Int, CGFloat, CGFloat) -> Void)?
    private var panoKeys: [CGImage] = []
    private var panoPositions: [CGFloat] = []
    private var panoLastKeySmall: CGImage?
    private var panoDirection: CGFloat = 0
    private var panoCounter = 0
    private var panoShifts: [CGPoint] = []
    private var panoPrevSmall: CGImage?
    private var panoAccum = CGPoint.zero      // camera movement since the last key frame, summed from small frame-to-frame steps
    private var panoPredicted: [CGPoint]?
    private var panoRestore = (exp: false, wb: false, focus: false)
    /// True while a video mode is selected: the recording has no look applied, so the preview stays raw (what you see is what is recorded).
    var videoMode = false { didSet { if videoMode { DispatchQueue.main.async { self.displayHandler?(nil) } } } }
    var astroMode = false
    /// Provides the current sky map (set by the view) so it can be drawn onto the finished star photo.
    var skyProvider: (() -> SkyTracker.Frame?)?
    var skyBurn = true
    private var astroSkySnapshot: SkyTracker.Frame?
    /// 0 = default (about 6 quick frames), otherwise keep shooting for this many seconds.
    var nightSeconds = 0
    var astroSeconds = 20
    var astroTrails = false
    /// 0 = natural sky glow … 1 = black sky (the sky glow is measured and removed so stars stand out).
    var astroSkyDarkness: Float = 0.6
    private let nightDefaultFrames = 6
    private var nightCount = 0
    private var nightRef: CIImage?
    private var nightAcc: CIImage?
    private var nightStart = Date()
    private var nightStopRequested = false
    /// 0 fast, 1 balanced, 2 best (maps to the camera's photo quality prioritisation)
    var qualityPriority = 1
    @Published var isSaving = false
    private var saveToken = 0
    private var pauseFramesUntil = Date.distantPast
    private var finishing = 0       // photos currently being processed
    // Lens-switch crossfade: freeze the current picture on screen while the camera input swaps, then fade it out.
    private var snapshotRequested = false
    private var snapshotWork: (() -> Void)?
    private var clearOverlayAfterSwap = false
    private var swapFrameMark = 0
    private var currentLens: Lens = .wide
    private let finishQueue = DispatchQueue(label: "camera.finish", qos: .userInitiated)
    @Published var sessionCount = 0
    private var sessionShots: [URL] = []
    func sessionShotURLs() -> [URL] { sessionShots }
    func clearSession() {
        sessionShots.forEach { try? FileManager.default.removeItem(at: $0) }
        sessionShots = []; sessionCount = 0
    }
    /// Histogram data lives in its own object so ~10 updates/second redraw only the histogram, not the whole screen.
    let hist = HistogramModel()
    var isForeground = true
    /// How the phone is physically held (the screen stays portrait, like the system camera when rotation is locked).
    private(set) var lastDeviceOrientation: UIDeviceOrientation = .portrait
    /// 0 portrait, 1 landscape (home button right), 2 landscape (home button left), 3 upside down
    @Published var orientationCode = 0
    private(set) var thermalLevel = 0
    private var previewMaxWidth: CGFloat { thermalLevel >= 1 ? 600 : 900 }
    @Published var suggestedLook: String?
    var suggestionsEnabled = true { didSet { if !suggestionsEnabled { DispatchQueue.main.async { self.suggestedLook = nil } } } }
    private var lastSuggestTime = Date.distantPast
    private var wbPickPoint: CGPoint?
    /// While true the preview shows the untouched camera image (hold-to-compare).
    var compareRaw = false { didSet { if compareRaw { DispatchQueue.main.async { self.displayHandler?(nil) } } } }
    func setLookExtras(grain: Float, glow: Float, leak: Int, dust: Float) {
        LookProcessor.extraGrain = grain; LookProcessor.extraHalation = glow
        LookProcessor.extraLeak = leak; LookProcessor.extraDust = dust
        if !LookProcessor.hasExtras && previewLook == .original { DispatchQueue.main.async { self.displayHandler?(nil) } }
    }
    /// Tap on a grey / white object: the next frame is sampled and white balance is set so that spot turns neutral.
    func pickWhiteBalance(devicePoint: CGPoint) { wbPickPoint = devicePoint }
    var hdrMerge = false
    private var hdrFrames: [CIImage] = []
    private var hdrCollecting = false
    private let hdrTarget = 3
    var trailAverage = false
    var loupeHandler: ((CGImage?) -> Void)?
    var magnifierEnabled = false { didSet { if !magnifierEnabled { DispatchQueue.main.async { self.loupeHandler?(nil) } } } }
    @Published var aeLocked = false
    @Published var afLocked = false
    @Published var isInterval = false
    @Published var intervalShot = 0
    var intervalSeconds = 5
    var intervalCount = 25
    private var intervalTimer: Timer?
    private var thumbCompletion: (([String: UIImage]) -> Void)?
    /// Next live frame is turned into a thumbnail of every look and handed back on the main queue.
    func requestLookThumbnails(_ completion: @escaping ([String: UIImage]) -> Void) { thumbCompletion = completion }
    @Published var nightBusy = false
    private var nightSavedBias: Float = 0
    @Published var isTrailing = false
    @Published var trailElapsed = 0
    var trailDuration = 10
    private var trailAccum: CIImage?
    private var trailActive = false
    private var trailCounter = 0
    private var trailTimer: Timer?
    private var trailSavedBias: Float = 0
    private var frameInfoText = ""
    private var frameCounter = 0
    @Published var tint: Float = 0
    @Published var isFront = false
    private var device: AVCaptureDevice?
    private var cameraInput: AVCaptureDeviceInput?
    private var wideCamera: AVCaptureDevice?
    private var physicalWideCamera: AVCaptureDevice?
    private var ultraWideCamera: AVCaptureDevice?
    private var dualWideCamera: AVCaptureDevice?
    private var telephotoCamera: AVCaptureDevice?
    /// Telephoto zoom relative to the main lens (e.g. 5 on Pro Max, 3 on Pro).
    private var teleRatio: CGFloat = 3
    private var zoomSwitching = false
    private var pendingZoom: CGFloat?
    private var prefers48 = false
    @Published var lensButtons: [Double] = [0.5, 1, 2, 3]
    private let queue = DispatchQueue(label: "camera.session")
    @Published var authorized = false
    @Published var running = false
    @Published var iso: Float = 100
    @Published var shutter: Double = 1.0 / 120
    @Published var exposureBias: Float = 0
    @Published var focus: Float = 0.5
    @Published var temperature: Float = 5200
    @Published var zoom: CGFloat = 1
    @Published var message: String?
    @Published var captured = false
    @Published var supportsRAW = false
    @Published var rawEnabled = false
    @Published var flashMode = "AUTO"
    @Published var flashAvailable = false
    @Published var isRecording = false
    @Published var slowMotionSupported = false
    @Published var panoramaShotCount = 0
    @Published var timestampEnabled = false
    @Published var supportsPortrait = false
    @Published var supportsMacro = false
    @Published var supportsCinematic = false
    @Published var autoExposure = true
    @Published var autoFocus = true
    @Published var autoWB = true
    private var meterTimer: Timer?
    var meteringEnabled = true
    @Published var lastThumbnail: UIImage?
    @Published var torchOn = false
    @Published var has48MP = false
    @Published var photoResolutionMP = 12
    @Published var photoFormat = "HEIF"
    @Published var videoResolution = "4K UHD"
    @Published var videoFPS = 30
    @Published var slowMotionFPS = 120
    @Published var supportedVideoResolutions: [String] = ["4K UHD", "HD"]
    @Published var supportedFrameRates: [Int] = [24, 30, 60]
    @Published var supportedCinematicFrameRates: [Int] = [24, 30]
    @Published var supportedSlowMotionRates: [Int] = [120, 240]
    var selectedLook = "ORIGINAL"
    var selectedAspect: CGFloat = 4.0 / 3.0
    var slowMotionMode = false
    var timeLapseMode = false
    var portraitMode = false
    var cinematicMode = false
    private var activeVideoFPS = 30
    var panoramaMode = false
    private var panoramaFrames: [CIImage] = []
    @Published private(set) var panoramaProcessing = false
    private var photoVideoFormat: AVCaptureDevice.Format?
    private var preVideoCameraInput: AVCaptureDeviceInput?
    private var preVideoCamera: AVCaptureDevice?
    private var fullPhotoDimensions: CMVideoDimensions?
    private var twelveMPDimensions: CMVideoDimensions?

    /// The live-frame stream (looks, peaking, histogram…) is detached while recording, so slow-motion / 4K video never competes with it.
    private func setFrameOutput(_ on: Bool) {
        if on {
            if !session.outputs.contains(videoDataOutput), session.canAddOutput(videoDataOutput) { session.addOutput(videoDataOutput) }
        } else if session.outputs.contains(videoDataOutput) {
            session.removeOutput(videoDataOutput)
        }
    }
    private func updateOrientation() {
        let o = UIDevice.current.orientation
        guard o == .portrait || o == .portraitUpsideDown || o == .landscapeLeft || o == .landscapeRight, o != lastDeviceOrientation else { return }
        lastDeviceOrientation = o
        orientationCode = o == .landscapeLeft ? 1 : o == .landscapeRight ? 2 : o == .portraitUpsideDown ? 3 : 0
    }
    /// Rotates a capture / preview / movie connection to match how the phone is held.
    func applyOrientation(to connection: AVCaptureConnection?) {
        guard let c = connection else { return }
        let o = lastDeviceOrientation
        if #available(iOS 17.0, *) {
            let angle: CGFloat = o == .landscapeLeft ? 0 : o == .landscapeRight ? 180 : o == .portraitUpsideDown ? 270 : 90
            if c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }
        } else {
            let vo: AVCaptureVideoOrientation = o == .landscapeLeft ? .landscapeRight : o == .landscapeRight ? .landscapeLeft : o == .portraitUpsideDown ? .portraitUpsideDown : .portrait
            if c.isVideoOrientationSupported { c.videoOrientation = vo }
        }
    }
    /// Orientation that makes a raw camera frame upright for the way the phone is held.
    func frameOrientation() -> CGImagePropertyOrientation {
        switch lastDeviceOrientation {
        case .landscapeLeft: return isFront ? .upMirrored : .up
        case .landscapeRight: return isFront ? .downMirrored : .down
        case .portraitUpsideDown: return isFront ? .rightMirrored : .left
        default: return isFront ? .leftMirrored : .right
        }
    }
    private func updateThermal() {
        let level: Int
        switch ProcessInfo.processInfo.thermalState { case .serious: level = 1; case .critical: level = 2; default: level = 0 }
        guard level != thermalLevel else { return }
        thermalLevel = level
        if level >= 1 { DispatchQueue.main.async { self.message = level == 1 ? "Phone is warm — live effects reduced" : "Phone is hot — live effects paused" } }
    }
    private func startHousekeeping() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("session"))
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        updateOrientation()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateOrientation() }
        updateThermal()
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateThermal() }
    }
    func start() {
        startHousekeeping()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async { self?.authorized = ok }
                if ok { self?.configureAndRun() }
            }
        default: DispatchQueue.main.async { self.message = "Enable camera access in Settings" }
        }
    }

    private func configureAndRun() {
        queue.async {
            guard !self.session.isRunning else { return }
            self.session.beginConfiguration(); self.session.sessionPreset = .photo
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera), self.session.canAddInput(input) else { self.session.commitConfiguration(); return }
            self.device = camera; self.cameraInput = input; self.wideCamera = camera
            self.physicalWideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            self.ultraWideCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            self.dualWideCamera = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            self.telephotoCamera = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
            if self.telephotoCamera != nil, let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
                let f = triple.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
                if f.count >= 2, f[0] > 0 { self.teleRatio = max(2, (f[1] / f[0]).rounded()) }
            }
            var buttons: [Double] = []
            if self.ultraWideCamera != nil { buttons.append(0.5) }
            buttons += [1, 2]
            if self.telephotoCamera != nil { buttons.append(Double(self.teleRatio)) }
            DispatchQueue.main.async { self.lensButtons = buttons }
            self.session.addInput(input)
            if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
            if self.session.canAddOutput(self.movieOutput) { self.session.addOutput(self.movieOutput) }
            if self.session.canAddOutput(self.metadataOutput) { self.session.addOutput(self.metadataOutput) }
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.videoDataOutput.setSampleBufferDelegate(self, queue: self.frameQueue)
            if self.session.canAddOutput(self.videoDataOutput) { self.session.addOutput(self.videoDataOutput) }
            self.photoOutput.maxPhotoQualityPrioritization = .quality
            if #available(iOS 17.0, *) {
                self.photoOutput.isResponsiveCaptureEnabled = self.photoOutput.isResponsiveCaptureSupported
                self.photoOutput.isZeroShutterLagEnabled = self.photoOutput.isZeroShutterLagSupported
                self.photoOutput.isFastCapturePrioritizationEnabled = self.photoOutput.isFastCapturePrioritizationSupported
            }
            self.session.commitConfiguration()
            self.selectHighResFormat(on: camera)
            self.refreshPhotoDimensions(camera)
            self.photoOutput.isAppleProRAWEnabled = self.photoOutput.isAppleProRAWSupported
            let codecs = self.photoOutput.availablePhotoCodecTypes
            let formats = camera.formats
            let has48 = (self.physicalWideCamera?.formats ?? formats).contains { f in
                f.supportedMaxPhotoDimensions.contains { Int64($0.width) * Int64($0.height) >= 40_000_000 }
            }
            DispatchQueue.main.async {
                self.supportsRAW = self.photoOutput.isAppleProRAWSupported || !self.photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
                self.flashAvailable = self.photoOutput.supportedFlashModes.contains(.on) || self.photoOutput.supportedFlashModes.contains(.auto)
                self.supportsPortrait = true
                self.supportsMacro = self.ultraWideCamera != nil
                self.has48MP = has48
                self.photoResolutionMP = 12
                self.photoFormat = codecs.contains(.hevc) ? "HEIF" : "JPEG"
                self.slowMotionSupported = (self.physicalWideCamera?.formats ?? formats).contains { f in f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 120 } }
                if #available(iOS 26.0, *) { self.supportsCinematic = (self.dualWideCamera?.formats ?? formats).contains { $0.isCinematicVideoCaptureSupported } }
                let wideResolutions = formats.map { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width }
                self.supportedVideoResolutions = (wideResolutions.contains(where: { $0 >= 7680 }) ? ["8K"] : [])
                    + (wideResolutions.contains(where: { $0 >= 3840 && $0 < 7680 }) ? ["4K UHD"] : [])
                    + (wideResolutions.contains(where: { $0 >= 1920 && $0 < 3840 }) ? ["HD"] : [])
                    + (wideResolutions.contains(where: { $0 >= 1280 && $0 < 1920 }) ? ["720p"] : [])
                if self.supportedVideoResolutions.isEmpty { self.supportedVideoResolutions = ["HD"] }
                self.supportedFrameRates = [24, 25, 30, 60].filter { fps in formats.contains { f in f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= Double(fps) && $0.maxFrameRate >= Double(fps) } } }
                let cinematicFormats = self.dualWideCamera?.formats ?? []
                self.supportedCinematicFrameRates = [24, 25, 30].filter { fps in cinematicFormats.contains { f in f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= Double(fps) && $0.maxFrameRate >= Double(fps) } } }
                self.supportedSlowMotionRates = [120, 240].filter { fps in formats.contains { f in f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(fps) } } }
            }
            self.session.startRunning()
            self.startMetering()
            DispatchQueue.main.async { self.authorized = true; self.running = true }
        }
    }

    func setISO(_ value: Float) { iso = value; autoExposure = false; aeLocked = false; applyExposure() }
    func setShutter(_ value: Double) { shutter = value; autoExposure = false; aeLocked = false; applyExposure() }
    func setBias(_ value: Float) {
        if autoExposure { setAutoBias(value) } else { exposureBias = value; applyExposure() }
    }
    private func applyExposure() {
        guard let d = device, d.isExposureModeSupported(.custom) else { return }
        let f = d.activeFormat
        let seconds = shutter * pow(2.0, Double(exposureBias))
        let lo = max(f.minExposureDuration.seconds, 1.0 / 8000), hi = f.maxExposureDuration.seconds
        let duration = CMTime(seconds: min(max(seconds, lo), hi), preferredTimescale: 1_000_000_000)
        let boundedISO = min(max(iso, f.minISO), f.maxISO)
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            d.setExposureModeCustom(duration: duration, iso: boundedISO, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    func setFocus(_ value: Float) {
        focus = value; autoFocus = false; afLocked = false
        guard let d = device, d.isLockingFocusWithCustomLensPositionSupported else { return }
        let v = min(max(value, 0), 1)
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            d.setFocusModeLocked(lensPosition: v, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    /// Mirror the camera's live auto values into the dials so they show real numbers.
    func startMetering() {
        DispatchQueue.main.async {
            self.meterTimer?.invalidate()
            self.meterTimer = Timer.scheduledTimer(withTimeInterval: 0.33, repeats: true) { [weak self] _ in
                guard let self, self.meteringEnabled, self.isForeground, let d = self.device else { return }
                if self.autoExposure {
                    if abs(self.iso - d.iso) > 1 { self.iso = d.iso }
                    let t = d.exposureDuration.seconds
                    if t > 0, abs(self.shutter - t) > t * 0.02 { self.shutter = t }
                }
                if self.autoFocus, abs(self.focus - d.lensPosition) > 0.005 { self.focus = d.lensPosition }
                if self.autoWB {
                    let g = d.deviceWhiteBalanceGains, m = d.maxWhiteBalanceGain
                    if g.redGain >= 1, g.greenGain >= 1, g.blueGain >= 1, g.redGain <= m, g.greenGain <= m, g.blueGain <= m {
                        let tv = d.temperatureAndTintValues(for: g)
                        self.temperature = tv.temperature; self.tint = tv.tint
                    }
                }
            }
        }
    }
    func setWhiteBalance(_ value: Float) { temperature = value; autoWB = false; applyWhiteBalance() }
    func setTint(_ value: Float) { tint = value; autoWB = false; applyWhiteBalance() }
    private func applyWhiteBalance() {
        guard let d = device, d.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
        let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: tint)
        var gains = d.deviceWhiteBalanceGains(for: values)
        let maxGain = d.maxWhiteBalanceGain
        func clamp(_ g: Float) -> Float { min(max(g, 1.0), maxGain) }
        gains.redGain = clamp(gains.redGain)
        gains.greenGain = clamp(gains.greenGain)
        gains.blueGain = clamp(gains.blueGain)
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            d.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    // MARK: Auto modes, tap-to-focus
    func setAuto(_ dial: String) {
        switch dial { case "FOCUS": autoFocus = true; afLocked = false; case "WB": autoWB = true; default: autoExposure = true; aeLocked = false }
        guard let d = device else { return }
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            switch dial {
            case "FOCUS": if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            case "WB": if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { d.whiteBalanceMode = .continuousAutoWhiteBalance }
            default: if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            }
            d.unlockForConfiguration()
        }
    }
    func resetBias() {
        exposureBias = 0
        guard let d = device else { return }
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            d.setExposureTargetBias(0, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    /// Auto exposure compensation (works in auto exposure mode).
    func setAutoBias(_ value: Float) {
        exposureBias = value
        guard let d = device else { return }
        let clamped = min(max(value, d.minExposureTargetBias), d.maxExposureTargetBias)
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            d.setExposureTargetBias(clamped, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    func setAELock(_ on: Bool) {
        aeLocked = on
        guard let d = device else { return }
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            if on { if d.isExposureModeSupported(.locked) { d.exposureMode = .locked } }
            else if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            d.unlockForConfiguration()
        }
        if on { autoExposure = true }
    }
    func setAFLock(_ on: Bool) {
        afLocked = on
        guard let d = device else { return }
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            if on { if d.isFocusModeSupported(.locked) { d.focusMode = .locked } }
            else if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            d.unlockForConfiguration()
        }
        if on { autoFocus = true }
    }
    func focus(atDevicePoint p: CGPoint, lock: Bool) {
        aeLocked = lock; afLocked = lock
        guard let d = device else { return }
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            if d.isFocusPointOfInterestSupported {
                d.focusPointOfInterest = p
                if d.isFocusModeSupported(lock ? .autoFocus : .continuousAutoFocus) { d.focusMode = lock ? .autoFocus : .continuousAutoFocus }
            }
            if d.isExposurePointOfInterestSupported {
                d.exposurePointOfInterest = p
                if lock, d.isExposureModeSupported(.autoExpose) { d.exposureMode = .autoExpose }
                else if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            }
            d.unlockForConfiguration()
        }
    }
    func toggleTorch() {
        guard let d = device, d.hasTorch else { return }
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            let on = d.torchMode != .on
            if on { try? d.setTorchModeOn(level: 1.0) } else { d.torchMode = .off }
            d.unlockForConfiguration()
            DispatchQueue.main.async { self.torchOn = on }
        }
    }
    private func publishThumbnail(_ data: Data) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 160]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return }
        let img = UIImage(cgImage: cg)
        DispatchQueue.main.async { self.lastThumbnail = img }
    }
    private enum Lens { case ultra, wide, tele }
    /// Which real lens serves a displayed zoom (0.5x ultra-wide, 1x main, tele at its true ratio, crops in between).
    private func resolveLens(_ z: CGFloat, sticky: Bool) -> (Lens, AVCaptureDevice?, CGFloat) {
        var lens: Lens
        if z < 0.999, ultraWideCamera != nil { lens = .ultra }
        else if telephotoCamera != nil, z >= teleRatio - 0.001 { lens = .tele }
        else { lens = .wide }
        if sticky {
            // While pinching, stay on the current lens until the zoom is clearly past the boundary.
            if currentLens == .ultra, lens == .wide, z < 1.04 { lens = .ultra }
            if currentLens == .wide, lens == .ultra, z > 0.94 { lens = .wide }
            if currentLens == .wide, lens == .tele, z < teleRatio + 0.06 { lens = .wide }
            if currentLens == .tele, lens == .wide, z > teleRatio - 0.12 { lens = .tele }
        }
        switch lens {
        case .ultra: return (.ultra, ultraWideCamera, max(1, z / 0.5))
        case .tele: return (.tele, telephotoCamera, max(1, z / teleRatio))
        case .wide: return (.wide, physicalWideCamera ?? wideCamera, max(1, z))
        }
    }
    private func displayBase(_ lens: Lens) -> CGFloat { lens == .ultra ? 0.5 : lens == .tele ? teleRatio : 1 }
    private func apply(factor: CGFloat, to d: AVCaptureDevice, lens: Lens) {
        let clamped = min(max(factor, d.minAvailableVideoZoomFactor), d.activeFormat.videoMaxZoomFactor)
        currentLens = lens
        zoom = clamped * displayBase(lens)
        do { try d.lockForConfiguration() } catch { return }
        d.videoZoomFactor = clamped
        d.unlockForConfiguration()
    }
    func setZoom(_ value: CGFloat, sticky: Bool = false) {
        if isFront { if let d = device { apply(factor: max(1, value), to: d, lens: .wide) }; return }
        if zoomSwitching { pendingZoom = value; return }
        let z = max(0.5, value)
        let (lens, target, factor) = resolveLens(z, sticky: sticky)
        guard let target else { return }
        // 48 MP only on the main lens at exactly 1x (like the system camera).
        let want = (prefers48 && has48MP && lens == .wide && factor < 1.05) ? 48 : 12
        if photoResolutionMP != want { photoResolutionMP = want }
        if device === target { apply(factor: factor, to: target, lens: lens) }
        else { switchLens(to: target, lens: lens, factor: factor) }
    }
    private func switchLens(to target: AVCaptureDevice, lens: Lens, factor: CGFloat) {
        zoomSwitching = true
        let swap: () -> Void = { [self] in
            queue.async {
                guard let oldInput = self.cameraInput, !self.isRecording,
                      let newInput = try? AVCaptureDeviceInput(device: target) else {
                    DispatchQueue.main.async { self.zoomSwitching = false; self.displayHandler?(nil) }
                    return
                }
                self.session.beginConfiguration()
                self.session.removeInput(oldInput)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput); self.cameraInput = newInput; self.device = target
                } else { self.session.addInput(oldInput) }
                self.session.commitConfiguration()
                self.selectHighResFormat(on: target)
                self.refreshPhotoDimensions(target)
                self.photoOutput.isAppleProRAWEnabled = self.photoOutput.isAppleProRAWSupported
                let raw = self.photoOutput.isAppleProRAWSupported || !self.photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
                DispatchQueue.main.async {
                    self.autoExposure = true; self.autoFocus = true; self.autoWB = true
                    self.supportsRAW = raw
                    self.apply(factor: factor, to: target, lens: lens)
                    self.swapFrameMark = self.frameCounter
                    self.clearOverlayAfterSwap = true
                    self.zoomSwitching = false
                    if let p = self.pendingZoom { self.pendingZoom = nil; self.setZoom(p, sticky: true) }
                }
            }
        }
        snapshotWork = swap
        snapshotRequested = true
        // If no frame arrives to freeze (session idle), swap anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if self.snapshotRequested { self.snapshotRequested = false; let w = self.snapshotWork; self.snapshotWork = nil; w?() }
        }
    }
    /// Back to defaults: everything automatic, 1x, HEIF 12 MP, flash auto, torch off.
    func resetCamera() {
        setAuto("EXP"); setAuto("FOCUS"); setAuto("WB")
        resetBias()
        setAELock(false); setAFLock(false)
        flashMode = "AUTO"
        setPhotoFormat("HEIF")
        setPhotoResolution(12)
        setZoom(1)
        if torchOn { toggleTorch() }
        previewLook = .original
    }
    func setPhotoFormat(_ format: String) { photoFormat = format; if format == "RAW" { rawEnabled = true } else { rawEnabled = false } }
    /// Must run after the session has applied its format: reads the sizes the active format can really shoot.
    private func refreshPhotoDimensions(_ camera: AVCaptureDevice) {
        func px(_ d: CMVideoDimensions) -> Int64 { Int64(d.width) * Int64(d.height) }
        let dims = camera.activeFormat.supportedMaxPhotoDimensions.sorted { px($0) < px($1) }
        twelveMPDimensions = dims.last(where: { px($0) <= 13_000_000 }) ?? dims.first
        fullPhotoDimensions = dims.last
        if let full = fullPhotoDimensions { photoOutput.maxPhotoDimensions = full }
        let has = (fullPhotoDimensions.map(px) ?? 0) >= 40_000_000
        let all = camera.formats.flatMap { $0.supportedMaxPhotoDimensions }.max { px($0) < px($1) }
        let info = "Max photo size: \(fullPhotoDimensions?.width ?? 0)×\(fullPhotoDimensions?.height ?? 0) · device max \(all?.width ?? 0)×\(all?.height ?? 0)"
        DispatchQueue.main.async {
            if self.photoResolutionMP >= 40 && !has {
                self.photoResolutionMP = 12
                self.message = "48 MP isn't available on this lens · \(info)"
            }
        }
    }
    /// 48 MP is the main 1x lens; choosing it jumps to 1x. Other lenses and zoomed crops shoot 12 MP.
    func setPhotoResolution(_ mp: Int) {
        prefers48 = mp >= 40 && has48MP
        photoResolutionMP = prefers48 ? 48 : 12
        if prefers48 { setZoom(1) }
    }
    func selectLens(_ z: CGFloat) { setZoom(z) }
    /// Picks a 4:3 format that supports ~48 MP stills (e.g. 8064x6048), if the device has one.
    private func selectHighResFormat(on camera: AVCaptureDevice) {
        func maxPixels(_ f: AVCaptureDevice.Format) -> Int64 {
            f.supportedMaxPhotoDimensions.map { Int64($0.width) * Int64($0.height) }.max() ?? 0
        }
        guard maxPixels(camera.activeFormat) < 40_000_000 else { return }
        let candidates = camera.formats.filter { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return maxPixels(f) >= 40_000_000 && d.width >= 4000 && Int(d.width) * 3 == Int(d.height) * 4
                && f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }
        guard let best = candidates.min(by: { maxPixels($0) < maxPixels($1) }) else { return }
        do {
            try camera.lockForConfiguration()
            camera.activeFormat = best
            camera.unlockForConfiguration()
        } catch {}
    }
    /// Macro = the ultra-wide lens (it focuses closest).
    func setMacroMode(_ enabled: Bool) { setZoom(enabled ? 0.5 : 1) }
    func capture() {
        frameInfoText = "ISO \(Int(iso))  ·  " + (shutter >= 0.5 ? String(format: "%.1fs", shutter) : "1/\(max(1, Int((1 / shutter).rounded())))") + "  ·  " + selectedLook
        guard running else { return }
        if panoramaMode && (panoramaProcessing || panoramaFrames.count >= 8) { return }
        if panoramaMode || nightMode || astroMode { rawEnabled = false }
        isSaving = true
        saveToken += 1
        let token = saveToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { if token == self.saveToken { self.isSaving = false } }
        // Snapshot UI state here; everything else happens off the main thread.
        let wantRAW = rawEnabled, wantJPEG = photoFormat == "JPEG"
        let use48 = photoResolutionMP >= 40 && !nightMode && !astroMode
        let flash = flashMode, night = nightMode || astroMode, hdr = hdrCollecting, pano = panoramaMode, burst = burstEnabled, prio = qualityPriority
        let fullDims = fullPhotoDimensions, twelveDims = twelveMPDimensions
        queue.async {
            let codec: AVVideoCodecType = wantJPEG || !self.photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .jpeg : .hevc
            let processedFormat: [String: Any] = [AVVideoCodecKey: codec]
            let settings: AVCapturePhotoSettings
            if wantRAW, let rawType = self.photoOutput.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }) ?? self.photoOutput.availableRawPhotoPixelFormatTypes.first {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: processedFormat)
            } else { settings = AVCapturePhotoSettings(format: processedFormat) }
            if let dimensions = use48 ? fullDims : twelveDims { settings.maxPhotoDimensions = dimensions }
            let requestedFlash: AVCaptureDevice.FlashMode = flash == "ON" ? .on : flash == "OFF" ? .off : .auto
            if self.photoOutput.supportedFlashModes.contains(requestedFlash) { settings.flashMode = requestedFlash }
            if night { settings.flashMode = .off }
            // Multi-frame modes merge several shots anyway, so each one can be fast; "best" is only worth it for single shots.
            settings.photoQualityPrioritization = (night || hdr || pano || burst || prio == 0) ? .speed : (prio == 2 ? .quality : .balanced)
            if let type = settings.availablePreviewPhotoPixelFormatTypes.first {
                settings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: type, kCVPixelBufferWidthKey as String: 480, kCVPixelBufferHeightKey as String: 480]
            }
            self.applyOrientation(to: self.photoOutput.connection(with: .video))
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleRecording(slowMotion: Bool, timeLapse: Bool = false, cinematic: Bool = false) {
        if movieOutput.isRecording { movieOutput.stopRecording(); return }
        guard running else { return }
        slowMotionMode = slowMotion
        timeLapseMode = timeLapse
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard let self else { return }
            self.queue.async {
                self.session.beginConfiguration()
                self.setFrameOutput(false)
                self.savedColorSpace = self.device?.activeColorSpace
                if granted, let mic = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: mic), self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                var switchedForCinematic = false
                let specialVideoCamera = cinematic ? self.dualWideCamera : slowMotion ? self.physicalWideCamera : nil
                if let target = specialVideoCamera, let current = self.cameraInput, target.uniqueID != current.device.uniqueID,
                   let nextInput = try? AVCaptureDeviceInput(device: target) {
                    self.session.removeInput(current)
                    if self.session.canAddInput(nextInput) {
                        self.session.addInput(nextInput)
                        self.preVideoCameraInput = current
                        self.cameraInput = nextInput
                        self.device = target
                        switchedForCinematic = true
                    } else { self.session.addInput(current) }
                }
                let selectedFPS = slowMotion ? Double(self.slowMotionFPS) : timeLapse ? 30.0 : Double(self.videoFPS)
                self.activeVideoFPS = Int(selectedFPS)
                self.photoVideoFormat = switchedForCinematic ? nil : self.device?.activeFormat
                let minimumWidth = slowMotion ? 1920 : self.widthRange(for: self.videoResolution).lowerBound
                let plain = !slowMotion && !timeLapse && !cinematic          // HDR / Log / ProRes only apply to plain video
                var usedRange = plain ? self.videoRange : "SDR"
                var wantSpace: AVCaptureColorSpace?
                if usedRange == "HDR" { wantSpace = .HLG_BT2020 }
                else if usedRange == "LOG", #available(iOS 17.0, *) { wantSpace = .appleLog }
                if wantSpace != nil { self.session.automaticallyConfiguresCaptureDeviceForWideColor = false }
                var configured = self.configureFrameRate(selectedFPS, minimumWidth: minimumWidth, cinematic: cinematic, space: wantSpace)
                var fellBackToSDR = false
                if !configured, wantSpace != nil {
                    usedRange = "SDR"; fellBackToSDR = true
                    self.session.automaticallyConfiguresCaptureDeviceForWideColor = true
                    configured = self.configureFrameRate(selectedFPS, minimumWidth: minimumWidth, cinematic: cinematic)
                }
                guard configured else {
                    if switchedForCinematic { self.restorePreVideoCamera() }
                    self.setFrameOutput(true)
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.message = "This resolution and frame rate aren't supported by the active camera" }
                    return
                }
                if cinematic {
                    guard #available(iOS 26.0, *), let input = self.cameraInput else { self.setFrameOutput(true); self.session.commitConfiguration(); return }
                    self.metadataOutput.metadataObjectTypes = self.metadataOutput.requiredMetadataObjectTypesForCinematicVideoCapture
                    input.isCinematicVideoCaptureEnabled = true
                }
                self.cinematicMode = cinematic
                self.session.commitConfiguration()
                if let connection = self.movieOutput.connection(with: .video), connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .cinematic
                }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-\(UUID().uuidString).mov")
                self.applyOrientation(to: self.movieOutput.connection(with: .video))
                // Codec: only what this configuration really offers; otherwise fall back and say so.
                var chosen = AVVideoCodecType.hevc
                var notes: [String] = []
                if fellBackToSDR { notes.append("HDR / Log isn't available at this resolution and frame rate — recording SDR") }
                if let connection = self.movieOutput.connection(with: .video) {
                    let available = self.movieOutput.availableVideoCodecTypes
                    switch plain ? self.videoCodec : "HEVC" {
                    case "PRORES":
                        if available.contains(.proRes422HQ) { chosen = .proRes422HQ }
                        else if available.contains(.proRes422) { chosen = .proRes422 }
                        else { notes.append("ProRes isn't available at this resolution and frame rate — using HEVC") }
                    case "H.264":
                        if usedRange == "SDR", available.contains(.h264) { chosen = .h264 } else { notes.append("H.264 can't carry HDR / Log — using HEVC") }
                    default: break
                    }
                    if available.contains(chosen) { self.movieOutput.setOutputSettings([AVVideoCodecKey: chosen], for: connection) }
                }
                // What actually started (not what was asked for), so you can verify 4K 100 / 120 fps etc.
                var info = ""
                if let d = self.device {
                    let dims = CMVideoFormatDescriptionGetDimensions(d.activeFormat.formatDescription)
                    let fps = Int((1.0 / max(d.activeVideoMinFrameDuration.seconds, 0.0001)).rounded())
                    let codecName = chosen == .h264 ? "H.264" : chosen == .hevc ? "HEVC" : "ProRes"
                    info = "\(dims.width)×\(dims.height) · \(fps) fps · \(codecName)" + (usedRange == "SDR" ? "" : " · \(usedRange)")
                }
                let report = info
                let noteText = notes.joined(separator: " · ")
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                DispatchQueue.main.async {
                    self.recordingInfo = report
                    self.message = noteText.isEmpty ? "Recording \(report)" : "Recording \(report) · \(noteText)"
                    self.isRecording = true
                    self.displayHandler?(nil); self.overlayHandler?(nil); self.loupeHandler?(nil)   // no frozen frames over the live preview
                }
            }
        }
    }

    private func configureFrameRate(_ fps: Double, minimumWidth: Int = 0, cinematic: Bool = false, space: AVCaptureColorSpace? = nil) -> Bool {
        guard let device else { return false }
        let compatible = device.formats.filter { format in
            let width = Int(CMVideoFormatDescriptionGetDimensions(format.formatDescription).width)
            let supportsCinematic: Bool
            if #available(iOS 26.0, *) { supportsCinematic = !cinematic || format.isCinematicVideoCaptureSupported } else { supportsCinematic = !cinematic }
            let spaceOK = space == nil || format.supportedColorSpaces.contains(space!)
            return width >= minimumWidth && spaceOK && supportsCinematic && format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= fps && $0.maxFrameRate >= fps }
        }.sorted { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }
        guard let format = compatible.first else { return false }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if let space, format.supportedColorSpaces.contains(space) { device.activeColorSpace = space }
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.unlockForConfiguration()
            return true
        } catch { device.unlockForConfiguration() }
        return false
    }

    private func restorePhotoFrameRate() {
        guard let device, let format = photoVideoFormat else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if let space = savedColorSpace, format.supportedColorSpaces.contains(space), device.activeColorSpace != space { device.activeColorSpace = space }
            if format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            }
            device.unlockForConfiguration()
        } catch { device.unlockForConfiguration() }
        photoVideoFormat = nil
    }

    private func restorePreVideoCamera() {
        guard let previous = preVideoCameraInput, let current = cameraInput else { return }
        session.removeInput(current)
        if session.canAddInput(previous) {
            session.addInput(previous)
            cameraInput = previous
            device = previous.device
        }
        preVideoCameraInput = nil
        metadataOutput.metadataObjectTypes = []
    }

    func resetPanorama() { panoramaFrames.removeAll(); panoramaShotCount = 0; panoramaProcessing = false }

    /// Stitch what has been shot so far (needs at least 2 frames).
    func finishPanorama() {
        finishQueue.async {
            guard self.panoramaFrames.count >= 2, !self.panoramaProcessing else { return }
            DispatchQueue.main.async { self.message = "Stitching panorama…" }
            self.stitchPanorama()
        }
    }

    /// Movement of `cur` relative to `prev`, in pixels of these (small) images — Vision translational registration.
    static func estimateStep(_ prev: CGImage, _ cur: CGImage) -> CGPoint? {
        let request = VNTranslationalImageRegistrationRequest(targetedCIImage: CIImage(cgImage: cur))
        guard (try? VNImageRequestHandler(ciImage: CIImage(cgImage: prev)).perform([request])) != nil,
              let t = request.results?.first?.alignmentTransform else { return nil }
        return CGPoint(x: t.tx, y: t.ty)
    }

    /// Pure stitching (no UI, no saving). `predicted[i-1]` is the measured shift of frame i relative to frame i-1, as fractions of the frame
    /// (same convention as Vision's alignment transform). Each placement is refined on the overlapping strips only.
    /// Returns the panorama with its origin at (0, 0), or nil if frames could not be aligned.
    static func stitchCore(_ frames: [CIImage], predicted: [CGPoint]?) -> CIImage? {
        guard frames.count >= 2 else { return frames.first }
        var placed: [CIImage] = [frames[0]]
        var offset = CGPoint.zero                                     // where the previous frame sits
        for i in 1..<frames.count {
            let f = frames[i]
            let w = f.extent.width, h = f.extent.height
            // 1. First guess: the shift measured while sweeping, or a whole-frame registration if there is none.
            var step = CGPoint.zero
            if let p = predicted, i - 1 < p.count {
                step = CGPoint(x: p[i - 1].x * w, y: p[i - 1].y * h)
            } else {
                let request = VNTranslationalImageRegistrationRequest(targetedCIImage: f)
                guard (try? VNImageRequestHandler(ciImage: frames[i - 1]).perform([request])) != nil,
                      let t = request.results?.first?.alignmentTransform else { return nil }
                step = CGPoint(x: t.tx, y: t.ty)
            }
            var position = CGPoint(x: offset.x + step.x, y: offset.y + step.y)
            // 2. Refine: compare only the part both frames really show.
            let current = f.transformed(by: CGAffineTransform(translationX: position.x, y: position.y))
            let rect = placed[i - 1].extent.intersection(current.extent).insetBy(dx: w * 0.04, dy: h * 0.04)
            if rect.width > 48, rect.height > 48 {
                let move = CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
                let a = placed[i - 1].cropped(to: rect).transformed(by: move)
                let b = current.cropped(to: rect).transformed(by: move)
                let request = VNTranslationalImageRegistrationRequest(targetedCIImage: b)
                if (try? VNImageRequestHandler(ciImage: a).perform([request])) != nil,
                   let r = request.results?.first?.alignmentTransform, abs(r.tx) < w * 0.12, abs(r.ty) < h * 0.12 {
                    position = CGPoint(x: position.x + r.tx, y: position.y + r.ty)
                }
            }
            offset = position
            placed.append(f.transformed(by: CGAffineTransform(translationX: position.x, y: position.y)))
        }
        // 3. Blend each frame into the picture over a narrow band in the middle of the overlap (a wide band would smear any misalignment).
        var union = placed[0].extent
        var composite = placed[0]
        for f in placed.dropFirst() {
            let e = f.extent
            let lo = max(e.minX, union.minX), hi = min(e.maxX, union.maxX)
            let mask: CIImage
            if hi - lo > 16 {
                let mid = (lo + hi) / 2, half = max(8, (hi - lo) * 0.12)
                let g = CIFilter.linearGradient()
                g.point0 = CGPoint(x: mid - half, y: 0); g.point1 = CGPoint(x: mid + half, y: 0)
                let newOnRight = e.midX >= union.midX
                g.color0 = newOnRight ? CIColor.black : CIColor.white
                g.color1 = newOnRight ? CIColor.white : CIColor.black
                mask = (g.outputImage ?? CIImage(color: .white)).cropped(to: e)
            } else { mask = CIImage(color: .white).cropped(to: e) }
            let blend = CIFilter.blendWithMask()
            blend.inputImage = f.cropped(to: e); blend.backgroundImage = composite; blend.maskImage = mask
            union = union.union(e)
            composite = (blend.outputImage ?? composite).cropped(to: union)
        }
        // 4. Keep only the rows every frame covers.
        let top = placed.map { $0.extent.maxY }.min() ?? union.maxY
        let bottom = placed.map { $0.extent.minY }.max() ?? union.minY
        let crop = CGRect(x: union.minX, y: bottom, width: union.width, height: max(1, top - bottom))
        return composite.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    }

    private func stitchPanorama() {
        let source = panoramaFrames
        let predicted = panoPredicted
        panoPredicted = nil
        DispatchQueue.main.async { self.panoramaProcessing = true }
        panoramaFrames.removeAll()
        let ratio = selectedAspect
        func fail(_ text: String) {
            DispatchQueue.main.async { self.message = text; self.panoramaShotCount = 0; self.panoramaProcessing = false }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard source.count >= 2 else { fail("Take at least 2 frames for a panorama"); return }
            // Every frame is cut to the viewfinder's shape, and scaled so the stitched image stays renderable.
            let cut = source.map { self.crop($0, to: ratio) }
            let estimatedWidth = cut.reduce(0) { $0 + $1.extent.width } * 0.75
            let k = min(1, 12000 / max(estimatedWidth, 1))
            let frames: [CIImage] = cut.map { f in
                var g = f.transformed(by: CGAffineTransform(translationX: -f.extent.minX, y: -f.extent.minY))
                if k < 1 { g = g.transformed(by: CGAffineTransform(scaleX: k, y: k)) }
                return g
            }
            guard let composite = CameraEngine.stitchCore(frames, predicted: predicted) else {
                fail("Panorama alignment failed — pan slower and keep the phone level"); return
            }
            let graded = LookProcessor.apply(Look(rawValue: self.selectedLook) ?? .original, to: composite, strength: self.lookStrength)
            // Save: straight to HEIC when possible, otherwise through an image (needed for the date stamp).
            if !self.timestampEnabled {
                let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
                if let data = LookProcessor.photoContext.heifRepresentation(of: graded, format: .RGBA8, colorSpace: space, options: [:]) {
                    self.saveToSession(data: data)
                    self.saveStillData(data, message: "Panorama saved")
                    DispatchQueue.main.async { self.panoramaShotCount = 0; self.panoramaProcessing = false }
                    return
                }
            }
            guard let cg = LookProcessor.photoContext.createCGImage(graded, from: graded.extent) else { fail("Could not render panorama"); return }
            let result = self.timestampEnabled ? self.stamp(UIImage(cgImage: cg)) : UIImage(cgImage: cg)
            self.saveToSession(result)
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else { DispatchQueue.main.async { self.panoramaProcessing = false }; return }
                PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: result) }) { ok, _ in
                    DispatchQueue.main.async {
                        self.panoramaShotCount = 0
                        self.panoramaProcessing = false
                        self.isSaving = false
                        self.message = ok ? "Panorama saved to Photos" : "Could not save panorama"
                    }
                }
            }
        }
    }

    private func stamp(_ image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let text = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        return renderer.image { context in
            image.draw(at: .zero)
            let font = UIFont.monospacedSystemFont(ofSize: max(20, image.size.width * 0.018), weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .strokeColor: UIColor.black.withAlphaComponent(0.65), .strokeWidth: -2]
            let size = (text as NSString).size(withAttributes: attributes)
            let rect = CGRect(x: image.size.width - size.width - 36, y: image.size.height - size.height - 32, width: size.width, height: size.height)
            (text as NSString).draw(in: rect, withAttributes: attributes)
        }
    }

    private func saveVideo(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }) { ok, _ in
                DispatchQueue.main.async { self.message = ok ? "Video saved to Photos" : "Could not save video" }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func saveStillData(_ data: Data, message: String) {
        publishThumbnail(data)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }) { ok, _ in DispatchQueue.main.async { self.captured = ok; self.isSaving = false; self.message = ok ? message : "Could not save photo" } }
        }
    }

    private func exportSpeed(_ url: URL, multiplier: Double, suffix: String) {
        let asset = AVURLAsset(url: url)
        guard let source = asset.tracks(withMediaType: .video).first else { saveVideo(url); return }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { saveVideo(url); return }
        do {
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: source, at: .zero)
            track.preferredTransform = source.preferredTransform
            let adjustedDuration = CMTimeMultiplyByFloat64(asset.duration, multiplier: multiplier)
            track.scaleTimeRange(CMTimeRange(start: .zero, duration: asset.duration), toDuration: adjustedDuration)
            if let sourceAudio = asset.tracks(withMediaType: .audio).first,
               let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try audio.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: sourceAudio, at: .zero)
                audio.scaleTimeRange(CMTimeRange(start: .zero, duration: asset.duration), toDuration: adjustedDuration)
            }
        } catch { saveVideo(url); return }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { saveVideo(url); return }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-\(suffix)-\(UUID().uuidString).mov")
        exporter.outputURL = output
        exporter.outputFileType = .mov
        exporter.exportAsynchronously {
            if exporter.status == .completed {
                try? FileManager.default.removeItem(at: url)
                self.saveVideo(output)
            } else {
                try? FileManager.default.removeItem(at: output)
                self.saveVideo(url)
            }
        }
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Instant feedback: the small preview that comes with the photo is shown while the full image is processed.
        if !photo.isRawPhoto, !nightMode, !astroMode, !panoramaMode, !hdrCollecting, let p = photo.previewCGImageRepresentation() {
            let raw = (photo.metadata[kCGImagePropertyOrientation as String] as? UInt32) ?? 1
            let orientation: UIImage.Orientation
            switch CGImagePropertyOrientation(rawValue: raw) ?? .up {
            case .up: orientation = .up; case .upMirrored: orientation = .upMirrored
            case .down: orientation = .down; case .downMirrored: orientation = .downMirrored
            case .left: orientation = .left; case .leftMirrored: orientation = .leftMirrored
            case .right: orientation = .right; case .rightMirrored: orientation = .rightMirrored
            }
            let t = UIImage(cgImage: p, scale: 1, orientation: orientation)
            DispatchQueue.main.async { self.lastThumbnail = t }
        }
        finishQueue.async {
            self.finishing += 1
            self.handlePhoto(photo, error: error)
            self.finishing -= 1
        }
    }

    private func handlePhoto(_ photo: AVCapturePhoto, error: Error?) {
        if error != nil, nightMode || astroMode {
            DispatchQueue.main.async { self.message = "A frame failed — finishing with what was captured" }
            if nightAcc != nil { finishStack() } else { DispatchQueue.main.async { self.endStack() } }
            return
        }
        guard let data = photo.fileDataRepresentation() else { return }
        if nightMode || astroMode {
            guard !photo.isRawPhoto, let frame = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return }
            stackFrame(frame)
            return
        }
        if hdrCollecting {
            guard !photo.isRawPhoto, let frame = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return }
            hdrFrames.append(frame)
            let n = hdrFrames.count
            DispatchQueue.main.async { self.message = n < self.hdrTarget ? "HDR · \(n)/\(self.hdrTarget)" : "Merging HDR…" }
            if n >= hdrTarget { hdrCollecting = false; let f = hdrFrames; hdrFrames = []; mergeHDR(f) }
            return
        }
        if panoramaMode {
            guard !photo.isRawPhoto, let frame = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return }
            panoramaFrames.append(frame)
            let count = panoramaFrames.count
            DispatchQueue.main.async { self.panoramaShotCount = count; self.message = count < 8 ? "Panorama · \(count) frames — keep panning, or tap FINISH" : "Stitching panorama…" }
            if count >= 8 { stitchPanorama() }
            return
        }
        if photo.isRawPhoto {
            if let p = photo.previewCGImageRepresentation() { let t = UIImage(cgImage: p); DispatchQueue.main.async { self.lastThumbnail = t } }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else { return }
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }) { ok, _ in DispatchQueue.main.async { self.captured = ok; self.message = ok ? "RAW saved to Photos" : "Could not save RAW" } }
            }
            return
        }
        guard let input = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return }
        var source = input
        if portraitMode {
            let (composited, ok) = portraitComposite(input)
            source = composited
            if !ok { DispatchQueue.main.async { self.message = "No person found — saved without blur" } }
        }
        finishStill(source)
    }

    /// Look + crop + stamp/frame + thumbnail + save to Photos.
    private func finishStill(_ source: CIImage, savedMessage: String = "Saved to Photos") {
        let graded = LookProcessor.apply(Look(rawValue: selectedLook) ?? .original, to: source, strength: lookStrength)
        let framed = crop(graded, to: selectedAspect)
        if !timestampEnabled && frameStyle == 0 {
            let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
            if let data = LookProcessor.photoContext.heifRepresentation(of: framed, format: .RGBA8, colorSpace: space, options: [:]) {
                saveToSession(data: data)
                saveStillData(data, message: savedMessage)
                return
            }
        }
        guard let cg = LookProcessor.photoContext.createCGImage(framed, from: framed.extent) else { return }
        let image = UIImage(cgImage: cg)
        var finalImage = timestampEnabled ? stamp(image) : image
        if frameStyle > 0 { finalImage = addFrame(finalImage, info: frameInfoText) }
        saveToSession(finalImage)
        if let thumb = finalImage.preparingThumbnail(of: CGSize(width: 160, height: 160)) {
            DispatchQueue.main.async { self.lastThumbnail = thumb }
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: finalImage) }) { ok, _ in
                DispatchQueue.main.async { self.captured = ok; self.isSaving = false; self.message = ok ? savedMessage : "Could not save photo" }
            }
        }
    }

    private func crop(_ image: CIImage, to ratio: CGFloat) -> CIImage {
        guard ratio > 0 else { return image }
        let bounds = image.extent
        let current = bounds.width / bounds.height
        let ratio = bounds.width >= bounds.height ? ratio : 1 / ratio   // portrait photo → tall crop, landscape → wide crop
        let rect: CGRect
        if current > ratio {
            let width = bounds.height * ratio
            rect = CGRect(x: bounds.midX - width / 2, y: bounds.minY, width: width, height: bounds.height)
        } else {
            let height = bounds.width / ratio
            rect = CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
        }
        return image.cropped(to: rect)
    }
}

extension CameraEngine: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { self.isRecording = false; self.recordingInfo = nil }
        if let error { DispatchQueue.main.async { self.message = "Recording stopped: \(error.localizedDescription)" } }
        if slowMotionMode { exportSpeed(outputFileURL, multiplier: Double(activeVideoFPS) / 30, suffix: "Slow") }
        else if timeLapseMode { exportSpeed(outputFileURL, multiplier: 0.1, suffix: "TimeLapse") }
        else { saveVideo(outputFileURL) }
        queue.async {
            self.session.beginConfiguration()
            if self.cinematicMode, #available(iOS 26.0, *), let input = self.cameraInput { input.isCinematicVideoCaptureEnabled = false }
            if self.cinematicMode || self.slowMotionMode { self.restorePreVideoCamera() }
            self.restorePhotoFrameRate()
            self.setFrameOutput(true)
            self.session.automaticallyConfiguresCaptureDeviceForWideColor = true
            self.session.commitConfiguration()
            self.cinematicMode = false
        }
    }
}

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func setAnalysis(peaking: Bool, zebra: Bool, histogram: Bool) {
        peakingEnabled = peaking; zebraEnabled = zebra; histogramEnabled = histogram
        if !peaking && !zebra { DispatchQueue.main.async { self.overlayHandler?(nil) } }
        if !histogram { DispatchQueue.main.async { self.hist.data = HistogramModel.Data() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let look = previewLook
        let needLook = !compareRaw && !videoMode && thermalLevel < 2 && (look != .original || LookProcessor.hasExtras)
        let needOverlay = peakingEnabled || zebraEnabled
        guard isForeground, Date() >= pauseFramesUntil, !isRecording, needLook || needOverlay || histogramEnabled || trailActive || thumbCompletion != nil || magnifierEnabled || wbPickPoint != nil || suggestionsEnabled || snapshotRequested || clearOverlayAfterSwap || panoSweeping,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameCounter &+= 1
        if panoSweeping { handlePanoFrame(buffer); return }
        if snapshotRequested {
            snapshotRequested = false
            let work = snapshotWork; snapshotWork = nil
            var snap = CIImage(cvPixelBuffer: buffer).oriented(frameOrientation())
            let sc = previewMaxWidth / max(snap.extent.width, 1)
            if sc < 1 { snap = snap.transformed(by: CGAffineTransform(scaleX: sc, y: sc)) }
            let shown = needLook ? LookProcessor.apply(look, to: snap, strength: lookStrength) : snap
            if let cg = LookProcessor.context.createCGImage(shown, from: shown.extent) {
                DispatchQueue.main.async { self.displayHandler?(cg); DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { work?() } }
            } else { DispatchQueue.main.async { work?() } }
        }
        if clearOverlayAfterSwap, frameCounter &- swapFrameMark >= 3 {
            clearOverlayAfterSwap = false
            if !needLook { DispatchQueue.main.async { self.displayHandler?(nil) } }   // new lens is live: fade the frozen picture out
        }
        if let completion = thumbCompletion {
            thumbCompletion = nil
            var sample = CIImage(cvPixelBuffer: buffer).oriented(frameOrientation())
            let k = 200 / max(sample.extent.width, sample.extent.height)
            sample = sample.transformed(by: CGAffineTransform(scaleX: k, y: k))
            if let cgSample = LookProcessor.context.createCGImage(sample, from: sample.extent) {
                DispatchQueue.global(qos: .utility).async {
                    let thumbs = LookProcessor.thumbnails(for: CIImage(cgImage: cgSample))
                    DispatchQueue.main.async { completion(thumbs) }
                }
            }
        }
        if let pt = wbPickPoint { wbPickPoint = nil; applyPickedWhiteBalance(buffer, at: pt) }
        if suggestionsEnabled, thermalLevel == 0, !trailActive, Date().timeIntervalSince(lastSuggestTime) > 1.5 {
            lastSuggestTime = Date(); analyzeScene(buffer)
        }
        if magnifierEnabled, !trailActive, frameCounter % 2 == 0 {
            let full = CIImage(cvPixelBuffer: buffer).oriented(frameOrientation())
            let e = full.extent, side: CGFloat = 420
            let rect = CGRect(x: e.midX - side / 2, y: e.midY - side / 2, width: side, height: side)
            if let cg = LookProcessor.context.createCGImage(full, from: rect) {
                DispatchQueue.main.async { [weak self] in self?.loupeHandler?(cg) }
            }
        }
        if !(needLook || needOverlay || histogramEnabled || trailActive) { return }
        if trailActive { handleTrailFrame(buffer); return }
        var image = CIImage(cvPixelBuffer: buffer).oriented(frameOrientation())
        let scale = previewMaxWidth / max(image.extent.width, 1)
        if scale < 1 { image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        let ctx = LookProcessor.context

        let heavyLook = finishing > 0 || look.spec.halation + LookProcessor.extraHalation > 0 || LookProcessor.extraLeak > 0 || LookProcessor.extraDust > 0
        if needLook, !(heavyLook && frameCounter % 2 == 1) {
            let graded = LookProcessor.apply(look, to: image, strength: lookStrength)
            if let cg = ctx.createCGImage(graded, from: graded.extent) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.previewLook == look else { return }
                    self.displayHandler?(cg)
                }
            }
        }
        if needOverlay, frameCounter % 2 == 0, let overlay = analysisOverlay(for: image), let cg = ctx.createCGImage(overlay, from: overlay.extent) {
            DispatchQueue.main.async { [weak self] in self?.overlayHandler?(cg) }
        }
        if histogramEnabled, frameCounter % 3 == 0 { updateHistogram(image) }
    }

    /// Focus peaking: marks only the sharpest edges. The threshold follows the picture's own average edge strength, so noise,
    /// fine texture and out-of-focus areas are not painted (a fixed low threshold covered the whole screen).
    static func peakingMask(_ luma: CIImage) -> CIImage {
        let soft = luma.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.6]).cropped(to: luma.extent)   // calms sensor noise
        let edges = soft.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])
        let avg = edges.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: edges.extent)])
        var px = [Float](repeating: 0, count: 4)
        LookProcessor.context.render(avg, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        let threshold = max(0.04, CGFloat(px[0]) * 2.0)
        return edges.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 14, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 1, y: 0.2, z: 0.1, w: -14 * threshold)])
            .applyingFilter("CIColorClamp")   // alpha must stay 0…1: negative alpha would darken whatever it is composited over
    }
    private func analysisOverlay(for full: CIImage) -> CIImage? {
        let image = full.transformed(by: CGAffineTransform(scaleX: 0.6, y: 0.6))   // overlay is stretched back over the preview, so a smaller image is plenty
        let luma = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        var result: CIImage?
        if peakingEnabled { result = CameraEngine.peakingMask(luma) }
        if zebraEnabled {
            let zebra = luma.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 22, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 1, y: 0.1, z: 0.6, w: -20.4)])
            result = result.map { zebra.composited(over: $0) } ?? zebra
        }
        return result?.cropped(to: image.extent)
    }

    private func updateHistogram(_ full: CIImage) {
        let image = full.transformed(by: CGAffineTransform(scaleX: 0.4, y: 0.4))
        let bins = 64
        let hist = image.applyingFilter("CIAreaHistogram", parameters: [
            "inputExtent": CIVector(cgRect: image.extent), "inputScale": 1.0, "inputCount": bins])
        var buf = [Float](repeating: 0, count: bins * 4)
        LookProcessor.context.render(hist, toBitmap: &buf, rowBytes: bins * 16,
                                     bounds: CGRect(x: 0, y: 0, width: bins, height: 1), format: .RGBAf, colorSpace: nil)
        var luma = (0..<bins).map { 0.299 * buf[$0 * 4] + 0.587 * buf[$0 * 4 + 1] + 0.114 * buf[$0 * 4 + 2] }
        var rr = (0..<bins).map { buf[$0 * 4] }, gg = (0..<bins).map { buf[$0 * 4 + 1] }, bb = (0..<bins).map { buf[$0 * 4 + 2] }
        let total = max(luma.reduce(0, +), 0.0001)
        let hi = (luma[bins - 1] + luma[bins - 2]) / total, lo = (luma[0] + luma[1]) / total
        let peak = luma.max() ?? 1
        if peak > 0 { luma = luma.map { ($0 / peak).squareRoot() } }
        let cpeak = max(rr.max() ?? 0, gg.max() ?? 0, bb.max() ?? 0)
        if cpeak > 0 { rr = rr.map { ($0 / cpeak).squareRoot() }; gg = gg.map { ($0 / cpeak).squareRoot() }; bb = bb.map { ($0 / cpeak).squareRoot() } }
        let d = HistogramModel.Data(luma: luma, r: rr, g: gg, b: bb, hi: hi, lo: lo)
        DispatchQueue.main.async { [weak self] in self?.hist.data = d }
    }

    /// Person cut-out (Vision) with the background blurred. Returns false if nobody was found.
    func portraitComposite(_ input: CIImage) -> (CIImage, Bool) {
        let extent = input.extent
        let longSide = max(extent.width, extent.height)
        let s = min(1, 1280 / longSide)
        let small = input.transformed(by: CGAffineTransform(scaleX: s, y: s))
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(ciImage: small, options: [:])
        guard (try? handler.perform([request])) != nil,
              let buffer = request.results?.first?.pixelBuffer else { return (input, false) }
        var mask = CIImage(cvPixelBuffer: buffer)
        let avg = mask.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: mask.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        LookProcessor.photoContext.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        guard px[0] > 6 else { return (input, false) }   // no person in frame
        mask = mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width, y: extent.height / mask.extent.height))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: longSide / 600])
            .cropped(to: extent)
        let radius = Double(longSide) / 160 * (0.3 + 1.4 * Double(portraitBlurAmount))
        let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = input; blend.backgroundImage = blurred; blend.maskImage = mask
        return (blend.outputImage?.cropped(to: extent) ?? input, true)
    }

    // MARK: HDR merge (exposure fusion by soft per-pixel selection)
    private func alignFrames(_ frames: [CIImage], reference: Int) -> [CIImage] {
        guard frames.indices.contains(reference) else { return frames }
        let ref = frames[reference]
        let s: CGFloat = 0.25
        let refSmall = ref.transformed(by: CGAffineTransform(scaleX: s, y: s))
        return frames.enumerated().map { i, f in
            guard i != reference else { return f }
            let req = VNTranslationalImageRegistrationRequest(targetedCIImage: f.transformed(by: CGAffineTransform(scaleX: s, y: s)), options: [:])
            if (try? VNImageRequestHandler(ciImage: refSmall, options: [:]).perform([req])) != nil,
               let obs = req.results?.first as? VNImageTranslationAlignmentObservation {
                let t = obs.alignmentTransform
                return f.transformed(by: CGAffineTransform(translationX: t.tx / s, y: t.ty / s)).clampedToExtent().cropped(to: f.extent)
            }
            return f
        }
    }
    private func mergeHDR(_ frames: [CIImage]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let mid = frames.count / 2
            let aligned = self.alignFrames(frames, reference: mid)
            let full = aligned[mid].extent
            func weight(_ img: CIImage) -> CIImage {
                let gray = img.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
                let poly = CIVector(x: 0, y: 4, z: -4, w: 0)   // 4L(1-L): best exposed near mid-grey
                return gray.applyingFilter("CIColorPolynomial", parameters: [
                    "inputRedCoefficients": poly, "inputGreenCoefficients": poly, "inputBlueCoefficients": poly,
                    "inputAlphaCoefficients": CIVector(x: 1, y: 0, z: 0, w: 0)])
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 5]).cropped(to: full)
            }
            func scaled(_ img: CIImage, _ k: CGFloat, bias: CGFloat = 0) -> CIImage {
                img.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)])
            }
            var best = aligned[mid]
            var bestW = weight(best)
            for (i, f) in aligned.enumerated() where i != mid {
                let w = weight(f)
                // m = clamp(((w - bestW) * 0.5 + 0.5 - 0.5) * 40 + 0.5)  → soft "is this frame better here?"
                let add = CIFilter.additionCompositing()
                add.inputImage = scaled(w, 0.5); add.backgroundImage = scaled(bestW.applyingFilter("CIColorInvert"), 0.5)
                let sum = (add.outputImage ?? w).cropped(to: full)          // = 0.5 + 0.5 (w - bestW)
                var mask = scaled(sum, 40, bias: 0.5 - 20)
                mask = mask.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 14]).cropped(to: full)
                let blend = CIFilter.blendWithMask()
                blend.inputImage = f; blend.backgroundImage = best; blend.maskImage = mask
                best = (blend.outputImage ?? best).cropped(to: full)
                let lighten = CIFilter.lightenBlendMode()
                lighten.inputImage = w; lighten.backgroundImage = bestW
                bestW = (lighten.outputImage ?? bestW).cropped(to: full)
            }
            self.finishStill(best, savedMessage: "HDR photo saved")
        }
    }

    // MARK: Intervalometer
    func startInterval() {
        guard running, !isInterval else { return }
        intervalShot = 0; isInterval = true
        UIApplication.shared.isIdleTimerDisabled = true
        fireInterval()
        intervalTimer?.invalidate()
        intervalTimer = Timer.scheduledTimer(withTimeInterval: Double(max(1, intervalSeconds)), repeats: true) { [weak self] _ in self?.fireInterval() }
    }
    private func fireInterval() {
        guard isInterval else { return }
        capture()
        intervalShot += 1
        if intervalShot >= intervalCount { stopInterval() }
    }
    func stopInterval() {
        intervalTimer?.invalidate(); intervalTimer = nil
        guard isInterval else { return }
        isInterval = false
        UIApplication.shared.isIdleTimerDisabled = false
        message = "Interval finished · \(intervalShot) photos"
    }

    // MARK: Session shots (used for Photos → PDF)
    private func saveToSession(data: Data) {
        DispatchQueue.global(qos: .utility).async {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2400]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
                  let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { return }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("session", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("shot-\(UUID().uuidString).jpg")
            guard (try? jpeg.write(to: url)) != nil else { return }
            DispatchQueue.main.async {
                self.sessionShots.append(url)
                if self.sessionShots.count > 40 { try? FileManager.default.removeItem(at: self.sessionShots.removeFirst()) }
                self.sessionCount = self.sessionShots.count
            }
        }
    }
    private func saveToSession(_ image: UIImage) {
        DispatchQueue.global(qos: .utility).async {
            let small = image.preparingThumbnail(of: CGSize(width: 2400, height: 2400)) ?? image
            guard let data = small.jpegData(compressionQuality: 0.85) else { return }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("session", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("shot-\(UUID().uuidString).jpg")
            guard (try? data.write(to: url)) != nil else { return }
            DispatchQueue.main.async {
                self.sessionShots.append(url)
                if self.sessionShots.count > 40 { try? FileManager.default.removeItem(at: self.sessionShots.removeFirst()) }
                self.sessionCount = self.sessionShots.count
            }
        }
    }

    // MARK: Hyperfocal estimate (approximate, from field of view and lens aperture)
    private func widthRange(for resolution: String) -> Range<Int> {
        switch resolution {
        case "8K": return 7680..<100_000
        case "4K UHD": return 3840..<7680
        case "720p": return 1280..<1920
        default: return 1920..<3840
        }
    }
    private func videoFormats(for resolution: String) -> [AVCaptureDevice.Format] {
        let range = widthRange(for: resolution)
        return (physicalWideCamera ?? device)?.formats.filter { range.contains(Int(CMVideoFormatDescriptionGetDimensions($0.formatDescription).width)) } ?? []
    }
    private func supportsFPS(_ f: AVCaptureDevice.Format, _ fps: Int) -> Bool {
        f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= Double(fps) && $0.maxFrameRate >= Double(fps) }
    }
    /// Field of view along the sensor's long side, in degrees, including the current digital zoom.
    func effectiveFOV() -> Double {
        guard let d = device else { return 65 }
        let fov = Double(d.activeFormat.videoFieldOfView) * .pi / 180
        return 2 * atan(tan(fov / 2) / Double(max(1, d.videoZoomFactor))) * 180 / .pi
    }
    /// Frame rates the main lens really supports at this resolution (24 / 25 PAL / 30 / 50 PAL / 60 / 100 / 120…).
    func videoRates(for resolution: String) -> [Int] {
        let formats = videoFormats(for: resolution)
        return [24, 25, 30, 48, 50, 60, 100, 120].filter { fps in formats.contains { supportsFPS($0, fps) } }
    }
    /// SDR always; HDR (HLG) and LOG (Apple Log) only when a format at this resolution / frame rate supports them.
    func videoRanges(for resolution: String, fps: Int) -> [String] {
        let formats = videoFormats(for: resolution).filter { supportsFPS($0, fps) }
        var out = ["SDR"]
        if formats.contains(where: { $0.supportedColorSpaces.contains(.HLG_BT2020) }) { out.append("HDR") }
        if #available(iOS 17.0, *), formats.contains(where: { $0.supportedColorSpaces.contains(.appleLog) }) { out.append("LOG") }
        return out
    }
    /// HEVC and H.264 (8-bit SDR only); ProRes on Pro iPhones for 4K / HD up to 30 fps.
    func videoCodecs(for resolution: String, fps: Int, range: String) -> [String] {
        var out = ["HEVC"]
        if range == "SDR" { out.append("H.264") }
        let proCapable = telephotoCamera != nil && videoFormats(for: resolution).contains { $0.supportedColorSpaces.contains(.HLG_BT2020) }
        if proCapable, fps <= 30, resolution == "4K UHD" || resolution == "HD" { out.append("PRORES") }
        return out
    }
    func hyperfocal() -> (hyper: Double, near: Double)? {
        guard let d = device, d.lensAperture > 0 else { return nil }
        let fov = Double(d.activeFormat.videoFieldOfView) * .pi / 180
        guard fov > 0.1 else { return nil }
        let fEq = 18.0 / tan(fov / 2)                                   // 35mm-equivalent focal length (mm)
        let crop: Double = d === ultraWideCamera ? 7.0 : d === telephotoCamera ? 5.5 : 3.7   // approximate sensor crop factors
        let fReal = fEq / crop, coc = 0.030 / crop
        let h = (fReal * fReal) / (Double(d.lensAperture) * coc) + fReal   // mm
        return (h / 1000, h / 2000)
    }

    // MARK: Scene analysis → look suggestion
    private func analyzeScene(_ buffer: CVPixelBuffer) {
        var img = CIImage(cvPixelBuffer: buffer).oriented(frameOrientation())
        let k = 256 / max(img.extent.width, img.extent.height)
        img = img.transformed(by: CGAffineTransform(scaleX: k, y: k))
        let faceReq = VNDetectFaceRectanglesRequest()
        let hasFace = (try? VNImageRequestHandler(ciImage: img, options: [:]).perform([faceReq])) != nil && !(faceReq.results?.isEmpty ?? true)
        let avg = img.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: img.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        LookProcessor.context.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        let suggestion: String?
        if hasFace { suggestion = Look.portra.rawValue }
        else if luma < 0.16 { suggestion = Look.cinestill.rawValue }
        else if g > r * 1.08 && g > b * 1.05 { suggestion = Look.forest.rawValue }
        else if b > r * 1.12 && luma > 0.35 { suggestion = Look.beach.rawValue }
        else if r > b * 1.3 && luma > 0.3 { suggestion = Look.sunkissed.rawValue }
        else if luma > 0.62 { suggestion = Look.airy.rawValue }
        else { suggestion = nil }
        DispatchQueue.main.async { [weak self] in if self?.suggestedLook != suggestion { self?.suggestedLook = suggestion } }
    }

    // MARK: White-balance picker
    private func applyPickedWhiteBalance(_ buffer: CVPixelBuffer, at pt: CGPoint) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        let cx = min(max(Int(pt.x * CGFloat(w)), 8), w - 9), cy = min(max(Int(pt.y * CGFloat(h)), 8), h - 9)
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for y in (cy - 6)...(cy + 6) {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in (cx - 6)...(cx + 6) { b += Double(row[x * 4]); g += Double(row[x * 4 + 1]); r += Double(row[x * 4 + 2]); n += 1 }
        }
        r /= n; g /= n; b /= n
        guard r > 8, g > 8, b > 8, let d = device else {
            DispatchQueue.main.async { self.message = "Tap a brighter grey or white object" }
            return
        }
        let cur = d.deviceWhiteBalanceGains
        var gains = AVCaptureDevice.WhiteBalanceGains(redGain: Float(Double(cur.redGain) * g / r), greenGain: cur.greenGain, blueGain: Float(Double(cur.blueGain) * g / b))
        let m = min(gains.redGain, gains.greenGain, gains.blueGain)
        if m < 1 { gains.redGain /= m; gains.greenGain /= m; gains.blueGain /= m }
        let mx = d.maxWhiteBalanceGain
        gains.redGain = min(max(gains.redGain, 1), mx); gains.greenGain = min(max(gains.greenGain, 1), mx); gains.blueGain = min(max(gains.blueGain, 1), mx)
        guard d.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            d.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            d.unlockForConfiguration()
            let tv = d.temperatureAndTintValues(for: gains)
            DispatchQueue.main.async {
                self.autoWB = false
                self.temperature = tv.temperature; self.tint = tv.tint
                self.message = "White balance set · \(Int(tv.temperature))K"
            }
        }
    }

    // MARK: Continuous panorama sweep
    func startPanoSweep() {
        guard running, !panoSweeping, !panoramaProcessing else { return }
        panoKeys = []; panoPositions = []; panoLastKeySmall = nil; panoPrevSmall = nil; panoAccum = .zero; panoDirection = 0; panoCounter = 0
        panoStrip = nil; panoramaShotCount = 0; panoShifts = []
        panoRestore = (autoExposure, autoWB, autoFocus)
        if let d = device {
            queue.async {
                do { try d.lockForConfiguration() } catch { return }
                if d.isExposureModeSupported(.locked) { d.exposureMode = .locked }
                if d.isWhiteBalanceModeSupported(.locked) { d.whiteBalanceMode = .locked }
                if d.isFocusModeSupported(.locked) { d.focusMode = .locked }
                d.unlockForConfiguration()
            }
        }
        UIApplication.shared.isIdleTimerDisabled = true
        displayHandler?(nil)
        panoSweeping = true
        message = "Sweep slowly in either direction — tap the shutter to finish"
    }
    func finishPanoSweep() {
        guard panoSweeping else { return }
        panoSweeping = false
        UIApplication.shared.isIdleTimerDisabled = false
        panoGhostHandler?(nil, 0, 0, 0)
        panoStrip = nil
        // Back to automatic exposure / white balance / focus (whatever was automatic before the sweep).
        if panoRestore.exp { setAuto("EXP") }
        if panoRestore.wb { setAuto("WB") }
        if panoRestore.focus { setAuto("FOCUS") }
        frameQueue.async {            // after any frame already being handled
            let keys = self.panoKeys
            let shifts = self.panoShifts
            self.panoKeys = []; self.panoPositions = []; self.panoLastKeySmall = nil; self.panoShifts = []
            guard keys.count >= 2 else {
                DispatchQueue.main.async { self.message = "Sweep a little further — a panorama needs at least 2 frames"; self.panoramaShotCount = 0 }
                return
            }
            self.finishQueue.async {
                self.panoramaFrames = keys.map { CIImage(cgImage: $0) }
                self.panoPredicted = shifts
                DispatchQueue.main.async { self.message = "Stitching panorama…" }
                self.stitchPanorama()
            }
        }
    }
    private func handlePanoFrame(_ buffer: CVPixelBuffer) {
        panoCounter += 1
        guard panoKeys.isEmpty || panoCounter % 3 == 0 else { return }       // ~10 checks per second
        let full = CIImage(cvPixelBuffer: buffer).oriented(frameOrientation())
        let ctx = LookProcessor.context
        func render(_ img: CIImage, maxSide: CGFloat) -> CGImage? {
            let k = min(1, maxSide / max(img.extent.width, img.extent.height))
            let scaled = k < 1 ? img.transformed(by: CGAffineTransform(scaleX: k, y: k)) : img
            return ctx.createCGImage(scaled, from: scaled.extent)
        }
        guard let small = render(full, maxSide: 320) else { return }
        // Key frames are cut to the viewfinder's shape, so what the ghost / strip show is what gets stitched.
        let shaped = crop(full, to: selectedAspect)
        let cropX = full.extent.width / max(shaped.extent.width, 1)
        let cropY = full.extent.height / max(shaped.extent.height, 1)
        if panoKeys.isEmpty {
            guard let key = render(shaped, maxSide: 1800) else { return }
            panoKeys = [key]; panoPositions = [0]; panoLastKeySmall = small; panoPrevSmall = small; panoAccum = .zero
            let strip = makePanoStrip()
            DispatchQueue.main.async { self.panoramaShotCount = 1; self.panoStrip = strip }
            return
        }
        // Track small steps between consecutive frames (reliable) and add them up, instead of comparing against a frame 40 % of a screen ago.
        guard let previous = panoPrevSmall, let step = CameraEngine.estimateStep(previous, small) else { panoPrevSmall = small; return }
        panoPrevSmall = small
        panoAccum = CGPoint(x: panoAccum.x + step.x, y: panoAccum.y + step.y)
        let fx = panoAccum.x / CGFloat(small.width) * cropX          // how far the camera has moved since the last key frame (fractions of the key frame)
        let fy = panoAccum.y / CGFloat(small.height) * cropY
        // Live overlap preview: the previous key frame, translucent, exactly where it sits in the current view.
        let lastKey = panoKeys.last, index = panoKeys.count
        DispatchQueue.main.async { self.panoGhostHandler?(lastKey, index, -fx, fy) }
        if panoDirection == 0, abs(fx) > 0.06 { panoDirection = fx > 0 ? 1 : -1 }
        if panoDirection != 0, fx * panoDirection < -0.1 { return }                      // moving back: ignore
        if abs(fx) >= 0.4, panoDirection == 0 || fx * panoDirection > 0 {                 // enough new picture: keep this frame
            guard let key = render(shaped, maxSide: 1800) else { return }
            panoKeys.append(key); panoLastKeySmall = small; panoAccum = .zero
            panoPositions.append((panoPositions.last ?? 0) + fx)
            panoShifts.append(CGPoint(x: fx, y: fy))
            let strip = makePanoStrip(), n = panoKeys.count
            DispatchQueue.main.async {
                self.panoramaShotCount = n; self.panoStrip = strip
                self.message = "Panorama · \(n) frames — keep sweeping, or tap the shutter to finish"
                if n >= 10 { self.finishPanoSweep() }
            }
        }
    }
    private func makePanoStrip() -> UIImage? {
        guard let first = panoKeys.first else { return nil }
        let h: CGFloat = 90
        let fw = h * CGFloat(first.width) / CGFloat(first.height)
        let minP = panoPositions.min() ?? 0, maxP = panoPositions.max() ?? 0
        let size = CGSize(width: max((maxP - minP + 1) * fw, fw), height: h)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for (i, key) in panoKeys.enumerated() where i < panoPositions.count {
                UIImage(cgImage: key).draw(in: CGRect(x: (panoPositions[i] - minP) * fw, y: 0, width: fw, height: h))
            }
        }
    }

    // MARK: Night + star stacking (frames are merged one by one, so memory stays flat however long you shoot)
    func startNight() { beginStack(astro: false) }
    func startAstro() { beginStack(astro: true) }
    /// Finish early with the frames captured so far.
    func stopNight() {
        guard nightBusy else { return }
        nightStopRequested = true
        message = "Finishing…"
    }
    private func beginStack(astro: Bool) {
        guard running, !nightBusy else { return }
        nightBusy = true; nightCount = 0; nightRef = nil; nightAcc = nil; nightStopRequested = false
        nightStart = Date()
        astroSkySnapshot = (astro && skyBurn) ? skyProvider?() : nil
        nightSavedBias = exposureBias
        UIApplication.shared.isIdleTimerDisabled = true
        if astro { prepareAstro() } else { setBias(max(exposureBias, 0.7)) }
        let target = astro ? astroSeconds : nightSeconds
        message = astro ? "Stars · \(target)s · keep the phone on a tripod · tap the shutter to finish early"
                        : (target == 0 ? "Night · hold still" : "Night · \(target)s · hold still · tap the shutter to finish early")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.nightStopRequested && self.nightCount == 0 { self.endStack(); return }
            self.capture()
        }
    }
    /// Longest exposure the sensor allows, high ISO, focus locked at infinity.
    private func prepareAstro() {
        guard let d = device else { return }
        let f = d.activeFormat
        let dur = min(f.maxExposureDuration.seconds, 3.0)
        let isoValue = min(max(f.minISO, 1600), f.maxISO)
        shutter = dur; iso = isoValue; autoExposure = false; autoFocus = false
        let t = CMTime(seconds: dur, preferredTimescale: 1_000_000_000)
        queue.async {
            do { try d.lockForConfiguration() } catch { return }
            d.setExposureModeCustom(duration: t, iso: isoValue, completionHandler: nil)
            if d.isLockingFocusWithCustomLensPositionSupported { d.setFocusModeLocked(lensPosition: 1.0, completionHandler: nil) }
            d.unlockForConfiguration()
        }
    }
    private func endStack() {
        nightBusy = false
        UIApplication.shared.isIdleTimerDisabled = false
        if astroMode { setAuto("EXP"); setAuto("FOCUS") }
        setBias(nightSavedBias)
    }
    private func flatten(_ img: CIImage) -> CIImage {
        guard let cg = LookProcessor.photoContext.createCGImage(img, from: img.extent) else { return img }
        return CIImage(cgImage: cg)
    }
    private func alignFrame(_ f: CIImage, to ref: CIImage) -> CIImage {
        let s: CGFloat = 0.25
        let req = VNTranslationalImageRegistrationRequest(targetedCIImage: f.transformed(by: CGAffineTransform(scaleX: s, y: s)), options: [:])
        guard (try? VNImageRequestHandler(ciImage: ref.transformed(by: CGAffineTransform(scaleX: s, y: s)), options: [:]).perform([req])) != nil,
              let obs = req.results?.first as? VNImageTranslationAlignmentObservation else { return f }
        let t = obs.alignmentTransform
        return f.transformed(by: CGAffineTransform(translationX: t.tx / s, y: t.ty / s)).clampedToExtent().cropped(to: ref.extent)
    }
    private func stackFrame(_ frame: CIImage) {
        let astro = astroMode, trails = astroTrails
        nightCount += 1
        let n = nightCount
        let elapsed = Date().timeIntervalSince(nightStart)
        let target = astro ? astroSeconds : nightSeconds
        let done = nightStopRequested || n >= 600 || (target == 0 ? n >= nightDefaultFrames : elapsed >= Double(target))
        if let ref = nightRef, let acc = nightAcc {
            // Night is handheld: align each frame. Stars are shot on a tripod: no alignment (it would chase the stars).
            let f = astro ? frame : alignFrame(frame, to: ref)
            let merged: CIImage
            if astro && trails {
                let l = CIFilter.lightenBlendMode(); l.inputImage = f; l.backgroundImage = acc
                merged = (l.outputImage ?? acc).cropped(to: ref.extent)
            } else {
                let d = CIFilter.dissolveTransition(); d.inputImage = acc; d.targetImage = f; d.time = 1 / Float(n)
                merged = (d.outputImage ?? acc).cropped(to: ref.extent)
            }
            nightAcc = flatten(merged)
        } else { nightRef = frame; nightAcc = flatten(frame) }
        if !done { DispatchQueue.main.async { self.capture() } }          // next frame only after this one is merged: no backlog on long shoots
        DispatchQueue.main.async {
            self.message = done ? "Merging \(n) frames…"
                                : (target == 0 ? "Hold still · \(n)/\(self.nightDefaultFrames)"
                                               : "\(astro ? "Stars" : "Night") · \(min(Int(elapsed), target))/\(target)s · \(n) frames")
        }
        if done { finishStack() }
    }
    /// Tone for a stacked night-sky picture: noise reduction, the sky glow measured and removed (black sky), brighter stars with a soft glow.
    static func starTone(_ input: CIImage, darkness: Float, trails: Bool) -> CIImage {
        var acc = input
        if !trails {
            let nr = CIFilter.noiseReduction(); nr.inputImage = acc; nr.noiseLevel = 0.02; nr.sharpness = 0.4
            acc = nr.outputImage ?? acc
        }
        if darkness > 0 {
            // Measure the sky glow (the mean of the stacked picture; stars are tiny, so it is almost all background) and take it away.
            let avg = acc.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: acc.extent)])
            var px = [Float](repeating: 0, count: 4)
            LookProcessor.photoContext.render(avg, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
            let glow = 0.299 * px[0] + 0.587 * px[1] + 0.114 * px[2]
            let black = CGFloat(min(0.5, glow * (0.7 + 0.8 * darkness)))
            if black > 0.001 {
                let k = 1 / max(0.05, 1 - black)
                acc = acc.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputBiasVector": CIVector(x: -black * k, y: -black * k, z: -black * k, w: 0)])
            }
        }
        // Lift the dim end (faint stars live there) instead of adding contrast, which would crush them to black.
        let ex = CIFilter.exposureAdjust(); ex.inputImage = acc; ex.ev = trails ? 0.3 : (darkness > 0 ? 0.8 : 0.5)
        acc = ex.outputImage ?? acc
        let gm = CIFilter.gammaAdjust(); gm.inputImage = acc; gm.power = trails ? 0.85 : (darkness > 0 ? 0.7 : 0.9)
        acc = gm.outputImage ?? acc
        let cc = CIFilter.colorControls(); cc.inputImage = acc; cc.saturation = 1.1
        acc = cc.outputImage ?? acc
        if !trails, darkness > 0 {
            // A soft glow around the brightest points makes the stars pop against the dark sky.
            let bloom = CIFilter.bloom(); bloom.inputImage = acc
            bloom.radius = Float(max(acc.extent.width, acc.extent.height) / 700); bloom.intensity = 0.25 + 0.35 * darkness
            acc = (bloom.outputImage ?? acc).cropped(to: acc.extent)
        }
        return acc
    }
    private func finishStack() {
        guard var acc = nightAcc else { DispatchQueue.main.async { self.endStack() }; return }
        let astro = astroMode, trails = astroTrails, n = nightCount
        nightAcc = nil; nightRef = nil
        if astro {
            acc = CameraEngine.starTone(acc, darkness: astroSkyDarkness, trails: trails)
            // Constellation lines and names drawn onto the finished photo (portrait shots only — the map is laid out for an upright phone).
            if let sky = astroSkySnapshot, acc.extent.height >= acc.extent.width,
               let overlay = SkyRender.overlayImage(frame: sky, size: acc.extent.size), let overlayCI = CIImage(image: overlay) {
                acc = overlayCI.composited(over: acc).cropped(to: acc.extent)
            }
        } else {
            let nr = CIFilter.noiseReduction(); nr.inputImage = acc; nr.noiseLevel = 0.012; nr.sharpness = 0.55
            acc = nr.outputImage ?? acc
            let hs = CIFilter.highlightShadowAdjust(); hs.inputImage = acc; hs.shadowAmount = 0.55; hs.highlightAmount = 0.9
            acc = hs.outputImage ?? acc
            let ex = CIFilter.exposureAdjust(); ex.inputImage = acc; ex.ev = 0.25
            acc = ex.outputImage ?? acc
        }
        finishStill(acc, savedMessage: astro ? (trails ? "Star trails saved · \(n) frames" : "Star photo saved · \(n) frames") : "Night photo saved · \(n) frames")
        DispatchQueue.main.async { self.endStack() }
    }

    // MARK: Light trails
    func startTrail() {
        guard running, !isTrailing, !isRecording else { return }
        trailSavedBias = exposureBias
        if !trailAverage { setBias(min(exposureBias, -1)) }
        UIApplication.shared.isIdleTimerDisabled = true
        trailAccum = nil; trailCounter = 0
        trailElapsed = 0; isTrailing = true; trailActive = true
        message = trailAverage ? "Long exposure · keep the phone still" : "Light trail · keep the phone still"
        trailTimer?.invalidate()
        trailTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.trailElapsed += 1
            if self.trailElapsed >= self.trailDuration { self.stopTrail() }
        }
    }
    func stopTrail() {
        guard isTrailing else { return }
        trailTimer?.invalidate(); trailTimer = nil
        trailActive = false; isTrailing = false
        UIApplication.shared.isIdleTimerDisabled = false
        setBias(trailSavedBias)
        let average = trailAverage
        message = average ? "Processing long exposure…" : "Processing light trail…"
        frameQueue.async {
            let acc = self.trailAccum; self.trailAccum = nil
            DispatchQueue.main.async { self.displayHandler?(nil) }
            guard let acc else { DispatchQueue.main.async { self.message = "No frames captured" }; return }
            self.finishStill(acc, savedMessage: average ? "Long exposure saved" : "Light trail saved")
        }
    }
    private func handleTrailFrame(_ buffer: CVPixelBuffer) {
        var image = CIImage(cvPixelBuffer: buffer).oriented(frameOrientation())
        let scale = min(1, 2000 / max(image.extent.width, image.extent.height))
        if scale < 1 { image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        var merged = image
        if let acc = trailAccum {
            if trailAverage {
                let d = CIFilter.dissolveTransition()
                d.inputImage = acc; d.targetImage = image; d.time = 1 / Float(trailCounter + 1)
                merged = d.outputImage?.cropped(to: image.extent) ?? image
            } else {
                let f = CIFilter.lightenBlendMode()
                f.inputImage = image; f.backgroundImage = acc
                merged = f.outputImage?.cropped(to: image.extent) ?? image
            }
        }
        guard let cg = LookProcessor.context.createCGImage(merged, from: image.extent) else { return }
        trailAccum = CIImage(cgImage: cg)
        trailCounter += 1
        if trailCounter % 3 == 0 { DispatchQueue.main.async { [weak self] in if self?.trailActive == true { self?.displayHandler?(cg) } } }
    }

    func addFrame(_ image: UIImage, info: String) -> UIImage {
        let w = image.size.width, h = image.size.height
        let side = w * 0.04, bottom = w * 0.13
        let size = CGSize(width: w + side * 2, height: h + side + bottom)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(x: side, y: side, width: w, height: h))
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: w * 0.034, weight: .heavy), .foregroundColor: UIColor.black]
            let detail: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: w * 0.022, weight: .medium), .foregroundColor: UIColor.darkGray]
            ("LUMEN" as NSString).draw(at: CGPoint(x: side, y: h + side + bottom * 0.28), withAttributes: title)
            (info as NSString).draw(at: CGPoint(x: side, y: h + side + bottom * 0.62), withAttributes: detail)
        }
    }

    /// Three shots at -2 / 0 / +2 EV (works in auto and manual exposure), then restores your bias.
    func bracket(_ evs: [Float] = [-2, 0, 2]) {
        let original = exposureBias
        if hdrMerge { hdrFrames = []; hdrCollecting = true; rawEnabled = false; message = "HDR · hold still" }
        for (i, ev) in evs.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.0) {
                self.setBias(ev)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { self.capture() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(evs.count) * 1.0 + 0.3) { self.setBias(original) }
    }

    func burst(count: Int = 5) {
        for i in 0..<count { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) { self.capture() } }
    }

    func flipCamera() {
        queue.async {
            guard let oldInput = self.cameraInput, !self.isRecording else { return }
            let toFront = !self.isFront
            let target: AVCaptureDevice? = toFront ? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) : self.wideCamera
            guard let target, let newInput = try? AVCaptureDeviceInput(device: target) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(oldInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput); self.cameraInput = newInput; self.device = target
            } else { self.session.addInput(oldInput); self.session.commitConfiguration(); return }
            self.session.commitConfiguration()
            self.selectHighResFormat(on: target)
            self.refreshPhotoDimensions(target)
            if (try? target.lockForConfiguration()) != nil { target.videoZoomFactor = 1; target.unlockForConfiguration() }
            let flash = self.photoOutput.supportedFlashModes.contains(.on)
            let raw = self.photoOutput.isAppleProRAWSupported || !self.photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
            DispatchQueue.main.async {
                self.isFront = toFront; self.zoom = 1; self.flashAvailable = flash
                self.supportsRAW = raw; self.supportsMacro = !toFront && self.ultraWideCamera != nil
                if toFront { self.rawEnabled = false }
            }
        }
    }
}

/// Histogram values, observed only by the histogram view.
final class HistogramModel: ObservableObject {
    struct Data { var luma: [Float] = [], r: [Float] = [], g: [Float] = [], b: [Float] = [], hi: Float = 0, lo: Float = 0 }
    @Published var data = Data()
}

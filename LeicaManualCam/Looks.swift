import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// A film / camera-brand colour recipe. Applied to saved photos by `LookProcessor`
/// and approximated on the live preview by an overlay derived from the same numbers.
struct LookSpec {
    var sat: Float = 1
    var contrast: Float = 1
    var brightness: Float = 0
    /// White-point target in Kelvin. Below 6500 = warmer, above = cooler.
    var kelvin: Float = 6500
    /// Per-channel multiplier (highlight tint).
    var gain = SIMD3<Float>(1, 1, 1)
    /// Per-channel offset (lifted / tinted shadows, fade).
    var bias = SIMD3<Float>(0, 0, 0)
    var grain: Float = 0
    var vignette: Float = 0
    var halation: Float = 0
    var sepia: Float = 0
    /// Special screen effect: 1 pixel, 2 frosted glass, 3 CRT, 4 neon-green glow.
    var fx: Int = 0
    var swatch: Color = .gray
}

enum Look: String, CaseIterable {
    case original = "ORIGINAL"
    case custom = "MY LOOK"
    case menuClean = "MENU CLEAN"
    case foodFresh = "FOOD FRESH"
    case foodWarm = "FOOD WARM"
    case foodMoody = "FOOD MOODY"
    case foodRustic = "FOOD RUSTIC"
    case storm = "STORM"
    case misty = "MISTY"
    case vividSky = "VIVID SKY"
    case alpine = "ALPINE"
    case sunkissed = "SUNKISSED"
    case sunset = "SUNSET"
    case blush = "BLUSH"
    case pastel = "PASTEL DREAM"
    case airy = "BRIGHT & AIRY"
    case highKey = "HIGH KEY"
    case matte = "MATTE"
    case moody = "MOODY"
    case tealOrange = "TEAL & ORANGE"
    case neon = "NEON NIGHT"
    case vintage70 = "VINTAGE 70s"
    case digicam = "DIGICAM FLASH"
    case crossProcess = "CROSS PROCESS"
    case desert = "DESERT"
    case autumn = "AUTUMN"
    case forest = "FOREST"
    case beach = "BEACH DAY"
    case frost = "FROST"
    case blueHour = "BLUE HOUR"
    case midnight = "MIDNIGHT"
    case drama = "DRAMA B&W"
    case hasselblad = "HASSELBLAD"
    case leica = "LEICA"
    case leicaMono = "LEICA MONOCHROM"
    case classicChrome = "CLASSIC CHROME"
    case velvia = "VELVIA"
    case provia = "PROVIA"
    case astia = "ASTIA"
    case classicNeg = "CLASSIC NEG"
    case eterna = "ETERNA"
    case acros = "ACROS"
    case sCinetone = "S-CINETONE"
    case canon = "CANON"
    case nikon = "NIKON"
    case vlog = "V-LOG"
    case arri = "ARRI ALEXA"
    case red = "RED"
    case blackmagic = "BMD FILM"
    case pentax = "PENTAX REVERSAL"
    case ricoh = "RICOH GR"
    case olympus = "OLYMPUS"
    case polaroid = "POLAROID"
    case portra = "PORTRA"
    case ektar = "EKTAR"
    case gold200 = "GOLD 200"
    case triX = "TRI-X"
    case vision3 = "VISION3 500T"
    case agfa = "AGFA VISTA"
    case hp5 = "HP5"
    case cinestill = "CINESTILL 800T"
    case lomo = "LOMO"
    case indoorTrue = "INDOOR TRUE"
    case indoorCozy = "INDOOR COZY"
    case pixel = "PIXEL"
    case glass = "GLASS"
    case crt = "CRT"
    case filmGrain = "FILM GRAIN"
    case neonGreen = "NEON GREEN"
    case mono = "MONO"

    var blurb: String {
        switch self {
        case .original: return "No colour processing"
        case .custom: return "Your own recipe — adjust the sliders below"
        case .menuClean: return "True whites and honest colour — ideal for delivery-app menu photos"
        case .foodFresh: return "Bright, juicy and appetising with a touch of warmth"
        case .foodWarm: return "Warm, cosy and golden — pizza, burgers, comfort food"
        case .foodMoody: return "Dark, rich and dramatic — fine-dining style with deep shadows"
        case .foodRustic: return "Earthy, matte and homely — wooden tables and bakery vibes"
        case .storm: return "Dark steel-blue skies, hard contrast and heavy drama"
        case .misty: return "Soft, hazy and cool — fog, drizzle and quiet mornings"
        case .vividSky: return "Deep blue skies and punchy colour — rainbows, clouds, open views"
        case .alpine: return "Crisp, clean and cool — mountains, snow and thin air"
        case .sunkissed: return "Warm golden glow, lifted shadows, soft sun-baked skin"
        case .sunset: return "Deep orange and pink, rich warm highlights"
        case .blush: return "Rosy, soft and flattering with a gentle glow"
        case .pastel: return "Dreamy, low-contrast pastels with a soft haze"
        case .airy: return "Bright, clean and light — lifted exposure"
        case .highKey: return "Very bright and soft, minimal shadows"
        case .matte: return "Faded blacks, muted colour, modern editorial feel"
        case .moody: return "Dark, desaturated and cool with heavy vignette"
        case .tealOrange: return "Blockbuster split: warm skin, teal shadows"
        case .neon: return "Electric magenta and blue with a night-city glow"
        case .vintage70: return "Warm faded 70s print with grain and sepia"
        case .digicam: return "Early-2000s flash digicam: punchy, grainy, blown highlights"
        case .crossProcess: return "Shifted greens and blues, high contrast lab look"
        case .desert: return "Dry, golden and dusty with warm shadows"
        case .autumn: return "Rich oranges, golden leaves, warm contrast"
        case .forest: return "Deep natural greens, cool shade, calm tone"
        case .beach: return "Bright sky blues, clean whites, summery"
        case .frost: return "Icy cool tones, clean and crisp"
        case .blueHour: return "Twilight blues with soft contrast"
        case .midnight: return "Deep indigo night mood, dark and cinematic"
        case .drama: return "Hard-contrast black and white with deep vignette"
        case .hasselblad: return "Natural skin tones, smooth gradients, soft contrast, slightly warm"
        case .leica: return "Rich contrast, deep blacks, slightly desaturated, filmic and moody"
        case .leicaMono: return "High-contrast black and white with strong grain"
        case .classicChrome: return "Muted documentary look, deep blues, soft greens"
        case .velvia: return "Vivid, saturated colour for landscapes"
        case .provia: return "Neutral, balanced, true to life"
        case .astia: return "Soft contrast, gentle flattering skin tones"
        case .classicNeg: return "Retro, punchy teal and orange shadows"
        case .eterna: return "Cinematic, low saturation, made for video"
        case .acros: return "Fine-grain black and white"
        case .sCinetone: return "Cinematic, soft highlights, warm skin"
        case .canon: return "Warm, creamy skin tones, slightly orange and pink"
        case .nikon: return "Neutral, crisp, slightly cool and clean"
        case .vlog: return "Flat cinematic base with wide dynamic range"
        case .arri: return "Film-like highlight roll-off and natural colour"
        case .red: return "Sharp, high-detail, punchy contrast"
        case .blackmagic: return "Rich, organic cinema look"
        case .pentax: return "Strong saturation and contrast, slide-film feel"
        case .ricoh: return "High-contrast street look with deep tones"
        case .olympus: return "Bright, punchy, saturated colour"
        case .polaroid: return "Faded, warm, vintage instant film"
        case .portra: return "Soft, pastel and warm, great for portraits"
        case .ektar: return "Ultra-saturated, fine grain"
        case .gold200: return "Nostalgic warm yellows"
        case .triX: return "Classic gritty black and white"
        case .vision3: return "Cinematic tungsten film look"
        case .agfa: return "Warm vintage tones with a magenta tint"
        case .hp5: return "Classic black and white"
        case .cinestill: return "Night look with red halation glow around lights"
        case .lomo: return "Heavy vignette and cross-processed colour"
        case .indoorTrue: return "Removes the orange bulb cast so walls and skin look natural, and lifts dim rooms"
        case .indoorCozy: return "Keeps warm lamp light but cleans the colour and brightens the room"
        case .pixel: return "Blocky 8-bit pixels with a limited colour palette"
        case .glass: return "Frosted, translucent glass with a soft colour glow"
        case .crt: return "Old TV: scanlines, dark edges and a glowing screen"
        case .filmGrain: return "Fine film noise over everything"
        case .neonGreen: return "Dark scene with glowing green edges, like a hacker terminal"
        case .mono: return "Black and white with higher contrast, no distractions"
        }
    }

    var spec: LookSpec {
        func v(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { SIMD3(r, g, b) }
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch self {
        case .original: return LookSpec(swatch: c(0.40, 0.42, 0.45))
        case .custom:
            let d = UserDefaults.standard
            func f(_ k: String, _ def: Double) -> Float { d.object(forKey: k) == nil ? Float(def) : Float(d.double(forKey: k)) }
            return LookSpec(sat: f("cl_sat", 1), contrast: f("cl_con", 1), brightness: f("cl_br", 0), kelvin: f("cl_k", 6500), grain: f("cl_grain", 0), vignette: f("cl_vig", 0), swatch: c(0.62, 0.45, 0.72))
        case .menuClean: return LookSpec(sat: 1.12, contrast: 1.05, brightness: 0.03, swatch: c(0.92, 0.92, 0.90))
        case .foodFresh: return LookSpec(sat: 1.18, contrast: 1.08, brightness: 0.04, kelvin: 6200, gain: v(1.03, 1.0, 0.97), bias: v(0.01, 0.01, 0), swatch: c(0.90, 0.55, 0.25))
        case .foodWarm: return LookSpec(sat: 1.15, contrast: 1.1, kelvin: 5600, gain: v(1.06, 1.0, 0.92), vignette: 0.15, halation: 0.1, swatch: c(0.82, 0.45, 0.20))
        case .foodMoody: return LookSpec(sat: 1.05, contrast: 1.3, brightness: -0.07, kelvin: 5800, gain: v(1.04, 1.0, 0.94), grain: 0.1, vignette: 0.55, swatch: c(0.30, 0.18, 0.12))
        case .foodRustic: return LookSpec(sat: 0.92, contrast: 1.05, kelvin: 5500, gain: v(1.05, 1.0, 0.9), bias: v(0.03, 0.02, 0.01), grain: 0.2, vignette: 0.25, swatch: c(0.60, 0.45, 0.30))
        case .storm: return LookSpec(sat: 0.8, contrast: 1.3, brightness: -0.06, kelvin: 7400, gain: v(0.96, 1.0, 1.06), grain: 0.1, vignette: 0.4, swatch: c(0.22, 0.27, 0.34))
        case .misty: return LookSpec(sat: 0.8, contrast: 0.8, brightness: 0.06, kelvin: 7200, gain: v(0.97, 1.0, 1.04), bias: v(0.03, 0.04, 0.05), halation: 0.25, swatch: c(0.70, 0.76, 0.80))
        case .vividSky: return LookSpec(sat: 1.35, contrast: 1.18, kelvin: 6800, gain: v(0.97, 1.0, 1.08), vignette: 0.15, swatch: c(0.15, 0.45, 0.85))
        case .alpine: return LookSpec(sat: 1.05, contrast: 1.15, brightness: 0.02, kelvin: 7000, gain: v(0.97, 1.0, 1.06), swatch: c(0.55, 0.72, 0.88))
        case .sunkissed: return LookSpec(sat: 1.1, contrast: 1.05, brightness: 0.03, kelvin: 5200, gain: v(1.06, 1.0, 0.9), bias: v(0.03, 0.015, 0), vignette: 0.1, halation: 0.25, swatch: c(0.95, 0.72, 0.38))
        case .sunset: return LookSpec(sat: 1.3, contrast: 1.12, kelvin: 4600, gain: v(1.1, 0.95, 0.9), bias: v(0.02, 0, 0.03), vignette: 0.2, swatch: c(0.90, 0.38, 0.25))
        case .blush: return LookSpec(sat: 0.95, contrast: 0.95, brightness: 0.04, kelvin: 5900, gain: v(1.05, 0.98, 1.0), bias: v(0.04, 0.01, 0.02), halation: 0.2, swatch: c(0.92, 0.62, 0.62))
        case .pastel: return LookSpec(sat: 0.75, contrast: 0.85, brightness: 0.08, gain: v(1.0, 1.0, 1.0), bias: v(0.04, 0.03, 0.05), halation: 0.3, swatch: c(0.78, 0.72, 0.88))
        case .airy: return LookSpec(sat: 0.95, contrast: 0.9, brightness: 0.1, bias: v(0.03, 0.03, 0.03), swatch: c(0.88, 0.92, 0.95))
        case .highKey: return LookSpec(sat: 0.9, contrast: 0.95, brightness: 0.12, bias: v(0.02, 0.02, 0.02), halation: 0.15, swatch: c(0.95, 0.95, 0.93))
        case .matte: return LookSpec(sat: 0.85, contrast: 0.88, bias: v(0.05, 0.05, 0.05), swatch: c(0.50, 0.48, 0.46))
        case .moody: return LookSpec(sat: 0.8, contrast: 1.25, brightness: -0.06, kelvin: 7000, gain: v(0.97, 1, 1.04), vignette: 0.5, swatch: c(0.18, 0.24, 0.30))
        case .tealOrange: return LookSpec(sat: 1.1, contrast: 1.2, gain: v(1.06, 1.0, 0.94), bias: v(0, 0.015, 0.03), swatch: c(0.20, 0.52, 0.55))
        case .neon: return LookSpec(sat: 1.35, contrast: 1.2, gain: v(1.05, 0.95, 1.1), bias: v(0.02, 0, 0.04), vignette: 0.3, halation: 0.4, swatch: c(0.75, 0.15, 0.80))
        case .vintage70: return LookSpec(sat: 0.9, contrast: 1.05, kelvin: 5400, gain: v(1.08, 0.98, 0.85), bias: v(0.03, 0.02, 0), grain: 0.35, vignette: 0.5, sepia: 0.15, swatch: c(0.68, 0.48, 0.28))
        case .digicam: return LookSpec(sat: 1.15, contrast: 1.25, brightness: 0.05, gain: v(1.02, 1, 1.04), grain: 0.4, vignette: 0.3, swatch: c(0.80, 0.82, 0.88))
        case .crossProcess: return LookSpec(sat: 1.3, contrast: 1.25, gain: v(0.95, 1.05, 1.12), bias: v(0.03, 0, 0), swatch: c(0.40, 0.70, 0.55))
        case .desert: return LookSpec(sat: 1.1, contrast: 1.1, kelvin: 5000, gain: v(1.07, 1.0, 0.85), swatch: c(0.78, 0.55, 0.32))
        case .autumn: return LookSpec(sat: 1.2, contrast: 1.1, kelvin: 5000, gain: v(1.08, 1.0, 0.88), vignette: 0.15, swatch: c(0.78, 0.38, 0.15))
        case .forest: return LookSpec(sat: 1.15, contrast: 1.05, kelvin: 6300, gain: v(0.97, 1.06, 0.95), vignette: 0.2, swatch: c(0.16, 0.38, 0.22))
        case .beach: return LookSpec(sat: 1.2, contrast: 1.05, brightness: 0.04, kelvin: 6800, gain: v(0.98, 1.02, 1.05), swatch: c(0.30, 0.65, 0.80))
        case .frost: return LookSpec(sat: 0.85, contrast: 1.05, brightness: 0.03, kelvin: 8200, gain: v(0.95, 1.0, 1.08), swatch: c(0.62, 0.78, 0.90))
        case .blueHour: return LookSpec(sat: 1.0, contrast: 1.1, kelvin: 8800, gain: v(0.93, 0.99, 1.1), vignette: 0.2, swatch: c(0.22, 0.34, 0.62))
        case .midnight: return LookSpec(sat: 0.9, contrast: 1.2, brightness: -0.05, kelvin: 9000, gain: v(0.9, 0.98, 1.12), vignette: 0.5, swatch: c(0.10, 0.12, 0.30))
        case .drama: return LookSpec(sat: 0, contrast: 1.5, brightness: -0.05, grain: 0.3, vignette: 0.6, swatch: c(0.08, 0.08, 0.08))
        case .hasselblad: return LookSpec(sat: 0.95, contrast: 0.96, brightness: 0.01, kelvin: 6100, gain: v(1.01, 1, 0.98), bias: v(0.01, 0.01, 0.008), swatch: c(0.62, 0.52, 0.40))
        case .leica: return LookSpec(sat: 0.85, contrast: 1.2, brightness: -0.03, kelvin: 6200, gain: v(1.02, 1, 0.97), grain: 0.15, vignette: 0.35, swatch: c(0.42, 0.30, 0.22))
        case .leicaMono: return LookSpec(sat: 0, contrast: 1.32, brightness: -0.02, grain: 0.5, vignette: 0.3, swatch: c(0.20, 0.20, 0.20))
        case .classicChrome: return LookSpec(sat: 0.78, contrast: 1.12, brightness: -0.02, gain: v(0.97, 1, 1.04), bias: v(0, 0.005, 0.012), grain: 0.1, vignette: 0.15, swatch: c(0.30, 0.40, 0.45))
        case .velvia: return LookSpec(sat: 1.5, contrast: 1.15, kelvin: 6400, swatch: c(0.75, 0.25, 0.20))
        case .provia: return LookSpec(sat: 1.05, contrast: 1.04, swatch: c(0.45, 0.50, 0.48))
        case .astia: return LookSpec(sat: 0.95, contrast: 0.92, kelvin: 6200, gain: v(1.02, 1, 0.99), bias: v(0.01, 0.01, 0.01), swatch: c(0.75, 0.60, 0.55))
        case .classicNeg: return LookSpec(sat: 1.1, contrast: 1.15, kelvin: 6300, gain: v(1.06, 0.98, 0.94), bias: v(0, 0.015, 0.022), grain: 0.2, swatch: c(0.25, 0.50, 0.50))
        case .eterna: return LookSpec(sat: 0.7, contrast: 0.9, brightness: 0.02, gain: v(0.98, 1, 1.02), bias: v(0.01, 0.015, 0.02), swatch: c(0.40, 0.48, 0.52))
        case .acros: return LookSpec(sat: 0, contrast: 1.2, grain: 0.3, swatch: c(0.50, 0.50, 0.50))
        case .sCinetone: return LookSpec(sat: 0.92, contrast: 0.95, kelvin: 6000, gain: v(1.03, 1, 0.97), bias: v(0.015, 0.012, 0.01), swatch: c(0.70, 0.55, 0.42))
        case .canon: return LookSpec(sat: 1.05, brightness: 0.02, kelvin: 5900, gain: v(1.04, 1, 0.99), bias: v(0.01, 0.005, 0.008), swatch: c(0.85, 0.55, 0.45))
        case .nikon: return LookSpec(sat: 1.0, contrast: 1.08, kelvin: 6800, swatch: c(0.45, 0.55, 0.65))
        case .vlog: return LookSpec(sat: 0.6, contrast: 0.72, brightness: 0.06, bias: v(0.03, 0.03, 0.03), swatch: c(0.60, 0.60, 0.58))
        case .arri: return LookSpec(sat: 0.95, contrast: 0.98, kelvin: 6300, gain: v(1.01, 1, 0.99), vignette: 0.1, swatch: c(0.55, 0.50, 0.42))
        case .red: return LookSpec(sat: 1.1, contrast: 1.22, swatch: c(0.70, 0.18, 0.15))
        case .blackmagic: return LookSpec(sat: 0.92, contrast: 1.05, kelvin: 6200, gain: v(1.02, 1, 0.98), grain: 0.1, swatch: c(0.45, 0.38, 0.32))
        case .pentax: return LookSpec(sat: 1.35, contrast: 1.25, kelvin: 6300, swatch: c(0.62, 0.30, 0.15))
        case .ricoh: return LookSpec(sat: 0.9, contrast: 1.3, brightness: -0.04, grain: 0.25, vignette: 0.2, swatch: c(0.25, 0.25, 0.27))
        case .olympus: return LookSpec(sat: 1.25, contrast: 1.1, brightness: 0.03, swatch: c(0.90, 0.55, 0.10))
        case .polaroid: return LookSpec(sat: 0.8, contrast: 0.9, brightness: 0.03, kelvin: 5700, gain: v(1.04, 1, 0.94), bias: v(0.03, 0.025, 0.01), grain: 0.25, vignette: 0.5, swatch: c(0.80, 0.70, 0.55))
        case .portra: return LookSpec(sat: 0.85, contrast: 0.92, brightness: 0.03, kelvin: 5900, gain: v(1.03, 1, 0.98), bias: v(0.025, 0.02, 0.015), swatch: c(0.88, 0.72, 0.62))
        case .ektar: return LookSpec(sat: 1.45, contrast: 1.18, kelvin: 6300, grain: 0.12, swatch: c(0.80, 0.20, 0.18))
        case .gold200: return LookSpec(sat: 1.1, contrast: 1.05, kelvin: 5300, gain: v(1.05, 1, 0.88), grain: 0.2, vignette: 0.2, swatch: c(0.90, 0.70, 0.25))
        case .triX: return LookSpec(sat: 0, contrast: 1.35, grain: 0.7, vignette: 0.3, swatch: c(0.15, 0.15, 0.15))
        case .vision3: return LookSpec(sat: 0.9, contrast: 1.05, kelvin: 7400, gain: v(0.97, 1, 1.04), grain: 0.3, swatch: c(0.25, 0.40, 0.55))
        case .agfa: return LookSpec(sat: 1.1, contrast: 1.05, kelvin: 6000, gain: v(1.04, 0.97, 1.03), bias: v(0.015, 0, 0.015), grain: 0.2, swatch: c(0.70, 0.35, 0.50))
        case .hp5: return LookSpec(sat: 0, contrast: 1.12, grain: 0.45, swatch: c(0.35, 0.35, 0.35))
        case .cinestill: return LookSpec(sat: 1.0, contrast: 1.1, brightness: -0.02, kelvin: 7200, gain: v(0.98, 1, 1.04), grain: 0.3, vignette: 0.2, halation: 0.9, swatch: c(0.15, 0.30, 0.50))
        case .indoorTrue: return LookSpec(sat: 1.05, contrast: 1.06, brightness: 0.05, kelvin: 8200, bias: v(0, 0.005, 0.01), swatch: c(0.85, 0.82, 0.75))
        case .indoorCozy: return LookSpec(sat: 1.08, contrast: 1.04, brightness: 0.06, kelvin: 6900, gain: v(1.03, 1, 0.97), swatch: c(0.90, 0.72, 0.50))
        case .pixel: return LookSpec(sat: 1.25, contrast: 1.15, fx: 1, swatch: c(0.35, 0.75, 0.35))
        case .glass: return LookSpec(sat: 1.2, contrast: 0.92, brightness: 0.04, gain: v(1.02, 1.02, 1.06), fx: 2, swatch: c(0.65, 0.80, 0.95))
        case .crt: return LookSpec(sat: 1.15, contrast: 1.15, gain: v(0.95, 1.05, 0.98), vignette: 0.9, fx: 3, swatch: c(0.25, 0.45, 0.35))
        case .filmGrain: return LookSpec(sat: 0.95, contrast: 1.05, grain: 0.8, swatch: c(0.55, 0.52, 0.48))
        case .neonGreen: return LookSpec(sat: 0.2, contrast: 1.5, brightness: -0.22, gain: v(0.3, 0.85, 0.4), vignette: 0.6, fx: 4, swatch: c(0.1, 0.9, 0.3))
        case .mono: return LookSpec(sat: 0, contrast: 1.3, brightness: -0.02, swatch: c(0.5, 0.5, 0.5))
        case .lomo: return LookSpec(sat: 1.4, contrast: 1.3, brightness: -0.02, gain: v(1.06, 1, 0.92), bias: v(0, 0.02, 0.04), grain: 0.15, vignette: 1.4, swatch: c(0.55, 0.20, 0.55))
        }
    }

    /// Colour for a soft-light overlay on the live preview (0.5 grey = neutral).
    var previewTint: Color {
        let s = spec
        let warmth = (6500 - s.kelvin) / 6500
        let r = 0.5 + Double((s.gain.x - 1) * 5 + warmth * 0.6 + s.bias.x * 3)
        let g = 0.5 + Double((s.gain.y - 1) * 5 + s.bias.y * 3)
        let b = 0.5 + Double((s.gain.z - 1) * 5 - warmth * 0.6 + s.bias.z * 3)
        return Color(red: min(max(r, 0), 1), green: min(max(g, 0), 1), blue: min(max(b, 0), 1))
    }
}

enum LookProcessor {
    /// No intermediate caching: far less memory on 12/48 MP photos and steadier live preview.
    static let context = CIContext(options: [.cacheIntermediates: false])
    /// Saving photos uses its own low-priority context, so the live preview keeps getting the GPU while a shot is processed.
    static let photoContext = CIContext(options: [.cacheIntermediates: false, .priorityRequestLow: true])
    /// Extra grain / glow (0...1) added on top of whichever look is active.
    static var extraGrain: Float = 0
    static var extraHalation: Float = 0
    /// 0 off, 1 warm, 2 sun, 3 pink/violet
    static var extraLeak: Int = 0
    static var extraDust: Float = 0
    static var hasExtras: Bool { extraGrain > 0 || extraHalation > 0 || extraLeak > 0 || extraDust > 0 }

    static func leak(_ img: CIImage, kind: Int) -> CIImage {
        let e = img.extent
        func glow(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: (CGFloat, CGFloat, CGFloat, CGFloat)) -> CIImage {
            let f = CIFilter.radialGradient()
            f.center = CGPoint(x: e.minX + cx * e.width, y: e.minY + cy * e.height)
            f.radius0 = 0; f.radius1 = Float(r * max(e.width, e.height))
            f.color0 = CIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
            f.color1 = CIColor(red: c.0, green: c.1, blue: c.2, alpha: 0)
            return (f.outputImage ?? CIImage.empty()).cropped(to: e)
        }
        let layers: [CIImage]
        switch kind {
        case 1: layers = [glow(0.0, 0.85, 0.75, (1, 0.45, 0.12, 0.85)), glow(1.0, 0.1, 0.5, (1, 0.2, 0.1, 0.55))]
        case 2: layers = [glow(-0.1, 0.5, 0.9, (1, 0.78, 0.3, 0.8))]
        default: layers = [glow(1.0, 0.9, 0.8, (0.9, 0.2, 0.7, 0.8)), glow(0.0, 0.1, 0.5, (0.4, 0.3, 1, 0.5))]
        }
        var out = img
        for l in layers {
            let f = CIFilter.screenBlendMode(); f.inputImage = l; f.backgroundImage = out
            out = (f.outputImage ?? out).cropped(to: e)
        }
        return out
    }

    /// The "screen" looks: pixel art, frosted glass, CRT scanlines and a neon-green glow.
    static func screenEffect(_ fx: Int, _ img: CIImage) -> CIImage {
        let e = img.extent
        let big = max(e.width, e.height)
        switch fx {
        case 1:
            let px = CIFilter.pixellate(); px.inputImage = img; px.scale = Float(max(3, big / 110)); px.center = CGPoint(x: e.minX, y: e.minY)
            let post = CIFilter.colorPosterize(); post.inputImage = px.outputImage?.cropped(to: e) ?? img; post.levels = 7
            return post.outputImage?.cropped(to: e) ?? img
        case 2:
            let blur = img.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: big / 90]).cropped(to: e)
            let d = CIFilter.dissolveTransition(); d.inputImage = img; d.targetImage = blur; d.time = 0.7
            let frosted = d.outputImage?.cropped(to: e) ?? blur
            let veil = frosted.applyingFilter("CIColorMatrix", parameters: ["inputBiasVector": CIVector(x: 0.05, y: 0.05, z: 0.07, w: 0)])
            let bloom = CIFilter.bloom(); bloom.inputImage = veil; bloom.radius = Float(big / 60); bloom.intensity = 0.5
            return bloom.outputImage?.cropped(to: e) ?? veil
        case 3:
            let bloom = CIFilter.bloom(); bloom.inputImage = img; bloom.radius = Float(big / 150); bloom.intensity = 0.45
            let glowing = bloom.outputImage?.cropped(to: e) ?? img
            let stripes = CIFilter.stripesGenerator()
            stripes.center = .zero; stripes.width = Float(max(1.5, big / 320)); stripes.sharpness = 0.6
            stripes.color0 = CIColor(red: 1, green: 1, blue: 1); stripes.color1 = CIColor(red: 0.5, green: 0.5, blue: 0.5)
            let lines = (stripes.outputImage ?? CIImage.empty())
                .transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY)).cropped(to: e)
            let m = CIFilter.multiplyCompositing(); m.inputImage = lines; m.backgroundImage = glowing
            return m.outputImage?.cropped(to: e) ?? glowing
        default:
            let edges = img.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 5.0])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0.3, y: 0.6, z: 0.3, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)]).cropped(to: e)
            let screen = CIFilter.screenBlendMode(); screen.inputImage = edges; screen.backgroundImage = img
            let combined = screen.outputImage?.cropped(to: e) ?? img
            let bloom = CIFilter.bloom(); bloom.inputImage = combined; bloom.radius = Float(big / 90); bloom.intensity = 1.2
            return bloom.outputImage?.cropped(to: e) ?? combined
        }
    }

    static func dust(_ img: CIImage, amount: Float) -> CIImage {
        let e = img.extent
        guard let noise = CIFilter.randomGenerator().outputImage else { return img }
        let scale = max(1, e.width / 1400)
        let a = CGFloat(amount)
        // The generator's alpha is random too: flatten it over black first (un-premultiplying it blows the values up and turns the whole picture white).
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: e)
        let flat = noise.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: e).composited(over: black)
        let specks = flat
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 160 * a, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 160 * a, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 160 * a, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -154 * a, y: -154 * a, z: -154 * a, w: 1)])
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.7 * scale]).cropped(to: e)
        let f = CIFilter.screenBlendMode(); f.inputImage = specks; f.backgroundImage = img
        return (f.outputImage ?? img).cropped(to: e)
    }

    /// Every look applied to a small sample image (for the picker thumbnails).
    static func thumbnails(for sample: CIImage) -> [String: UIImage] {
        var out: [String: UIImage] = [:]
        let extent = sample.extent
        for look in Look.allCases {
            let graded = apply(look, to: sample, strength: 1)
            if let cg = context.createCGImage(graded, from: extent) { out[look.rawValue] = UIImage(cgImage: cg) }
        }
        return out
    }

    /// A built-in scene (sky, sun, hills, warm subject) used until the camera supplies a real frame.
    static func fallbackScene() -> CIImage {
        let size = CGSize(width: 220, height: 160)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let sky = CGGradient(colorsSpace: space, colors: [UIColor(red: 0.30, green: 0.55, blue: 0.85, alpha: 1).cgColor, UIColor(red: 0.98, green: 0.78, blue: 0.55, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height * 0.7), options: [])
            UIColor(red: 1, green: 0.93, blue: 0.7, alpha: 1).setFill(); c.fillEllipse(in: CGRect(x: 150, y: 24, width: 30, height: 30))
            UIColor(red: 0.18, green: 0.42, blue: 0.25, alpha: 1).setFill(); c.fillEllipse(in: CGRect(x: -40, y: 95, width: 200, height: 120))
            UIColor(red: 0.12, green: 0.30, blue: 0.20, alpha: 1).setFill(); c.fillEllipse(in: CGRect(x: 80, y: 110, width: 200, height: 110))
            UIColor(red: 0.85, green: 0.30, blue: 0.25, alpha: 1).setFill(); c.fill(CGRect(x: 40, y: 96, width: 26, height: 30))
            UIColor(red: 0.93, green: 0.74, blue: 0.62, alpha: 1).setFill(); c.fillEllipse(in: CGRect(x: 45, y: 78, width: 16, height: 18))
        }
        return CIImage(image: img) ?? CIImage(color: .gray).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Applies a look blended with the original (strength 0...1).
    static func apply(_ look: Look, to input: CIImage, strength: Float) -> CIImage {
        let graded = apply(look, to: input)
        guard strength < 0.99, look != .original else { return graded }
        let d = CIFilter.dissolveTransition()
        d.inputImage = input; d.targetImage = graded; d.time = max(0, strength)
        return (d.outputImage ?? graded).cropped(to: input.extent)
    }

    static func apply(_ look: Look, to input: CIImage) -> CIImage {
        let s = look.spec
        let extent = input.extent
        var img = input

        if s.kelvin != 6500 {
            let f = CIFilter.temperatureAndTint(); f.inputImage = img
            f.neutral = CIVector(x: 6500, y: 0); f.targetNeutral = CIVector(x: CGFloat(s.kelvin), y: 0)
            img = f.outputImage ?? img
        }
        let cc = CIFilter.colorControls(); cc.inputImage = img
        cc.saturation = s.sat; cc.contrast = s.contrast; cc.brightness = s.brightness
        img = cc.outputImage ?? img

        if s.gain != SIMD3<Float>(1, 1, 1) || s.bias != SIMD3<Float>(0, 0, 0) {
            let m = CIFilter.colorMatrix(); m.inputImage = img
            m.rVector = CIVector(x: CGFloat(s.gain.x), y: 0, z: 0, w: 0)
            m.gVector = CIVector(x: 0, y: CGFloat(s.gain.y), z: 0, w: 0)
            m.bVector = CIVector(x: 0, y: 0, z: CGFloat(s.gain.z), w: 0)
            m.biasVector = CIVector(x: CGFloat(s.bias.x), y: CGFloat(s.bias.y), z: CGFloat(s.bias.z), w: 0)
            img = m.outputImage ?? img
        }
        if s.sepia > 0 {
            let f = CIFilter.sepiaTone(); f.inputImage = img; f.intensity = s.sepia
            img = f.outputImage ?? img
        }
        let halationAmount = min(1, s.halation + LookProcessor.extraHalation)
        let grainAmount = min(1, s.grain + LookProcessor.extraGrain)
        if halationAmount > 0 {
            // Red glow around bright areas: bloom, tinted red, screened back over the image.
            let bloom = CIFilter.bloom(); bloom.inputImage = img
            bloom.radius = Float(max(extent.width, extent.height) / 220); bloom.intensity = halationAmount
            let glow = bloom.outputImage?.cropped(to: extent) ?? img
            let tint = CIFilter.colorMatrix(); tint.inputImage = glow
            tint.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            tint.gVector = CIVector(x: 0, y: 0.25, z: 0, w: 0)
            tint.bVector = CIVector(x: 0, y: 0, z: 0.15, w: 0)
            let screen = CIFilter.screenBlendMode()
            screen.inputImage = tint.outputImage ?? glow; screen.backgroundImage = img
            let mixed = screen.outputImage?.cropped(to: extent) ?? img
            let dissolve = CIFilter.dissolveTransition()
            dissolve.inputImage = img; dissolve.targetImage = mixed; dissolve.time = min(0.8, halationAmount * 0.7)
            img = dissolve.outputImage?.cropped(to: extent) ?? mixed
        }
        if LookProcessor.extraLeak > 0 { img = LookProcessor.leak(img, kind: LookProcessor.extraLeak) }
        if LookProcessor.extraDust > 0 { img = LookProcessor.dust(img, amount: LookProcessor.extraDust) }
        if s.vignette > 0 {
            let f = CIFilter.vignette(); f.inputImage = img
            f.intensity = s.vignette; f.radius = Float(max(extent.width, extent.height) / 900 + 1)
            img = f.outputImage ?? img
        }
        if s.fx != 0 { img = LookProcessor.screenEffect(s.fx, img) }
        if grainAmount > 0, let noise = CIFilter.randomGenerator().outputImage {
            let scale = max(1, extent.width / 2400)
            let mono = CIFilter.colorControls(); mono.inputImage = noise.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: extent)
            mono.saturation = 0; mono.contrast = grainAmount * 0.9
            if let grainImg = mono.outputImage {
                let blend = CIFilter.softLightBlendMode()
                blend.inputImage = grainImg; blend.backgroundImage = img
                img = blend.outputImage?.cropped(to: extent) ?? img
            }
        }
        return img.cropped(to: extent)
    }
}

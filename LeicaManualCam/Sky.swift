import SwiftUI
import CoreMotion
import CoreLocation

// MARK: - Catalogue (bright stars and the main constellation figures)

enum SkyCatalog {
    struct Star { let id: String; let name: String; let ra: Double /* hours */; let dec: Double /* degrees */; let mag: Double }
    struct Constellation { let name: String; let lines: [(String, String)] }

    static let stars: [Star] = [
        // Orion
        Star(id: "ori_bet", name: "Betelgeuse", ra: 5.919, dec: 7.407, mag: 0.5), Star(id: "ori_rig", name: "Rigel", ra: 5.242, dec: -8.202, mag: 0.13),
        Star(id: "ori_bel", name: "Bellatrix", ra: 5.419, dec: 6.350, mag: 1.64), Star(id: "ori_min", name: "Mintaka", ra: 5.533, dec: -0.299, mag: 2.2),
        Star(id: "ori_aln", name: "Alnilam", ra: 5.604, dec: -1.202, mag: 1.7), Star(id: "ori_alk", name: "Alnitak", ra: 5.679, dec: -1.943, mag: 1.74),
        Star(id: "ori_sai", name: "Saiph", ra: 5.796, dec: -9.670, mag: 2.07), Star(id: "ori_mei", name: "Meissa", ra: 5.585, dec: 9.934, mag: 3.5),
        // Ursa Major (Big Dipper)
        Star(id: "uma_dub", name: "Dubhe", ra: 11.062, dec: 61.751, mag: 1.8), Star(id: "uma_mer", name: "Merak", ra: 11.031, dec: 56.382, mag: 2.37),
        Star(id: "uma_pha", name: "Phecda", ra: 11.897, dec: 53.695, mag: 2.4), Star(id: "uma_meg", name: "Megrez", ra: 12.257, dec: 57.033, mag: 3.3),
        Star(id: "uma_ali", name: "Alioth", ra: 12.900, dec: 55.960, mag: 1.76), Star(id: "uma_miz", name: "Mizar", ra: 13.399, dec: 54.925, mag: 2.2),
        Star(id: "uma_alc", name: "Alkaid", ra: 13.792, dec: 49.313, mag: 1.85),
        // Ursa Minor
        Star(id: "umi_pol", name: "Polaris", ra: 2.530, dec: 89.264, mag: 1.98), Star(id: "umi_koc", name: "Kochab", ra: 14.845, dec: 74.156, mag: 2.1),
        Star(id: "umi_phe", name: "Pherkad", ra: 15.345, dec: 71.834, mag: 3.0), Star(id: "umi_yil", name: "Yildun", ra: 17.537, dec: 86.586, mag: 4.35),
        Star(id: "umi_eps", name: "", ra: 16.766, dec: 82.037, mag: 4.2), Star(id: "umi_zet", name: "", ra: 15.734, dec: 77.795, mag: 4.3),
        Star(id: "umi_eta", name: "", ra: 16.292, dec: 75.755, mag: 5.0),
        // Cassiopeia
        Star(id: "cas_sch", name: "Schedar", ra: 0.675, dec: 56.537, mag: 2.2), Star(id: "cas_cap", name: "Caph", ra: 0.153, dec: 59.150, mag: 2.3),
        Star(id: "cas_nav", name: "", ra: 0.945, dec: 60.717, mag: 2.5), Star(id: "cas_ruc", name: "Ruchbah", ra: 1.430, dec: 60.235, mag: 2.7),
        Star(id: "cas_seg", name: "", ra: 1.907, dec: 63.670, mag: 3.4),
        // Cygnus
        Star(id: "cyg_den", name: "Deneb", ra: 20.690, dec: 45.280, mag: 1.25), Star(id: "cyg_sad", name: "Sadr", ra: 20.370, dec: 40.257, mag: 2.2),
        Star(id: "cyg_alb", name: "Albireo", ra: 19.512, dec: 27.960, mag: 3.1), Star(id: "cyg_gie", name: "", ra: 20.770, dec: 33.970, mag: 2.5),
        Star(id: "cyg_del", name: "", ra: 19.750, dec: 45.131, mag: 2.9),
        // Lyra
        Star(id: "lyr_veg", name: "Vega", ra: 18.616, dec: 38.784, mag: 0.03), Star(id: "lyr_she", name: "", ra: 18.835, dec: 33.363, mag: 3.5),
        Star(id: "lyr_sul", name: "", ra: 18.982, dec: 32.690, mag: 3.3), Star(id: "lyr_del", name: "", ra: 18.909, dec: 36.899, mag: 4.3),
        Star(id: "lyr_zet", name: "", ra: 18.746, dec: 37.605, mag: 4.4),
        // Aquila
        Star(id: "aql_alt", name: "Altair", ra: 19.846, dec: 8.868, mag: 0.77), Star(id: "aql_tar", name: "Tarazed", ra: 19.771, dec: 10.613, mag: 2.7),
        Star(id: "aql_als", name: "", ra: 19.922, dec: 6.407, mag: 3.7), Star(id: "aql_del", name: "", ra: 19.425, dec: 3.115, mag: 3.4),
        // Scorpius
        Star(id: "sco_ant", name: "Antares", ra: 16.490, dec: -26.432, mag: 1.06), Star(id: "sco_sha", name: "Shaula", ra: 17.560, dec: -37.104, mag: 1.6),
        Star(id: "sco_sar", name: "Sargas", ra: 17.622, dec: -42.998, mag: 1.87), Star(id: "sco_dsc", name: "Dschubba", ra: 16.005, dec: -22.622, mag: 2.3),
        Star(id: "sco_acr", name: "", ra: 16.090, dec: -19.805, mag: 2.6), Star(id: "sco_eps", name: "", ra: 16.836, dec: -34.293, mag: 2.3),
        Star(id: "sco_kap", name: "", ra: 17.708, dec: -39.030, mag: 2.4), Star(id: "sco_les", name: "", ra: 17.512, dec: -37.296, mag: 2.7),
        Star(id: "sco_tau", name: "", ra: 16.598, dec: -28.216, mag: 2.8),
        // Sagittarius (the teapot)
        Star(id: "sgr_kau", name: "Kaus Australis", ra: 18.403, dec: -34.385, mag: 1.85), Star(id: "sgr_kme", name: "", ra: 18.350, dec: -29.828, mag: 2.7),
        Star(id: "sgr_kbo", name: "", ra: 18.466, dec: -25.422, mag: 2.8), Star(id: "sgr_nun", name: "Nunki", ra: 18.921, dec: -26.297, mag: 2.0),
        Star(id: "sgr_asc", name: "", ra: 19.043, dec: -29.880, mag: 2.6), Star(id: "sgr_aln", name: "", ra: 18.097, dec: -30.424, mag: 3.0),
        Star(id: "sgr_tau", name: "", ra: 19.116, dec: -27.670, mag: 3.3),
        // Leo
        Star(id: "leo_reg", name: "Regulus", ra: 10.139, dec: 11.967, mag: 1.35), Star(id: "leo_den", name: "Denebola", ra: 11.818, dec: 14.572, mag: 2.1),
        Star(id: "leo_alg", name: "Algieba", ra: 10.333, dec: 19.842, mag: 2.0), Star(id: "leo_zos", name: "", ra: 11.235, dec: 20.524, mag: 2.6),
        Star(id: "leo_che", name: "", ra: 11.237, dec: 15.430, mag: 3.3), Star(id: "leo_adh", name: "", ra: 10.278, dec: 23.417, mag: 3.4),
        Star(id: "leo_ras", name: "", ra: 9.879, dec: 26.007, mag: 3.9),
        // Gemini
        Star(id: "gem_cas", name: "Castor", ra: 7.577, dec: 31.888, mag: 1.58), Star(id: "gem_pol", name: "Pollux", ra: 7.755, dec: 28.026, mag: 1.14),
        Star(id: "gem_alh", name: "Alhena", ra: 6.629, dec: 16.399, mag: 1.9), Star(id: "gem_meb", name: "", ra: 6.732, dec: 25.131, mag: 3.0),
        Star(id: "gem_tej", name: "", ra: 6.383, dec: 22.514, mag: 2.9), Star(id: "gem_was", name: "", ra: 7.335, dec: 21.982, mag: 3.5),
        // Taurus
        Star(id: "tau_ald", name: "Aldebaran", ra: 4.599, dec: 16.509, mag: 0.85), Star(id: "tau_eln", name: "Elnath", ra: 5.438, dec: 28.608, mag: 1.65),
        Star(id: "tau_zet", name: "", ra: 5.627, dec: 21.143, mag: 3.0), Star(id: "tau_ain", name: "", ra: 4.477, dec: 19.180, mag: 3.5),
        Star(id: "tau_gam", name: "", ra: 4.330, dec: 15.628, mag: 3.6), Star(id: "tau_alc", name: "Pleiades", ra: 3.791, dec: 24.105, mag: 2.9),
        // Canis Major
        Star(id: "cma_sir", name: "Sirius", ra: 6.752, dec: -16.716, mag: -1.46), Star(id: "cma_mir", name: "", ra: 6.378, dec: -17.956, mag: 2.0),
        Star(id: "cma_wez", name: "", ra: 7.140, dec: -26.393, mag: 1.8), Star(id: "cma_adh", name: "Adhara", ra: 6.977, dec: -28.972, mag: 1.5),
        Star(id: "cma_alu", name: "", ra: 7.402, dec: -29.303, mag: 2.45), Star(id: "cma_fur", name: "", ra: 6.339, dec: -30.063, mag: 3.0),
        // Southern Cross and Centaurus
        Star(id: "cru_acr", name: "Acrux", ra: 12.443, dec: -63.099, mag: 0.76), Star(id: "cru_mim", name: "Mimosa", ra: 12.795, dec: -59.689, mag: 1.25),
        Star(id: "cru_gac", name: "Gacrux", ra: 12.519, dec: -57.113, mag: 1.6), Star(id: "cru_del", name: "", ra: 12.252, dec: -58.749, mag: 2.8),
        Star(id: "cen_rig", name: "Rigil Kent.", ra: 14.660, dec: -60.834, mag: -0.27), Star(id: "cen_had", name: "Hadar", ra: 14.064, dec: -60.373, mag: 0.6),
        Star(id: "cen_men", name: "", ra: 14.111, dec: -36.370, mag: 2.06),
        // Pegasus and Andromeda
        Star(id: "peg_mar", name: "Markab", ra: 23.079, dec: 15.205, mag: 2.5), Star(id: "peg_sch", name: "Scheat", ra: 23.063, dec: 28.083, mag: 2.4),
        Star(id: "peg_alg", name: "", ra: 0.220, dec: 15.184, mag: 2.8), Star(id: "and_alp", name: "Alpheratz", ra: 0.139, dec: 29.091, mag: 2.1),
        Star(id: "and_mir", name: "Mirach", ra: 1.162, dec: 35.621, mag: 2.1), Star(id: "and_alm", name: "", ra: 2.065, dec: 42.330, mag: 2.2),
        // Bootes, Virgo, Libra
        Star(id: "boo_arc", name: "Arcturus", ra: 14.261, dec: 19.182, mag: -0.05), Star(id: "boo_iza", name: "", ra: 14.750, dec: 27.074, mag: 2.4),
        Star(id: "boo_seg", name: "", ra: 14.535, dec: 38.308, mag: 3.0), Star(id: "boo_nek", name: "", ra: 15.032, dec: 40.391, mag: 3.5),
        Star(id: "boo_mup", name: "", ra: 13.911, dec: 18.398, mag: 2.7),
        Star(id: "vir_spi", name: "Spica", ra: 13.420, dec: -11.161, mag: 1.04), Star(id: "vir_por", name: "", ra: 12.694, dec: -1.449, mag: 2.7),
        Star(id: "vir_vin", name: "", ra: 13.036, dec: 10.959, mag: 2.8), Star(id: "vir_zav", name: "", ra: 11.845, dec: 1.765, mag: 3.6),
        Star(id: "lib_zeg", name: "", ra: 15.283, dec: -9.383, mag: 2.6), Star(id: "lib_zen", name: "", ra: 14.848, dec: -16.042, mag: 2.75),
        Star(id: "lib_bra", name: "", ra: 15.592, dec: -14.789, mag: 3.3),
        // Auriga, Canis Minor, Aries, Perseus and a few lone bright stars
        Star(id: "aur_cap", name: "Capella", ra: 5.278, dec: 45.998, mag: 0.08), Star(id: "aur_men", name: "", ra: 5.992, dec: 44.948, mag: 1.9),
        Star(id: "aur_has", name: "", ra: 4.950, dec: 33.166, mag: 2.7), Star(id: "aur_the", name: "", ra: 5.995, dec: 37.213, mag: 2.6),
        Star(id: "cmi_pro", name: "Procyon", ra: 7.655, dec: 5.225, mag: 0.34), Star(id: "cmi_gom", name: "", ra: 7.452, dec: 8.289, mag: 2.9),
        Star(id: "ari_ham", name: "Hamal", ra: 2.120, dec: 23.462, mag: 2.0), Star(id: "ari_she", name: "", ra: 1.911, dec: 20.808, mag: 2.6),
        Star(id: "per_mir", name: "Mirfak", ra: 3.405, dec: 49.861, mag: 1.8), Star(id: "per_alg", name: "Algol", ra: 3.136, dec: 40.956, mag: 2.1),
        Star(id: "psa_fom", name: "Fomalhaut", ra: 22.961, dec: -29.622, mag: 1.16), Star(id: "car_can", name: "Canopus", ra: 6.399, dec: -52.696, mag: -0.74),
        Star(id: "eri_ach", name: "Achernar", ra: 1.629, dec: -57.237, mag: 0.46), Star(id: "hya_alp", name: "Alphard", ra: 9.460, dec: -8.659, mag: 2.0)
    ]

    static let constellations: [Constellation] = [
        Constellation(name: "Orion", lines: [("ori_mei", "ori_bet"), ("ori_mei", "ori_bel"), ("ori_bet", "ori_alk"), ("ori_bel", "ori_min"), ("ori_min", "ori_aln"), ("ori_aln", "ori_alk"), ("ori_alk", "ori_sai"), ("ori_min", "ori_rig"), ("ori_rig", "ori_sai")]),
        Constellation(name: "Big Dipper", lines: [("uma_dub", "uma_mer"), ("uma_mer", "uma_pha"), ("uma_pha", "uma_meg"), ("uma_meg", "uma_dub"), ("uma_meg", "uma_ali"), ("uma_ali", "uma_miz"), ("uma_miz", "uma_alc")]),
        Constellation(name: "Little Dipper", lines: [("umi_pol", "umi_yil"), ("umi_yil", "umi_eps"), ("umi_eps", "umi_zet"), ("umi_zet", "umi_eta"), ("umi_eta", "umi_phe"), ("umi_phe", "umi_koc"), ("umi_koc", "umi_zet")]),
        Constellation(name: "Cassiopeia", lines: [("cas_cap", "cas_sch"), ("cas_sch", "cas_nav"), ("cas_nav", "cas_ruc"), ("cas_ruc", "cas_seg")]),
        Constellation(name: "Cygnus", lines: [("cyg_den", "cyg_sad"), ("cyg_sad", "cyg_alb"), ("cyg_del", "cyg_sad"), ("cyg_sad", "cyg_gie")]),
        Constellation(name: "Lyra", lines: [("lyr_veg", "lyr_zet"), ("lyr_zet", "lyr_del"), ("lyr_del", "lyr_sul"), ("lyr_sul", "lyr_she"), ("lyr_she", "lyr_zet")]),
        Constellation(name: "Aquila", lines: [("aql_tar", "aql_alt"), ("aql_alt", "aql_als"), ("aql_alt", "aql_del")]),
        Constellation(name: "Scorpius", lines: [("sco_acr", "sco_dsc"), ("sco_dsc", "sco_ant"), ("sco_ant", "sco_tau"), ("sco_tau", "sco_eps"), ("sco_eps", "sco_sar"), ("sco_sar", "sco_kap"), ("sco_kap", "sco_sha"), ("sco_sha", "sco_les")]),
        Constellation(name: "Sagittarius", lines: [("sgr_aln", "sgr_kme"), ("sgr_kme", "sgr_kbo"), ("sgr_kbo", "sgr_nun"), ("sgr_nun", "sgr_tau"), ("sgr_tau", "sgr_asc"), ("sgr_asc", "sgr_kau"), ("sgr_kau", "sgr_aln")]),
        Constellation(name: "Leo", lines: [("leo_reg", "leo_alg"), ("leo_alg", "leo_adh"), ("leo_adh", "leo_ras"), ("leo_alg", "leo_zos"), ("leo_zos", "leo_den"), ("leo_den", "leo_che"), ("leo_che", "leo_reg")]),
        Constellation(name: "Gemini", lines: [("gem_cas", "gem_meb"), ("gem_meb", "gem_tej"), ("gem_pol", "gem_was"), ("gem_was", "gem_alh")]),
        Constellation(name: "Taurus", lines: [("tau_zet", "tau_ald"), ("tau_ald", "tau_eln"), ("tau_ald", "tau_gam"), ("tau_ald", "tau_ain")]),
        Constellation(name: "Canis Major", lines: [("cma_mir", "cma_sir"), ("cma_sir", "cma_wez"), ("cma_wez", "cma_adh"), ("cma_wez", "cma_alu"), ("cma_adh", "cma_fur")]),
        Constellation(name: "Southern Cross", lines: [("cru_acr", "cru_gac"), ("cru_mim", "cru_del")]),
        Constellation(name: "Centaurus", lines: [("cen_rig", "cen_had"), ("cen_had", "cen_men")]),
        Constellation(name: "Pegasus", lines: [("peg_mar", "peg_sch"), ("peg_sch", "and_alp"), ("and_alp", "peg_alg"), ("peg_alg", "peg_mar")]),
        Constellation(name: "Andromeda", lines: [("and_alp", "and_mir"), ("and_mir", "and_alm")]),
        Constellation(name: "Boötes", lines: [("boo_arc", "boo_iza"), ("boo_iza", "boo_seg"), ("boo_seg", "boo_nek"), ("boo_arc", "boo_mup")]),
        Constellation(name: "Virgo", lines: [("vir_zav", "vir_por"), ("vir_por", "vir_spi"), ("vir_por", "vir_vin")]),
        Constellation(name: "Libra", lines: [("lib_zen", "lib_zeg"), ("lib_zeg", "lib_bra"), ("lib_bra", "lib_zen")]),
        Constellation(name: "Auriga", lines: [("aur_cap", "aur_men"), ("aur_men", "aur_the"), ("aur_the", "tau_eln"), ("tau_eln", "aur_has"), ("aur_has", "aur_cap")]),
        Constellation(name: "Canis Minor", lines: [("cmi_pro", "cmi_gom")]),
        Constellation(name: "Aries", lines: [("ari_ham", "ari_she")]),
        Constellation(name: "Perseus", lines: [("per_mir", "per_alg")])
    ]
}

// MARK: - Astronomy

enum SkyMath {
    /// Local sidereal time in degrees.
    static func lst(date: Date, longitude: Double) -> Double {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        var gmst = (280.46061837 + 360.98564736629 * (jd - 2451545.0)).truncatingRemainder(dividingBy: 360)
        if gmst < 0 { gmst += 360 }
        return gmst + longitude
    }
    /// Altitude and azimuth (north = 0°, east = 90°) in radians.
    static func altAz(raHours: Double, decDeg: Double, latDeg: Double, lstDeg: Double) -> (alt: Double, az: Double) {
        let h = (lstDeg - raHours * 15) * .pi / 180
        let dec = decDeg * .pi / 180, lat = latDeg * .pi / 180
        let alt = asin(sin(dec) * sin(lat) + cos(dec) * cos(lat) * cos(h))
        let az = atan2(-cos(dec) * sin(h), sin(dec) * cos(lat) - cos(dec) * sin(lat) * cos(h))
        return (alt, az)
    }
}

// MARK: - Live tracker (location + device attitude → where the stars are in the camera view)

final class SkyTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Dot { var p: CGPoint; var mag: Double; var name: String }
    struct Segment { var a: CGPoint; var b: CGPoint }
    struct Label { var p: CGPoint; var text: String }
    /// Points are in units of the sensor image's long side, measured from its centre (x right, y down).
    struct Frame { var dots: [Dot] = []; var segments: [Segment] = []; var labels: [Label] = []; var ready = false; var status = "Starting sky map…" }

    @Published private(set) var frame = Frame()
    /// Manual nudge (same units) so you can line the map up with a known star when the compass is a few degrees off.
    var offset = CGPoint.zero
    var fovProvider: () -> Double = { 65 }

    private let motion = CMMotionManager()
    private let manager = CLLocationManager()
    private var location: CLLocation?
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        location = manager.location
        guard motion.isDeviceMotionAvailable else { frame = Frame(status: "Motion sensors aren't available"); return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let reference: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        motion.deviceMotionUpdateInterval = 1.0 / 15
        motion.startDeviceMotionUpdates(using: reference, to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            self.update(m)
        }
    }
    func stop() {
        guard running else { return }
        running = false
        motion.stopDeviceMotionUpdates()
        manager.stopUpdatingLocation()
    }
    func snapshot() -> Frame? { frame.ready ? frame : nil }

    /// Reference-frame vector (x north, y west, z up) → device frame. CoreMotion's matrix can be read either way round;
    /// the measured gravity vector (ref: straight down) tells us which reading is right.
    static func toDevice(_ v: (Double, Double, Double), r: CMRotationMatrix, gravity g: (Double, Double, Double)) -> (Double, Double, Double) {
        let a = (-r.m13, -r.m23, -r.m33), b = (-r.m31, -r.m32, -r.m33)
        let refToDevice = (a.0 * g.0 + a.1 * g.1 + a.2 * g.2) >= (b.0 * g.0 + b.1 * g.1 + b.2 * g.2)
        return refToDevice
            ? (r.m11 * v.0 + r.m12 * v.1 + r.m13 * v.2, r.m21 * v.0 + r.m22 * v.1 + r.m23 * v.2, r.m31 * v.0 + r.m32 * v.1 + r.m33 * v.2)
            : (r.m11 * v.0 + r.m21 * v.1 + r.m31 * v.2, r.m12 * v.0 + r.m22 * v.1 + r.m32 * v.2, r.m13 * v.0 + r.m23 * v.1 + r.m33 * v.2)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { location = locations.last }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func update(_ m: CMDeviceMotion) {
        guard let location else { frame = Frame(status: "Allow location so the app knows which sky you're under"); return }
        let g = m.gravity
        if abs(g.x) > 0.55 { frame = Frame(status: "Hold the phone upright (portrait) for the sky map"); return }
        frame = SkyTracker.project(date: Date(), latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                   rotation: m.attitude.rotationMatrix, gravity: (g.x, g.y, g.z), fovDegrees: fovProvider(), offset: offset)
    }

    /// Pure projection of the catalogue into the camera view (testable without sensors).
    static func project(date: Date, latitude: Double, longitude: Double, rotation r: CMRotationMatrix, gravity: (Double, Double, Double),
                        fovDegrees: Double, offset: CGPoint) -> Frame {
        let lst = SkyMath.lst(date: date, longitude: longitude)
        let tanHalf = tan(fovDegrees * .pi / 180 / 2)
        var points: [String: CGPoint] = [:]
        var out = Frame(ready: true, status: "")
        for star in SkyCatalog.stars {
            let (alt, az) = SkyMath.altAz(raHours: star.ra, decDeg: star.dec, latDeg: latitude, lstDeg: lst)
            guard alt > -0.05 else { continue }
            // reference frame: x = north, y = west, z = up
            let d = toDevice((cos(alt) * cos(az), -cos(alt) * sin(az), sin(alt)), r: r, gravity: gravity)
            guard d.2 < -0.05 else { continue }                       // the camera looks along the device's -z axis
            let u = (d.0 / -d.2) / (2 * tanHalf) + Double(offset.x)
            let v = -(d.1 / -d.2) / (2 * tanHalf) + Double(offset.y)
            guard abs(u) < 1.2, abs(v) < 1.2 else { continue }
            let p = CGPoint(x: u, y: v)
            points[star.id] = p
            out.dots.append(Dot(p: p, mag: star.mag, name: star.name))
        }
        for c in SkyCatalog.constellations {
            var visible: [CGPoint] = []
            for (s1, s2) in c.lines {
                if let a = points[s1], let b = points[s2] { out.segments.append(Segment(a: a, b: b)); visible += [a, b] }
            }
            if visible.count >= 2 {
                let cx = visible.map { $0.x }.reduce(0, +) / CGFloat(visible.count)
                let cy = visible.map { $0.y }.reduce(0, +) / CGFloat(visible.count)
                out.labels.append(Label(p: CGPoint(x: cx, y: cy), text: c.name))
            }
        }
        return out
    }
}

// MARK: - Drawing

/// Live overlay on top of the viewfinder.
struct SkyOverlay: View {
    @ObservedObject var tracker: SkyTracker
    var body: some View {
        Canvas { ctx, size in
            let f = tracker.frame
            // The sensor image fills the card (aspect fill of a 3:4 portrait sensor).
            let side = size.width / size.height >= 0.75 ? size.width * 4 / 3 : size.height
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: size.width / 2 + p.x * side, y: size.height / 2 + p.y * side) }
            guard f.ready else {
                ctx.draw(Text(f.status).font(.system(size: 12, weight: .semibold)).foregroundColor(.white), at: CGPoint(x: size.width / 2, y: size.height * 0.2))
                return
            }
            var lines = Path()
            for s in f.segments { lines.move(to: pt(s.a)); lines.addLine(to: pt(s.b)) }
            ctx.stroke(lines, with: .color(.white.opacity(0.55)), lineWidth: 1)
            for d in f.dots {
                let r = max(1.6, 4.6 - d.mag * 1.0)
                let p = pt(d.p)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.95)))
                if d.mag < 1.7, !d.name.isEmpty {
                    ctx.draw(Text(d.name).font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.8)), at: CGPoint(x: p.x + 6, y: p.y - 8), anchor: .leading)
                }
            }
            for l in f.labels {
                ctx.draw(Text(l.text.uppercased()).font(.system(size: 11, weight: .bold)).foregroundColor(Color(red: 0.96, green: 0.84, blue: 0.55)), at: pt(l.p))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Draws the same map onto a finished photo (the sensor image: long side = height).
enum SkyRender {
    static func overlayImage(frame: SkyTracker.Frame, size: CGSize) -> UIImage? {
        guard frame.ready, size.height >= size.width else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let side = size.height, unit = size.height / 1400          // text and line sizes scale with the photo
        return UIGraphicsImageRenderer(size: size, format: format).image { r in
            let c = r.cgContext
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: size.width / 2 + p.x * side, y: size.height / 2 + p.y * side) }
            c.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor); c.setLineWidth(max(2, 1.6 * unit))
            for s in frame.segments { c.move(to: pt(s.a)); c.addLine(to: pt(s.b)); c.strokePath() }
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15 * unit, weight: .medium), .foregroundColor: UIColor.white.withAlphaComponent(0.85)]
            for d in frame.dots {
                let rad = max(2, (4.6 - d.mag) * 2.2 * unit), p = pt(d.p)
                c.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
                c.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
                if d.mag < 1.7, !d.name.isEmpty { (d.name as NSString).draw(at: CGPoint(x: p.x + rad + 6 * unit, y: p.y - 10 * unit), withAttributes: nameAttrs) }
            }
            let labelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 20 * unit, weight: .bold), .foregroundColor: UIColor(red: 0.96, green: 0.84, blue: 0.55, alpha: 1)]
            for l in frame.labels {
                let text = l.text.uppercased() as NSString, sz = text.size(withAttributes: labelAttrs), p = pt(l.p)
                text.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2), withAttributes: labelAttrs)
            }
        }
    }
}

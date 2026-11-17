import SwiftUI

/// Home-screen quick actions (press and hold the app icon), like the system Camera app.
final class QuickAction: ObservableObject {
    static let shared = QuickAction()
    /// The shortcut type waiting to be handled by the camera screen.
    @Published var pending: String?
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Launched from a quick action (app was not running)
        if let item = options.shortcutItem { QuickAction.shared.pending = item.type }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    // Quick action chosen while the app is already running in the background
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        QuickAction.shared.pending = shortcutItem.type
        completionHandler(true)
    }
}

@main
struct LeicaManualCamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { WindowGroup { CameraView() } }
}

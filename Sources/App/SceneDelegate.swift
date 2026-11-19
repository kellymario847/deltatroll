import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var overlay: OverlayHost?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }

        // 主界面：授权 + 状态控制台
        let root = MainView()
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .black
        window = UIWindow(windowScene: ws)
        window?.rootViewController = host
        window?.makeKeyAndVisible()

        // ESP 覆盖层常驻（初始隐藏，授权+利用成功后可呼出）
        overlay = OverlayHost(scene: ws)
        OverlayBridge.shared().overlay = overlay
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        overlay?.attachIfNeeded()
    }
}

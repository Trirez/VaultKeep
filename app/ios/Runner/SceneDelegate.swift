import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyOverlay: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard let window = self.window else { return }
    let overlay = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    overlay.frame = window.bounds
    overlay.tag = 9999
    window.addSubview(overlay)
    self.privacyOverlay = overlay
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    self.privacyOverlay?.removeFromSuperview()
    self.privacyOverlay = nil
  }
}

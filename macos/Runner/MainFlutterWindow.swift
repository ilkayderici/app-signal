import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Flutter şeffaf çizer; arkadaki bulanık cam görünür.
    flutterViewController.backgroundColor = .clear
    let windowFrame = self.frame
    self.contentViewController = GlassViewController(child: flutterViewController)
    self.setFrame(windowFrame, display: true)
    self.isOpaque = false
    self.backgroundColor = .clear

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerScreenChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Ekran kenarı için imleç konumu ve ana ekranın kullanılabilir alanı.
  /// Koordinatlar sol üst köşe başlangıçlı (window_manager ile aynı).
  private func registerScreenChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app_signal/screen", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let main = NSScreen.screens.first else {
        result(nil)
        return
      }
      let height = main.frame.height
      switch call.method {
      case "cursor":
        let p = NSEvent.mouseLocation
        result([p.x, height - p.y])
      case "visibleFrame":
        let f = main.visibleFrame
        result([f.minX, height - f.maxY, f.width, f.height])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Pencerenin arkasını bulanıklaştıran, köşeleri yuvarlak cam katman;
/// Flutter görünümü üstünde.
class GlassViewController: NSViewController {
  private let child: NSViewController

  init(child: NSViewController) {
    self.child = child
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    let glass = NSVisualEffectView()
    glass.material = .hudWindow
    glass.blendingMode = .behindWindow
    glass.state = .active
    glass.wantsLayer = true
    glass.layer?.cornerRadius = 14
    glass.layer?.masksToBounds = true
    view = glass

    addChild(child)
    child.view.frame = glass.bounds
    child.view.autoresizingMask = [.width, .height]
    glass.addSubview(child.view)
  }
}

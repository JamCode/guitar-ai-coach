import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "guitar_helper/build_info",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "getDistributionChannel" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(self?.distributionChannel() ?? "Release")
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// 通过 iOS 收据判断当前安装来源：TestFlight / App Store / Release。
  private func distributionChannel() -> String {
    #if DEBUG
      return "Debug"
    #else
      guard let receiptURL = Bundle.main.appStoreReceiptURL else {
        return "Release"
      }
      let receiptName = receiptURL.lastPathComponent.lowercased()
      if receiptName == "sandboxreceipt" {
        return "TestFlight"
      }
      if receiptName == "receipt" {
        return "App Store"
      }
      return "Release"
    #endif
  }
}

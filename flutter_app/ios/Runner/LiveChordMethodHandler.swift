import Foundation
import Flutter

/// Flutter `guitar_helper/live_chord` 通道处理器。
///
/// 当前实现接入本地 NNLS‑Chroma 引擎。
final class LiveChordMethodHandler {
  private let engine = LiveChordEngine()

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "Expected init args", details: nil))
        return
      }
      engine.configure(args: args)
      result(nil)
    case "process":
      result(engine.process(arguments: call.arguments))
    case "reset":
      engine.reset()
      result(nil)
    case "dispose":
      engine.reset()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

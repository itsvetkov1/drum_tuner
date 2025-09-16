import Flutter
import UIKit

public class DrumTuningPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(name: "drum_tuning_plugin/methods", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "drum_tuning_plugin/analysis", binaryMessenger: registrar.messenger())

    let instance = DrumTuningPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)

    // TODO: set up AVAudioEngine capture pipeline and connect to DSP core.
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      // TODO: start audio capture and analysis.
      result(nil)
    case "stop":
      // TODO: stop audio capture and analysis.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

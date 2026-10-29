import AuthenticationServices
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Google / Apple sign-in browser session (see [WebAuthSession]).
  private let webAuth = WebAuthSession()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The app runs under FlutterSceneDelegate, so there is no root view
    // controller to hang the channel off — register it on the engine instead.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WebAuthSession") {
      let channel = FlutterMethodChannel(
        name: "com.tommesalg.seller/web_auth",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.webAuth.handle(call: call, result: result)
      }
    }
  }
}

/// Runs the Google / Apple sign-in round-trip in `ASWebAuthenticationSession`,
/// which catches the `no.tommesalg.buyer://auth/vipps/...` return itself (the
/// buyer app's allowlisted return URL) without the scheme being registered here.
///
/// Dart: `authenticate({url, callbackScheme})` → the callback URL string, or a
/// FlutterError with code `CANCELED` | `BUSY` | `FAILED`.
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
  private var session: ASWebAuthenticationSession?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "authenticate" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let urlString = args["url"] as? String,
          let url = URL(string: urlString),
          let scheme = args["callbackScheme"] as? String else {
      result(FlutterError(code: "FAILED", message: "bad arguments", details: nil))
      return
    }
    if session != nil {
      result(FlutterError(code: "BUSY", message: nil, details: nil))
      return
    }

    let authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) {
      [weak self] callback, error in
      DispatchQueue.main.async {
        self?.session = nil
        if let callback = callback {
          result(callback.absoluteString)
        } else if let error = error as? ASWebAuthenticationSessionError,
                  error.code == .canceledLogin {
          result(FlutterError(code: "CANCELED", message: nil, details: nil))
        } else {
          result(FlutterError(code: "FAILED", message: error?.localizedDescription, details: nil))
        }
      }
    }
    authSession.presentationContextProvider = self
    // Share Safari cookies so users already signed in to Google / Apple skip
    // the password.
    authSession.prefersEphemeralWebBrowserSession = false
    session = authSession
    if !authSession.start() {
      session = nil
      result(FlutterError(code: "FAILED", message: "could not start", details: nil))
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    return windows.first(where: { $0.isKeyWindow }) ?? windows.first ?? ASPresentationAnchor()
  }
}

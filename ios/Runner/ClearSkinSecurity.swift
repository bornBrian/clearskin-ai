import DeviceCheck
import Flutter
import Security
import UIKit

/// iOS side of the `com.clearskinai/security` channel; the Dart side is
/// lib/services/security_service.dart and Android's is MainActivity.kt.
///
///  - deviceId: a random ID kept in the Keychain, which survives reinstalls,
///    so deleting the app doesn't reset free scans. Never used for ads.
///  - App Attest: proves to the server that a call comes from the genuine
///    ClearSkin app on a real iPhone (Apple's counterpart of Play Integrity).
///  - setSecure: with app lock on, covers the app in the app switcher.
///    iOS has no way to block screenshots.
final class ClearSkinSecurity: NSObject {
  static let shared = ClearSkinSecurity()

  private var channel: FlutterMethodChannel?
  private var privateWindow = false
  private var covers: [UIView] = []

  private let keyIdDefault = "cs.appAttest.keyId"
  private let attestedDefault = "cs.appAttest.attested"

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.clearskinai/security", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
    NotificationCenter.default.addObserver(
      self, selector: #selector(sceneWillDeactivate(_:)),
      name: UIScene.willDeactivateNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(sceneDidActivate(_:)),
      name: UIScene.didActivateNotification, object: nil)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "deviceId":
      result(installId())
    case "setSecure":
      privateWindow = args?["secure"] as? Bool ?? false
      result(nil)
    case "appAttestKey":
      guard let hash = (args?["clientDataHash"] as? String).flatMap(Data.init(hex:)) else {
        result(FlutterError(code: "bad_args", message: "clientDataHash required", details: nil))
        return
      }
      appAttestKey(clientDataHash: hash, retry: true, result: result)
    case "appAttestAssert":
      guard let keyId = args?["keyId"] as? String,
        let hash = (args?["clientDataHash"] as? String).flatMap(Data.init(hex:))
      else {
        result(FlutterError(code: "bad_args", message: "keyId and clientDataHash required", details: nil))
        return
      }
      appAttestAssert(keyId: keyId, clientDataHash: hash, result: result)
    case "appAttestConfirm":
      // The server accepted this key's attestation; assertions from now on.
      if let keyId = args?["keyId"] as? String,
        keyId == UserDefaults.standard.string(forKey: keyIdDefault)
      {
        UserDefaults.standard.set(keyId, forKey: attestedDefault)
      }
      result(nil)
    case "appAttestReset":
      resetAttestKey()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Install ID

  private func installId() -> String? {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.clearskinai.install-id",
      kSecAttrAccount as String: "id",
    ]
    if let id = readInstallId(base) { return id }
    let id = UUID().uuidString
    var add = base
    add[kSecValueData as String] = Data(id.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    switch SecItemAdd(add as CFDictionary, nil) {
    case errSecSuccess: return id
    case errSecDuplicateItem: return readInstallId(base)
    default: return nil
    }
  }

  private func readInstallId(_ base: [String: Any]) -> String? {
    var query = base
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  // MARK: App Attest

  /// The key to sign calls with. A new key comes back with its
  /// `attestation` for the server to register; an already registered key
  /// comes back alone. Nil where App Attest isn't available (simulator).
  private func appAttestKey(clientDataHash: Data, retry: Bool, result: @escaping FlutterResult) {
    let service = DCAppAttestService.shared
    guard service.isSupported else {
      result(nil)
      return
    }
    let defaults = UserDefaults.standard
    if let keyId = defaults.string(forKey: keyIdDefault),
      defaults.string(forKey: attestedDefault) == keyId
    {
      result(["keyId": keyId])
      return
    }
    let attest: (String) -> Void = { keyId in
      service.attestKey(keyId, clientDataHash: clientDataHash) { attestation, error in
        DispatchQueue.main.async {
          if let attestation {
            result(["keyId": keyId, "attestation": attestation.base64EncodedString()])
          } else if (error as? DCError)?.code == .invalidKey, retry {
            // A key can be attested only once; one attested earlier but
            // never registered (e.g. offline) is spent. Start over.
            self.resetAttestKey()
            self.appAttestKey(clientDataHash: clientDataHash, retry: false, result: result)
          } else {
            result(self.flutterError("attest_failed", error))
          }
        }
      }
    }
    if let keyId = defaults.string(forKey: keyIdDefault) {
      attest(keyId)
      return
    }
    service.generateKey { keyId, error in
      DispatchQueue.main.async {
        guard let keyId else {
          result(self.flutterError("keygen_failed", error))
          return
        }
        defaults.set(keyId, forKey: self.keyIdDefault)
        attest(keyId)
      }
    }
  }

  private func appAttestAssert(keyId: String, clientDataHash: Data, result: @escaping FlutterResult) {
    DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash) {
      assertion, error in
      DispatchQueue.main.async {
        if let assertion {
          result(assertion.base64EncodedString())
          return
        }
        if (error as? DCError)?.code == .invalidKey { self.resetAttestKey() }
        result(self.flutterError("assert_failed", error))
      }
    }
  }

  private func resetAttestKey() {
    UserDefaults.standard.removeObject(forKey: keyIdDefault)
    UserDefaults.standard.removeObject(forKey: attestedDefault)
  }

  private func flutterError(_ code: String, _ error: Error?) -> FlutterError {
    FlutterError(code: code, message: error?.localizedDescription, details: nil)
  }

  // MARK: App switcher cover

  @objc private func sceneWillDeactivate(_ note: Notification) {
    guard privateWindow, covers.isEmpty, let scene = note.object as? UIWindowScene else { return }
    for window in scene.windows {
      let cover = UIView(frame: window.bounds)
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      // #232321, the launch screen colour.
      cover.backgroundColor = UIColor(red: 0.137, green: 0.137, blue: 0.129, alpha: 1)
      window.addSubview(cover)
      covers.append(cover)
    }
  }

  @objc private func sceneDidActivate(_ note: Notification) {
    covers.forEach { $0.removeFromSuperview() }
    covers.removeAll()
  }
}

extension Data {
  /// Parses a hex string ("a1b2…"); nil if it isn't one.
  init?(hex: String) {
    guard hex.count % 2 == 0 else { return nil }
    var bytes = [UInt8]()
    bytes.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}

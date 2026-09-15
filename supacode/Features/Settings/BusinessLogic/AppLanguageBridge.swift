import Dependencies
import Foundation

/// Bridges the persisted `GlobalSettings.appLanguage` to the app-domain
/// `AppleLanguages` default that Foundation/AppKit consult at launch, and
/// records just enough ownership metadata to hand the key back when the user
/// returns to "system".
///
/// Ownership rules (docs/plans/2026-09-10-language-settings.md):
/// - The first switch from system to an explicit language records the
///   original non-managed value — including "the key did not exist" — before
///   writing the derived value.
/// - Returning to system only restores when the current domain value still
///   equals Prowl's most recent write; a value that no longer matches was
///   changed externally and is never overwritten in system mode.
/// - In explicit mode an externally changed value becomes the new
///   restore-to original before the derived value is written.
/// - Mere key presence never implies ownership; only a matching
///   `lastWritten` record does.
///
/// Only the app domain (Debug and Release bundle domains are naturally
/// separate) is touched; the global domain and other apps are never written.
nonisolated struct AppLanguageBridge {
  static let appleLanguagesKey = "AppleLanguages"
  private static let lastWrittenKey = "ProwlAppLanguageBridgeLastWritten"
  private static let originalExistedKey = "ProwlAppLanguageBridgeOriginalExisted"
  private static let originalValueKey = "ProwlAppLanguageBridgeOriginalValue"

  let defaults: UserDefaults
  /// The persistent domain the bridge manages. Reads go through
  /// `persistentDomain(forName:)` so a command-line `-AppleLanguages`
  /// override living in the argument domain is never mistaken for the
  /// persisted value.
  let domainName: String

  var currentAppleLanguages: [String]? {
    defaults.persistentDomain(forName: domainName)?[Self.appleLanguagesKey] as? [String]
  }

  func synchronize(preference: AppLanguage) {
    switch preference {
    case .system:
      restoreSystemLanguages()
    case .english, .zhHans:
      applyDerivedLanguages(for: preference)
    }
  }

  /// Preferred languages for predicting the next normal launch, with any
  /// Prowl-derived `AppleLanguages` prefix removed so it is not mistaken
  /// for the user's system list.
  func platformLanguagesForPrediction(
    preferredLanguages: [String] = Locale.preferredLanguages
  ) -> [String] {
    var languages = preferredLanguages
    if let derived = lastWritten, derived == currentAppleLanguages {
      for code in derived where languages.first == code {
        languages.removeFirst()
      }
    }
    return languages
  }

  private func applyDerivedLanguages(for language: AppLanguage) {
    let derived = [language.rawValue]
    let current = currentAppleLanguages
    if let lastWritten = lastWritten {
      if current != lastWritten {
        // Externally rewritten while we managed the key: the external value
        // is the user's latest non-Prowl choice, so it becomes the value to
        // restore when they return to "system".
        recordOriginal(current)
      }
      // current == lastWritten: we own the key; keep the original record.
    } else {
      // First take-over: capture the pre-Prowl value (or its absence).
      recordOriginal(current)
    }
    defaults.set(derived, forKey: Self.appleLanguagesKey)
    defaults.set(derived, forKey: Self.lastWrittenKey)
  }

  private func restoreSystemLanguages() {
    guard let lastWritten else { return }
    if currentAppleLanguages == lastWritten {
      if defaults.bool(forKey: Self.originalExistedKey),
        let original = defaults.stringArray(forKey: Self.originalValueKey)
      {
        defaults.set(original, forKey: Self.appleLanguagesKey)
      } else {
        defaults.removeObject(forKey: Self.appleLanguagesKey)
      }
    }
    // Mismatch: externally modified — keep the external value either way and
    // stop claiming the key.
    clearRecord()
  }

  private var lastWritten: [String]? {
    defaults.stringArray(forKey: Self.lastWrittenKey)
  }

  private func recordOriginal(_ value: [String]?) {
    if let value {
      defaults.set(true, forKey: Self.originalExistedKey)
      defaults.set(value, forKey: Self.originalValueKey)
    } else {
      defaults.set(false, forKey: Self.originalExistedKey)
      defaults.removeObject(forKey: Self.originalValueKey)
    }
  }

  private func clearRecord() {
    defaults.removeObject(forKey: Self.lastWrittenKey)
    defaults.removeObject(forKey: Self.originalExistedKey)
    defaults.removeObject(forKey: Self.originalValueKey)
  }
}

nonisolated struct AppLanguageBridgeClient: Sendable {
  var synchronize: @Sendable (_ preference: AppLanguage) -> Void = { _ in }
  var platformLanguages: @Sendable () -> [String] = { Locale.preferredLanguages }
}

extension AppLanguageBridgeClient: DependencyKey {
  static let liveValue = AppLanguageBridgeClient(
    synchronize: { preference in
      guard let domainName = Bundle.main.bundleIdentifier else { return }
      AppLanguageBridge(defaults: .standard, domainName: domainName)
        .synchronize(preference: preference)
    },
    platformLanguages: {
      guard let domainName = Bundle.main.bundleIdentifier else {
        return Locale.preferredLanguages
      }
      return AppLanguageBridge(defaults: .standard, domainName: domainName)
        .platformLanguagesForPrediction()
    }
  )

  static let testValue = AppLanguageBridgeClient()
}

extension DependencyValues {
  var appLanguageBridge: AppLanguageBridgeClient {
    get { self[AppLanguageBridgeClient.self] }
    set { self[AppLanguageBridgeClient.self] = newValue }
  }
}

import Foundation
import Testing

@testable import supacode

struct AppLanguageTests {
  private let supportedLanguages = ["en", "zh-Hans"]

  // MARK: - Model

  @Test func rawValuesAreStableStorageIdentifiers() {
    #expect(AppLanguage.system.rawValue == "system")
    #expect(AppLanguage.zhHans.rawValue == "zh-Hans")
    #expect(AppLanguage.english.rawValue == "en")
    #expect(AppLanguage(rawValue: "future-language") == nil)
  }

  @Test func titlesUseNativeLanguageForms() {
    #expect(AppLanguage.system.title == "Follow System / 跟随系统")
    #expect(AppLanguage.zhHans.title == "简体中文")
    #expect(AppLanguage.english.title == "English")
  }

  @Test func chinesePullRequestSummaryPreservesBaseAndHeadRoles() throws {
    let template = try chinese("%@ wants to merge %@ %@ into %@ from %@")
    let summary = String(format: template, "alice", "2", "commits", "main", "feature")

    #expect(summary == "alice 想要将 2 commits 从 feature 合并到 main")
  }

  @Test func chineseSkillRemovalHelpPreservesSkillAndPathRoles() throws {
    let template = try chinese("Remove the %@ skill link at %@; the bundled skill stays in the app")
    let help = String(format: template, "reviewer", "/tmp/reviewer")

    #expect(help == "移除 /tmp/reviewer 处的 reviewer 技能链接；内置技能仍保留在应用中")
  }

  @Test func confirmedWorkflowUIStringsHaveChineseTranslations() throws {
    let expectedTranslations = [
      "Delete Run": "删除运行记录",
      "Workflow run options": "工作流运行选项",
      "No fields": "无字段",
    ]

    for (key, expected) in expectedTranslations {
      #expect(try chinese(key) == expected)
    }
  }

  @Test func resolvedLanguageIsOnlyEnOrZhHans() {
    #expect(Set(ResolvedAppLanguage.allCases.map(\.rawValue)) == ["en", "zh-Hans"])
  }

  @Test func bootstrapSnapshotIsASupportedLanguage() {
    let snapshot = AppLanguageBootstrap.snapshotEffectiveLanguage()
    #expect(ResolvedAppLanguage.allCases.contains(snapshot))
  }

  // MARK: - Resolution

  @Test func explicitPreferenceWinsOverPlatformLanguages() {
    #expect(
      AppLanguageResolver.resolve(
        preference: .english,
        platformLanguages: ["zh-Hans"],
        supportedLanguages: supportedLanguages
      ) == .english
    )
    #expect(
      AppLanguageResolver.resolve(
        preference: .zhHans,
        platformLanguages: ["en-US"],
        supportedLanguages: supportedLanguages
      ) == .zhHans
    )
  }

  @Test func systemPreferenceFollowsPlatformNegotiation() {
    #expect(
      AppLanguageResolver.resolve(
        preference: .system,
        platformLanguages: ["zh-Hans", "en"],
        supportedLanguages: supportedLanguages
      ) == .zhHans
    )
    #expect(
      AppLanguageResolver.resolve(
        preference: .system,
        platformLanguages: ["en-US", "zh-Hans"],
        supportedLanguages: supportedLanguages
      ) == .english
    )
  }

  @Test func systemPreferenceFallsBackToEnglishWhenNothingMatches() {
    #expect(
      AppLanguageResolver.resolve(
        preference: .system,
        platformLanguages: ["fr-FR"],
        supportedLanguages: supportedLanguages
      ) == .english
    )
    #expect(
      AppLanguageResolver.resolve(
        preference: .system,
        platformLanguages: [],
        supportedLanguages: supportedLanguages
      ) == .english
    )
  }

  @Test func traditionalChineseDoesNotResolveToSimplified() {
    // Script differs, so platform matching must fall back to English rather
    // than treating any "zh" prefix as Simplified.
    #expect(
      AppLanguageResolver.resolve(
        preference: .system,
        platformLanguages: ["zh-Hant-TW"],
        supportedLanguages: supportedLanguages
      ) == .english
    )
  }

  @Test func commandLineOverrideBeatsExplicitPreference() {
    #expect(
      AppLanguageResolver.resolve(
        preference: .zhHans,
        platformLanguages: ["zh-Hans"],
        supportedLanguages: supportedLanguages,
        commandLineOverride: ["en"]
      ) == .english
    )
    #expect(
      AppLanguageResolver.resolve(
        preference: .english,
        platformLanguages: ["en"],
        supportedLanguages: supportedLanguages,
        commandLineOverride: ["zh-Hans"]
      ) == .zhHans
    )
  }

  @Test func commandLineOverrideWithoutMatchFallsBackToEnglish() {
    #expect(
      AppLanguageResolver.resolve(
        preference: .system,
        platformLanguages: ["zh-Hans"],
        supportedLanguages: supportedLanguages,
        commandLineOverride: ["fr-FR"]
      ) == .english
    )
  }

  // MARK: - Bridge ownership

  @Test func firstExplicitSelectionRecordsMissingOriginalAndRestoresByRemovingKey() {
    let (defaults, suite) = makeIsolatedDefaults()
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let bridge = AppLanguageBridge(defaults: defaults, domainName: suite)

    bridge.synchronize(preference: .zhHans)
    #expect(bridge.currentAppleLanguages == ["zh-Hans"])

    // The key did not exist before Prowl took over, so restoring "system"
    // removes it rather than resurrecting a phantom value.
    bridge.synchronize(preference: .system)
    #expect(bridge.currentAppleLanguages == nil)
  }

  @Test func existingExternalOverrideIsRestoredOnReturnToSystem() {
    let (defaults, suite) = makeIsolatedDefaults()
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    defaults.set(["ja"], forKey: "AppleLanguages")
    let bridge = AppLanguageBridge(defaults: defaults, domainName: suite)

    bridge.synchronize(preference: .english)
    #expect(bridge.currentAppleLanguages == ["en"])

    bridge.synchronize(preference: .system)
    #expect(bridge.currentAppleLanguages == ["ja"])
  }

  @Test func externalModificationInSystemModeIsPreservedAndRecordCleared() {
    let (defaults, suite) = makeIsolatedDefaults()
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let bridge = AppLanguageBridge(defaults: defaults, domainName: suite)

    bridge.synchronize(preference: .zhHans)
    #expect(bridge.currentAppleLanguages == ["zh-Hans"])

    // The user changes the per-app language through System Settings while
    // Prowl's record still points at its own write.
    defaults.set(["fr"], forKey: "AppleLanguages")
    bridge.synchronize(preference: .system)

    // The external value wins; the stale record must be dropped so a later
    // explicit selection treats "fr" as the value to restore.
    #expect(bridge.currentAppleLanguages == ["fr"])
    bridge.synchronize(preference: .english)
    #expect(bridge.currentAppleLanguages == ["en"])
    bridge.synchronize(preference: .system)
    #expect(bridge.currentAppleLanguages == ["fr"])
  }

  @Test func externalModificationInExplicitModeBecomesNewRestoreTarget() {
    let (defaults, suite) = makeIsolatedDefaults()
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let bridge = AppLanguageBridge(defaults: defaults, domainName: suite)

    bridge.synchronize(preference: .zhHans)
    defaults.set(["fr"], forKey: "AppleLanguages")

    bridge.synchronize(preference: .english)
    #expect(bridge.currentAppleLanguages == ["en"])

    bridge.synchronize(preference: .system)
    #expect(bridge.currentAppleLanguages == ["fr"])
  }

  @Test func systemWithoutRecordNeverClaimsExistingKey() {
    let (defaults, suite) = makeIsolatedDefaults()
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    // A per-app override set outside Prowl, with no Prowl ownership record.
    defaults.set(["de"], forKey: "AppleLanguages")
    let bridge = AppLanguageBridge(defaults: defaults, domainName: suite)

    bridge.synchronize(preference: .system)
    #expect(bridge.currentAppleLanguages == ["de"])
  }

  @Test func switchingBetweenExplicitLanguagesKeepsOriginalRestoreTarget() {
    let (defaults, suite) = makeIsolatedDefaults()
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let bridge = AppLanguageBridge(defaults: defaults, domainName: suite)

    bridge.synchronize(preference: .zhHans)
    bridge.synchronize(preference: .english)
    #expect(bridge.currentAppleLanguages == ["en"])

    // The original value was "absent" — Prowl's own zh-Hans write must not
    // become the restore target just because it is the current value.
    bridge.synchronize(preference: .system)
    #expect(bridge.currentAppleLanguages == nil)
  }

  @Test func predictionStripsProwlDerivedPrefixFromPreferredLanguages() {
    let (defaults, suite) = makeIsolatedDefaults()
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let bridge = AppLanguageBridge(defaults: defaults, domainName: suite)
    bridge.synchronize(preference: .zhHans)

    // After synchronize, we own the key. Prediction should return the saved
    // original (empty, since we started fresh), falling back to global.
    let predicted = bridge.platformLanguagesForPrediction()
    #expect(!predicted.contains("zh-Hans"), "Should strip Prowl-derived prefix")
  }

  @Test func predictionKeepsExternalOverrideAsSystemInput() {
    let (defaults, suite) = makeIsolatedDefaults()
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    defaults.set(["fr"], forKey: "AppleLanguages")
    let bridge = AppLanguageBridge(defaults: defaults, domainName: suite)

    // We don't own the key; the external ["fr"] should be returned as-is
    #expect(
      bridge.platformLanguagesForPrediction() == ["fr"]
    )
  }

  // A shortcut title is a run-time key: the compiler cannot extract it, so
  // `make check-localization-coverage` does not see a missing entry.
  @Test func everyShortcutTitleHasSimplifiedChineseEntry() throws {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    let sentinel = "\u{1}"
    let missing = AppShortcuts.bindings.map(\.title).filter {
      bundle.localizedString(forKey: $0, value: sentinel, table: nil) == sentinel
    }
    #expect(missing.isEmpty, "Add zh-Hans entries with extraction state manual: \(missing)")
  }

  // "Done" and "Blocked" have other meanings elsewhere (a button, a pull request
  // that cannot merge), so the agent states use their own keys.
  @Test func agentStateLabelsHaveTheirOwnCatalogEntries() throws {
    #expect(AgentDisplayState.working.label == "Working")
    #expect(AgentDisplayState.blocked.label == "Blocked")
    #expect(AgentDisplayState.done.label == "Done")
    #expect(AgentDisplayState.idle.label == "Idle")
    #expect(try chinese("agentState.working") == "工作中")
    #expect(try chinese("agentState.blocked") == "需处理")
    #expect(try chinese("agentState.done") == "已完成")
    #expect(try chinese("agentState.idle") == "空闲")
  }

  private func chinese(_ key: String) throws -> String {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    return bundle.localizedString(forKey: key, value: nil, table: nil)
  }

  private func makeIsolatedDefaults(
    function: String = #function
  ) -> (UserDefaults, String) {
    let suite = "prowl-app-language-tests.\(function).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
  }
}

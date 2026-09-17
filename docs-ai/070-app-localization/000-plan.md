# 070 — App Localization (Simplified Chinese): Plan

| | |
| --- | --- |
| **Status** | Planned (catalog, checks, glossary, and the language setting are in place; `001-action.md` follows when #811 merges) |
| **Anchor date** | 2026-09-18 |
| **Primary PRs** | #811 |
| **Related** | [glossary.md](glossary.md), `docs/components/settings.md`, `docs/reference/settings-fields.md` |

## Background

Prowl shipped in English only. PR #811 (an outside contribution) added a String Catalog with a
Simplified Chinese translation of the app UI and an in-app language setting. The maintainer took
the branch over on 2026-09-17 to finish it.

A review of the contribution found one structural problem: the catalog was written by hand and
nothing kept it in step with the code. Inside the PR itself, features that were merged from `main`
after the catalog was made (Remote Mirror, the new workflow sheet) had no entries, so the Chinese
UI showed mixed languages. More problems came from how Swift decides what is localizable:

- `Text("a " + "b")` has type `String`. The compiler does not extract it and SwiftUI shows it
  verbatim.
- A helper that takes `title: String` and calls `String(localized: String.LocalizationValue(title))`
  hides the literal at the call site from the compiler.
- The test host follows the system language. Assertions on English copy failed on a machine
  that runs in Chinese.

## Goals

- Every string the app shows comes from `supacode/Localizable.xcstrings`, with a finished `zh-Hans`
  translation.
- A change that adds UI copy without a translation fails a check, locally and in CI.
- Translations use one agreed vocabulary ([glossary.md](glossary.md)).
- Tests do not depend on the language of the machine.

### Non-goals

- Languages other than Simplified Chinese. The checks handle them, but no translation exists.
- The CLI, command IDs, log lines, agent prompts, and other protocol text. They stay in English.
- Text from third parties (Ghostty, Sparkle).

## Design / Approach

### The compiler is the source of truth for coverage

During a Debug build the Swift compiler writes one `.stringsdata` file per source file, next to
the object files. Each file lists the localizable strings the compiler found. This is the same
data Xcode uses to sync a catalog, so a comparison with it is exact. A scan of the source text
with regular expressions is not: it cannot tell `String` from `LocalizedStringKey`.

`scripts/check_localization.py` has two modes:

| Mode | Command | Needs a build | Reports |
| --- | --- | --- | --- |
| Catalog | `make check-localization` (part of `make check`) | No | An entry without a finished translation, a stale entry, placeholders that do not match the source |
| Coverage | `make check-localization-coverage` | Yes | A string the code uses but the catalog does not have; an entry that no code uses |

The required languages are the languages that appear in the catalog, so a new language is
enforced from its first entry. CI runs the catalog mode next to `make lint` and the coverage mode
after the app tests, which build the app (`.github/workflows/test.yml`). The script follows
`PROWL_DERIVED_DATA_PATH`, as `make test-app` does.

### Keys the compiler cannot see

A key that is built at run time must have `"extractionState": "manual"` in the catalog, or the
coverage mode reports it as unused. The shortcut titles in `AppShortcuts.bindings` and the Command
Palette titles are such keys. `AppLanguageTests` checks that each shortcut title has a `zh-Hans`
entry. `LocalizedStringResource(runtimeKey:)` (in `supacode/App/AppShortcuts.swift`) marks the
call sites.

Prefer to let the compiler see the literal:

- Give a helper a `LocalizedStringResource` or `LocalizedStringKey` parameter, not `String`.
  The literal at each call site is then extracted. Do not add a `String` overload next to it: a
  literal selects the `String` overload.
- Write long copy as one multi-line literal with `\` line continuations, not as a `+` chain.
- When one English word has two meanings, use a separate key with a default value, for example
  `String(localized: "agentState.done", defaultValue: "Done")`, and give the entry an explicit
  `en` value.

### The language setting has one source

Settings → General → Language offers Follow System, 简体中文, and English. `AppLanguageStore`
(`supacode/Features/Settings/BusinessLogic/AppLanguageStore.swift`) reads and writes the
per-app `AppleLanguages` default, the key that Foundation consults at launch. macOS writes the
same key from System Settings → Language & Region → Applications. Follow System removes the key.

Prowl keeps no copy of the choice in `settings.json`. The picker and System Settings therefore
always show one value, and the last change wins. `SettingsFeature` reads the value again when the
app becomes active and when the General page appears, because System Settings can change it
while Prowl runs.

A value that Prowl did not write is negotiated with `Bundle.preferredLocalizations`, as the
platform does: `zh-Hans-CN` reads as 简体中文, and a language without a localization reads as
English, because that is what the app shows. Foundation negotiates the language once per
process, so a change applies at the next launch. `SettingsFeature.State.languageChangePending`
compares the predicted language of the next launch with `ResolvedAppLanguage.effective()` to
show the restart hint only when the visible language changes.

### Tests

The `supacode` scheme runs tests with `language = "en"` and `region = "US"`. Tests assert on
literal English copy. Do not call `String(localized:)` on both sides of an assertion: that
compares a value with itself and does not check the text.

### Editing the catalog with a script

The catalog is plain JSON. `json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"` reproduces
the file byte for byte, so a scripted edit gives a minimal diff. An explicit `en` localization
overrides the key as the English text; remove it when the key changes.

## Alternatives & decisions

| Decision | Chosen | Rejected, and why |
| --- | --- | --- |
| Coverage check input | Compiler `.stringsdata` | A regular-expression scan of the source: many false reports. `xcstringstool sync`: its stale marking was not understood well enough to trust |
| Where the fast check runs | `make check` and CI lint stage | Only in CI: the feedback comes too late |
| Test language | Pinned in the scheme | `String(localized:)` on both sides of each assertion: the tests pass but verify nothing |
| Feature names | Translated (书架, 画布, Agent 灵动岛, 远程镜像) | English names: mixed text such as “Shelf 书脊” |
| `worktree` | Not translated | 工作树: `worktree` is a git term that users type and search for |
| Workflow `bundle` | Not translated (`Bundle`) | 捆绑包 reads badly; the DSL, the CLI, and the docs say bundle |
| Where the language choice lives | Per-app `AppleLanguages` only | A second copy in `settings.json` with ownership bookkeeping (the first design in #811): it silently reverted a choice made in System Settings, and needed about 170 lines to decide which side owned the key |

## Open

- **Verbatim `String` copy.** Some user-facing text is still built as plain `String` and is not
  localized: alert titles and messages in `RepositoriesFeature+WorktreeCreation.swift`, titles and
  placeholders in `WorkspaceCreationPromptView.swift`, error descriptions in `supacode/Clients/`,
  and user-facing messages from `WorkflowRunMachine.swift`. The coverage check cannot see them.

## Amendments

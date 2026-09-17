---
name: sync-l10n
description: Bring the app string catalog in step with the code at release time - translate new UI copy with the project glossary, remove catalog entries that no code uses, and triage string literals that look like unlocalized UI copy into the baseline (exempt or debt). Run as part of release prep, or on demand when the user asks to sync translations or localization. Nothing in everyday work depends on it.
---

# Sync L10n

Prowl localizes its UI (Simplified Chinese today). Everyday work is **not** blocked by
translations: a developer writes localizable English copy and moves on. This skill does the
catch-up **once per release**, so every release ships with a complete translation of the
copy the compiler can see, and every new suspicious literal has a recorded decision.

Read these first:

- `docs-ai/070-app-localization/000-plan.md` — the design and why it works this way.
- `docs-ai/070-app-localization/glossary.md` — the vocabulary. **Follow it for every value.**
  When a new term needs a decision, add it to the glossary in the same change.

All edits to the catalog and the baseline go through `scripts/localization.py`. Do not edit
`supacode/Localizable.xcstrings` or `scripts/localization_baseline.json` by hand: the script
validates placeholders and keeps the catalog in the exact format Xcode writes.

## Guiding principles

- **Translate what is new. Leave what exists.** Do not reword a finished translation unless
  it is wrong or breaks the glossary. Low churn keeps the diff reviewable.
- **Every suspect gets a decision.** Localize it, exempt it with a category, or record it as
  debt. Never make the audit pass by loosening the heuristics.
- **Prefer a rule over a list.** When a whole file or a call pattern is not UI (a new CLI
  handler, a new logger), add an `exemptPaths` or `exemptLinePatterns` rule. Rules absorb
  years of growth; per-literal entries do not.
- **Ask when the meaning is not clear.** A wrong exemption hides UI copy for good. Collect the
  unclear suspects and ask the user once, with the location and your best guess for each.
- **The debt is allowed to exist.** Burn it down within the budget below. Do not start a
  large refactor inside a release.

## Steps

1. **Build and audit.**
   ```bash
   make build-app
   python3 scripts/localization.py audit --json > "$SCRATCH/l10n-audit.json"
   ```
   The report has six lists. An empty report means nothing to do: say so and stop.

2. **`broken`** — a translation whose placeholders do not match its source. Fix the value
   with `apply` (step 4). This is the only list that also fails `make check`.

3. **`unused`** — catalog entries that no code uses. Before you remove them, look for run-time
   keys: a key that is looked up through `LocalizedStringResource(runtimeKey:)` or
   `String.LocalizationValue(<variable>)` is invisible to the compiler. Find the literal in the
   source (`git grep -F '"<key>"' -- supacode`). If it is still a run-time key, keep it and mark
   it with `"manual": true` through `apply`. Remove the rest:
   ```bash
   python3 scripts/localization.py prune
   ```
   `prune` also drops baseline entries whose literal left the code (`obsolete`).

4. **`missing` and `untranslated`** — write the translations to a JSON file and apply it:
   ```json
   {
     "Stop Host": {"zh-Hans": "停止主机"},
     "Resetting “%@” restores %@.": {"zh-Hans": "重置“%1$@”会恢复 %2$@。"},
     "Toggle Canvas": {"zh-Hans": "切换画布", "manual": true},
     "%@:%@": null
   }
   ```
   ```bash
   python3 scripts/localization.py apply "$SCRATCH/l10n-new.json"
   ```
   - Translate into **every** language the catalog uses (`untranslated` names the language).
   - `null` means "do not translate": a key that is only placeholders, punctuation, or a
     sample value such as `XXXX-XXXX`.
   - Keep every placeholder. When the order changes, number all of them (`%1$@`, `%2$lld`).
   - For a short or ambiguous string ("Open", "Run", "%@ in %@"), read the source file that
     `missing` names before you translate. One English word can need two translations; then
     the code needs its own key with a default value (see the plan, "Keys the compiler cannot
     see").
   - `apply` rejects a value with wrong placeholders and prints why.

5. **`suspects`** — literals that look like UI copy, are not localized, and are not in the
   baseline yet. Open each location and decide:

   | It is… | Do |
   | --- | --- |
   | UI copy, and the fix is local | Make it localizable in code (patterns below), rebuild, translate it in step 4 |
   | UI copy, but the fix needs a wider change (an error type, a reducer with tests, text that travels between machines) | Record it as `debt` |
   | Not UI: a log line, an identifier, a product name, text for an agent, a CLI or wire-protocol message, developer-only text | Exempt it with that category — or add a rule when the whole file or pattern is not UI |
   | Not clear | Ask the user (one batch) |

   ```json
   {
     "exempt": {"Claude Code": "product-name", "PANE_BUSY: …": "protocol"},
     "debt": ["Unable to create worktree"]
   }
   ```
   ```bash
   python3 scripts/localization.py triage "$SCRATCH/l10n-triage.json"
   ```
   Categories: `identifier`, `product-name`, `log`, `agent-prompt`, `protocol`, `developer`,
   `other`. The latest decision wins, so a wrong exemption can be moved back to `debt`.
   Rules live in `exemptPaths` and `exemptLinePatterns` of the baseline file; edit those two
   maps directly (the value is the reason), then run the audit again.

6. **Debt budget.** The audit prints the size of the debt. In each release, localize the debt
   in files that changed since the previous release tag, up to about 30 literals:
   ```bash
   git diff --name-only "$(git describe --tags --abbrev=0)"..HEAD -- supacode
   ```
   Skip this step when the release is urgent. Do more only when the user asks.

7. **Verify.** Rebuild and audit again until the report is empty, then:
   ```bash
   make build-app && python3 scripts/localization.py audit
   make check
   ```
   When you changed Swift code, run `make test` as well. Tests assert on English copy, and a
   key you changed can break one.

8. **Report.**
   ```
   ## L10n Sync
   Translated: <n> new, <n> updated · Removed: <n> unused · Marked manual: <n>
   Suspects: <n> localized, <n> exempt (<categories>), <n> debt, <n> rules added
   Debt: <before> → <after>

   ### Needs human decision
   - <literal> — <location> — <your guess and why you are not sure>
   ```

## Making copy localizable

| Situation | Write |
| --- | --- |
| Literal passed straight to SwiftUI | `Text("…")`, `.help("…")`, `Button("…")` — already localizable |
| The code needs a `String` (state, an alert, a toast) | `String(localized: "…")` |
| A helper takes copy as a parameter | Type the parameter `LocalizedStringKey` or `LocalizedStringResource`, not `String`. Do not keep a `String` overload: a literal selects it |
| A view-only helper returns copy | Return `LocalizedStringKey` |
| Long copy | One multi-line literal with `\` line continuations. `"a " + "b"` is a `String` and is never localized |
| The title is only known at run time | `LocalizedStringResource(runtimeKey:)`, and mark the catalog entry `manual` |
| Data, not copy (a branch name, a path) | `Text(verbatim:)` |

## Committing

- Stage only `supacode/Localizable.xcstrings`, `scripts/localization_baseline.json`, the
  glossary when it changed, and the Swift files you made localizable. Never `git add .`.
- **As part of release prep** (the `release` skill, on `main`): commit as its own commit before
  the version bump and tag, for example `git commit -m "Sync localization for <VERSION>"`.
  `release.sh` aborts on a dirty tree, and the commit must be an ancestor of the tag.
- **Standalone run** on a branch: open a PR that targets `onevcat/Prowl`.

## Adding a language

Add the first translation in the new language with `apply`. From then on the audit requires
that language for every entry. Add `docs-ai/070-app-localization/glossary-<language>.md`
before you translate in bulk.

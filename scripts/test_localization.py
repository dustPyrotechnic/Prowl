import json
import tempfile
import unittest
from pathlib import Path

from localization import (
    Baseline,
    apply_translations,
    build_settings_command,
    candidate_literals,
    extracted_keys,
    extraction_issues,
    placeholders,
    prune,
    record_decisions,
    serialize,
    structure_issues,
    translation_issues,
    unknown_candidates,
)


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def entry(zh_hans=None, **fields):
    localizations = {} if zh_hans is None else {"zh-Hans": unit(zh_hans)}
    return {"localizations": localizations, **fields}


def catalog(strings):
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


class PlaceholderTests(unittest.TestCase):
    def test_reads_types_in_argument_order(self):
        self.assertEqual(placeholders("%@ has %lld items"), ["@", "lld"])
        self.assertEqual(placeholders("%2$lld 项属于 %1$@"), ["@", "lld"])

    def test_ignores_escaped_percent(self):
        self.assertEqual(placeholders("%lld%% done"), ["lld"])

    def test_rejects_mixed_positional_and_sequential(self):
        self.assertIsNone(placeholders("%1$@ and %@"))


class SerializeTests(unittest.TestCase):
    def test_matches_the_format_that_xcode_writes(self):
        text = serialize(catalog({"b": entry("乙"), "A": {"shouldTranslate": False}}))
        self.assertTrue(text.startswith('{\n  "sourceLanguage" : "en",\n  "strings" : {\n    "A" : {'))
        self.assertLess(text.index('"A"'), text.index('"b"'))
        self.assertIn('"value" : "乙"', text)
        self.assertFalse(text.endswith("\n"))


class StructureIssueTests(unittest.TestCase):
    """The everyday check. It must not fail because a translation is still missing."""

    def test_accepts_entries_that_wait_for_the_release_sync(self):
        strings = {
            "Open": entry("打开"),
            "New copy": entry(),
            "From Xcode": {"extractionState": "stale", "localizations": {"zh-Hans": unit("旧", state="new")}},
        }
        self.assertEqual(structure_issues(catalog(strings)), [])

    def test_reports_placeholder_mismatch(self):
        strings = {"%@ has %lld items": entry("%@ 有 %@ 项")}
        self.assertEqual(
            structure_issues(catalog(strings)),
            ['"%@ has %lld items": zh-Hans placeholders [@, @] do not match source [@, lld]'],
        )

    def test_reports_reordered_placeholders_without_positions(self):
        strings = {"%@ has %lld items": entry("%lld 项属于 %@")}
        self.assertEqual(len(structure_issues(catalog(strings))), 1)

    def test_checks_every_variation(self):
        variations = {"variations": {"plural": {"one": unit("%lld 项"), "other": unit("很多项")}}}
        strings = {"%lld items": {"localizations": {"zh-Hans": variations}}}
        self.assertEqual(
            structure_issues(catalog(strings)),
            ['"%lld items": zh-Hans placeholders [] do not match source [lld]'],
        )


class TranslationIssueTests(unittest.TestCase):
    """The release check."""

    def test_accepts_complete_catalog(self):
        strings = {"Open": entry("打开"), "·": {"shouldTranslate": False}}
        self.assertEqual(translation_issues(catalog(strings)), [])

    def test_reports_missing_translation(self):
        strings = {"Open": entry("打开"), "Close": entry()}
        self.assertEqual(translation_issues(catalog(strings)), ['"Close": no zh-Hans translation'])

    def test_reports_unfinished_state(self):
        strings = {"Open": {"localizations": {"zh-Hans": unit("打开", state="needs_review")}}}
        self.assertEqual(translation_issues(catalog(strings)), ['"Open": zh-Hans state is needs_review'])

    def test_requires_every_language_the_catalog_uses(self):
        strings = {
            "Open": {"localizations": {"zh-Hans": unit("打开"), "ja": unit("開く")}},
            "Close": entry("关闭"),
        }
        self.assertEqual(translation_issues(catalog(strings)), ['"Close": no ja translation'])


class ExtractionIssueTests(unittest.TestCase):
    def test_reports_key_in_code_without_entry(self):
        issues = extraction_issues(catalog({"Open": entry("打开")}), {"Open": {"A.swift"}, "Close": {"B.swift"}})
        self.assertEqual(issues.missing, {"Close": ["B.swift"]})
        self.assertEqual(issues.unused, [])

    def test_reports_entry_without_use(self):
        issues = extraction_issues(catalog({"Open": entry("打开"), "Close": entry("关闭")}), {"Open": {"A.swift"}})
        self.assertEqual(issues.unused, ["Close"])

    def test_keeps_manual_entry_without_use(self):
        strings = {"Open": entry("打开", extractionState="manual")}
        self.assertEqual(extraction_issues(catalog(strings), {}).unused, [])


class ExtractedKeyTests(unittest.TestCase):
    def test_reads_localizable_table_of_existing_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "View.swift"
            source.write_text("")
            data = {
                "source": str(source),
                "tables": {"Localizable": [{"key": "Open"}, {"key": ""}], "Other": [{"key": "Ignored"}]},
            }
            (root / "View.stringsdata").write_text(json.dumps(data))
            removed = {"source": str(root / "Removed.swift"), "tables": {"Localizable": [{"key": "Gone"}]}}
            (root / "Removed.stringsdata").write_text(json.dumps(removed))
            self.assertEqual(extracted_keys(root), {"Open": {"View.swift"}})


class ApplyTests(unittest.TestCase):
    def test_adds_and_updates_translations(self):
        data = catalog({"Open": entry("开")})
        errors = apply_translations(data, {"Open": {"zh-Hans": "打开"}, "Close": {"zh-Hans": "关闭"}})
        self.assertEqual(errors, [])
        self.assertEqual(data["strings"]["Open"]["localizations"]["zh-Hans"], unit("打开"))
        self.assertEqual(data["strings"]["Close"]["localizations"]["zh-Hans"], unit("关闭"))

    def test_null_marks_a_key_as_not_translatable(self):
        data = catalog({})
        self.assertEqual(apply_translations(data, {"%@:%@": None}), [])
        self.assertEqual(data["strings"]["%@:%@"], {"shouldTranslate": False})

    def test_marks_a_run_time_key_as_manual(self):
        data = catalog({})
        self.assertEqual(apply_translations(data, {"Toggle Canvas": {"zh-Hans": "切换画布", "manual": True}}), [])
        self.assertEqual(data["strings"]["Toggle Canvas"]["extractionState"], "manual")
        self.assertEqual(list(data["strings"]["Toggle Canvas"]["localizations"]), ["zh-Hans"])

    def test_rejects_a_translation_with_wrong_placeholders(self):
        data = catalog({})
        errors = apply_translations(data, {"%@ items": {"zh-Hans": "很多项"}})
        self.assertEqual(len(errors), 1)
        self.assertNotIn("%@ items", data["strings"])


class PruneTests(unittest.TestCase):
    def test_removes_unused_entries_and_keeps_manual_ones(self):
        strings = {
            "Open": entry("打开"),
            "Gone": entry("没了"),
            "Run time": entry("运行时", extractionState="manual"),
        }
        data = catalog(strings)
        self.assertEqual(prune(data, {"Open": {"A.swift"}}), ["Gone"])
        self.assertEqual(sorted(data["strings"]), ["Open", "Run time"])


class CandidateLiteralTests(unittest.TestCase):
    def scan(self, path, text):
        return [literal for _, literal in candidate_literals(path, text)]

    def test_finds_sentences_anywhere(self):
        text = 'let message = "Unable to create worktree"\nlet key = "defaultEditorID"\n'
        self.assertEqual(self.scan("supacode/Domain/Thing.swift", text), ["Unable to create worktree"])

    def test_finds_single_words_only_in_view_files(self):
        text = 'Text(flag ? "Ready" : label)\n'
        self.assertEqual(self.scan("supacode/Features/X/Views/Row.swift", text), ["Ready"])
        self.assertEqual(self.scan("supacode/Domain/Thing.swift", text), [])

    def test_describes_interpolation_as_a_placeholder(self):
        text = 'return "Cannot reach \\(endpoint). Check the network."\n'
        self.assertEqual(self.scan("supacode/Domain/Thing.swift", text), ["Cannot reach %@. Check the network."])

    def test_skips_file_names_and_identifiers(self):
        text = 'let a = "Cargo.toml"\nlet b = "PROWL_LAUNCH_HOOK_TOKEN"\nlet c = "\\(home)/.local/bin/gh"\n'
        self.assertEqual(self.scan("supacode/Domain/Thing.swift", text), [])

    def test_skips_comments(self):
        self.assertEqual(self.scan("supacode/Domain/Thing.swift", '// "Not real copy here"\n'), [])

    def test_reads_past_quotes_inside_an_interpolation(self):
        text = 'let text = "Launching role \\(redelivery ? "again" : "now") for you"\n'
        self.assertEqual(self.scan("supacode/Domain/Thing.swift", text), ["Launching role %@ for you"])

    def test_reads_a_multi_line_literal_as_one_string(self):
        text = 'let text = """\n    Host is off. \\\n    Start Host first.\n    """\nlet next = 1\n'
        self.assertEqual(self.scan("supacode/Domain/Thing.swift", text), ["Host is off. Start Host first."])

    def test_reports_the_line_where_the_literal_starts(self):
        text = 'let a = 1\nlet text = "Unable to create worktree"\n'
        self.assertEqual(candidate_literals("supacode/Domain/Thing.swift", text), [(2, "Unable to create worktree")])


class BaselineTests(unittest.TestCase):
    def baseline(self, **fields):
        data = {"exemptPaths": {}, "exemptLinePatterns": {}, "exemptLiterals": {}, "debt": []}
        data.update(fields)
        return Baseline(data)

    def test_reports_only_candidates_that_nobody_has_triaged(self):
        baseline = self.baseline(exemptLiterals={"Claude Code": "product-name"}, debt=["Unable to create worktree"])
        found = {
            "Claude Code": ["supacode/Domain/A.swift:1"],
            "Unable to create worktree": ["supacode/Features/B.swift:2"],
            "Brand new copy": ["supacode/Features/C.swift:3"],
        }
        self.assertEqual(unknown_candidates(found, baseline, extracted=set()), {"Brand new copy": found["Brand new copy"]})

    def test_ignores_what_the_compiler_extracted(self):
        found = {"Open %@": ["supacode/Features/C.swift:3"]}
        self.assertEqual(unknown_candidates(found, self.baseline(), extracted={"Open %lld"}), {})

    def test_exempts_by_path_and_by_line(self):
        baseline = self.baseline(
            exemptPaths={"supacode/CLIService/**": "protocol"},
            exemptLinePatterns={r"[Ll]ogger\.": "log"},
        )
        self.assertTrue(baseline.exempts_path("supacode/CLIService/Handler.swift"))
        self.assertFalse(baseline.exempts_path("supacode/Features/View.swift"))
        self.assertTrue(baseline.exempts_line('  logger.info("Something happened here")'))

    def test_latest_triage_decision_wins(self):
        baseline = self.baseline(exemptLiterals={"RUN SCRIPT": "identifier"}, debt=["Claude Code"])
        record_decisions(baseline, {"exempt": {"Claude Code": "product-name"}, "debt": ["RUN SCRIPT"]})
        self.assertEqual(baseline.exempt_literals, {"Claude Code": "product-name"})
        self.assertEqual(baseline.debt, ["RUN SCRIPT"])

    def test_reports_entries_that_left_the_code(self):
        baseline = self.baseline(exemptLiterals={"Gone Product": "product-name"}, debt=["Gone copy", "Still here"])
        self.assertEqual(baseline.obsolete({"Still here"}), ["Gone Product", "Gone copy"])


class BuildSettingsCommandTests(unittest.TestCase):
    def test_uses_the_default_derived_data(self):
        self.assertNotIn("-derivedDataPath", build_settings_command({}))

    def test_follows_the_derived_data_path_of_make_test(self):
        command = build_settings_command({"PROWL_DERIVED_DATA_PATH": "/tmp/dd"})
        index = command.index("-derivedDataPath")
        self.assertEqual(command[index + 1], "/tmp/dd")


if __name__ == "__main__":
    unittest.main()

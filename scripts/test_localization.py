import json
import tempfile
import unittest
from pathlib import Path

from check_localization import (
    build_settings_command,
    catalog_issues,
    extracted_keys,
    extraction_issues,
    placeholders,
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


class CatalogIssueTests(unittest.TestCase):
    def test_accepts_complete_catalog(self):
        strings = {
            "Open": entry("打开"),
            "%@ in %@": entry("%2$@ 中的 %1$@"),
            "·": {"shouldTranslate": False},
        }
        self.assertEqual(catalog_issues(catalog(strings)), [])

    def test_reports_missing_translation(self):
        strings = {"Open": entry("打开"), "Close": entry()}
        self.assertEqual(catalog_issues(catalog(strings)), ['"Close": no zh-Hans translation'])

    def test_reports_unfinished_state(self):
        strings = {"Open": {"localizations": {"zh-Hans": unit("打开", state="needs_review")}}}
        self.assertEqual(catalog_issues(catalog(strings)), ['"Open": zh-Hans state is needs_review'])

    def test_reports_stale_entry(self):
        strings = {"Open": entry("打开", extractionState="stale")}
        self.assertEqual(catalog_issues(catalog(strings)), ['"Open": marked stale'])

    def test_reports_placeholder_mismatch(self):
        strings = {"%@ has %lld items": entry("%@ 有 %@ 项")}
        self.assertEqual(
            catalog_issues(catalog(strings)),
            ['"%@ has %lld items": zh-Hans placeholders [@, @] do not match source [@, lld]'],
        )

    def test_reports_reordered_placeholders_without_positions(self):
        strings = {"%@ has %lld items": entry("%lld 项属于 %@")}
        self.assertEqual(len(catalog_issues(catalog(strings))), 1)

    def test_checks_every_variation(self):
        variations = {
            "variations": {
                "plural": {
                    "one": unit("%lld 项"),
                    "other": unit("很多项"),
                }
            }
        }
        strings = {"Open": entry("打开"), "%lld items": {"localizations": {"zh-Hans": variations}}}
        self.assertEqual(
            catalog_issues(catalog(strings)),
            ['"%lld items": zh-Hans placeholders [] do not match source [lld]'],
        )

    def test_requires_every_language_the_catalog_uses(self):
        strings = {
            "Open": {"localizations": {"zh-Hans": unit("打开"), "ja": unit("開く")}},
            "Close": entry("关闭"),
        }
        self.assertEqual(catalog_issues(catalog(strings)), ['"Close": no ja translation'])


class ExtractionIssueTests(unittest.TestCase):
    def test_reports_key_in_code_without_entry(self):
        issues = extraction_issues(catalog({"Open": entry("打开")}), {"Open": {"A.swift"}, "Close": {"B.swift"}})
        self.assertEqual(issues, ['"Close": used in B.swift but not in the catalog'])

    def test_reports_entry_without_use(self):
        issues = extraction_issues(catalog({"Open": entry("打开"), "Close": entry("关闭")}), {"Open": {"A.swift"}})
        self.assertEqual(issues, ['"Close": in the catalog but not used in code (mark it manual if it is a runtime key)'])

    def test_allows_manual_entry_without_use(self):
        strings = {"Open": entry("打开", extractionState="manual")}
        self.assertEqual(extraction_issues(catalog(strings), {}), [])


class BuildSettingsCommandTests(unittest.TestCase):
    def test_uses_the_default_derived_data(self):
        self.assertNotIn("-derivedDataPath", build_settings_command({}))

    def test_follows_the_derived_data_path_of_make_test(self):
        command = build_settings_command({"PROWL_DERIVED_DATA_PATH": "/tmp/dd"})
        index = command.index("-derivedDataPath")
        self.assertEqual(command[index + 1], "/tmp/dd")


class ExtractedKeyTests(unittest.TestCase):
    def test_reads_localizable_table_of_existing_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "View.swift"
            source.write_text("")
            data = {
                "source": str(source),
                "tables": {
                    "Localizable": [{"key": "Open"}, {"key": ""}],
                    "Other": [{"key": "Ignored"}],
                },
            }
            (root / "View.stringsdata").write_text(json.dumps(data))
            removed = {"source": str(root / "Removed.swift"), "tables": {"Localizable": [{"key": "Gone"}]}}
            (root / "Removed.stringsdata").write_text(json.dumps(removed))
            self.assertEqual(extracted_keys(root), {"Open": {"View.swift"}})


if __name__ == "__main__":
    unittest.main()

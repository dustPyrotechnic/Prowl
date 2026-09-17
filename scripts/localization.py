#!/usr/bin/env python3
"""Check that the app string catalog is complete and matches the strings used in code.

Without arguments, only the catalog is checked: every entry has a finished
translation in each language the catalog uses, and its placeholders match the
source string. This needs no build.

With --from-build (or --stringsdata DIR), the catalog is also compared with the
.stringsdata files that the Swift compiler writes during a Debug build. They
list every localizable string the compiler found, so the comparison is exact.
It reports strings that the code uses but the catalog does not have, and
entries that no code uses. An entry for a key that is built at run time must
have the extraction state "manual".
"""

from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "supacode" / "Localizable.xcstrings"
TARGET = "supacode"
TABLE = "Localizable"
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsS])")


def placeholders(text: str) -> list[str] | None:
    """Return the placeholder types in argument order, or None when positions are mixed."""
    found = PLACEHOLDER.findall(text.replace("%%", ""))
    types = [(length or "") + conversion for _, length, conversion in found]
    positions = [int(position) for position, _, _ in found if position]
    if not positions:
        return types
    if len(positions) != len(found):
        return None
    ordered: dict[int, str] = {}
    for position, kind in zip(positions, types):
        ordered[position] = kind
    return [ordered[position] for position in sorted(ordered)]


def string_units(localization: dict) -> list[dict]:
    units = []
    if "stringUnit" in localization:
        units.append(localization["stringUnit"])
    for variation in localization.get("variations", {}).values():
        for case in variation.values():
            units.extend(string_units(case))
    return units


def describe(types: list[str] | None) -> str:
    return "mixed positions" if types is None else "[" + ", ".join(types) + "]"


def catalog_issues(catalog: dict) -> list[str]:
    strings = catalog["strings"]
    source_language = catalog.get("sourceLanguage", "en")
    languages = sorted(
        {language for entry in strings.values() for language in entry.get("localizations", {})} - {source_language}
    )
    issues = []
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        if entry.get("extractionState") == "stale":
            issues.append(f'"{key}": marked stale')
        expected = placeholders(key)
        for language in languages:
            localization = entry.get("localizations", {}).get(language)
            units = string_units(localization) if localization else []
            if not units:
                issues.append(f'"{key}": no {language} translation')
                continue
            for unit in units:
                if unit.get("state") != "translated":
                    issues.append(f'"{key}": {language} state is {unit.get("state")}')
                actual = placeholders(unit.get("value", ""))
                if actual != expected:
                    issues.append(
                        f'"{key}": {language} placeholders {describe(actual)} do not match source {describe(expected)}'
                    )
    return issues


def extracted_keys(directory: Path) -> dict[str, set[str]]:
    """Map each key the compiler extracted to the source files that use it."""
    keys: dict[str, set[str]] = {}
    for path in sorted(Path(directory).rglob("*.stringsdata")):
        data = json.loads(path.read_text())
        source = Path(data.get("source", ""))
        # Incremental builds can leave the output of a deleted file behind.
        if not source.is_file():
            continue
        for item in data.get("tables", {}).get(TABLE, []):
            if item["key"]:
                keys.setdefault(item["key"], set()).add(source.name)
    return keys


def extraction_issues(catalog: dict, extracted: dict[str, set[str]]) -> list[str]:
    strings = catalog["strings"]
    issues = []
    for key in sorted(extracted):
        if key not in strings:
            sources = ", ".join(sorted(extracted[key]))
            issues.append(f'"{key}": used in {sources} but not in the catalog')
    for key, entry in strings.items():
        if key not in extracted and entry.get("extractionState") != "manual":
            issues.append(f'"{key}": in the catalog but not used in code (mark it manual if it is a runtime key)')
    return issues


def build_settings_command(environment: dict[str, str]) -> list[str]:
    command = ["xcodebuild", "-project", str(ROOT / "supacode.xcodeproj"), "-scheme", TARGET]
    command += ["-configuration", "Debug", "-showBuildSettings", "-json"]
    # `make test-app` builds into this directory when the variable is set (CI does that).
    derived_data = environment.get("PROWL_DERIVED_DATA_PATH")
    if derived_data:
        command += ["-derivedDataPath", derived_data]
    return command


def build_objects_directory() -> Path:
    """Ask Xcode where the Debug build of the app target writes its per-file output."""
    command = build_settings_command(dict(os.environ))
    output = subprocess.run(command, check=True, capture_output=True, text=True).stdout
    for target in json.loads(output):
        if target["target"] == TARGET:
            return Path(target["buildSettings"]["OBJECT_FILE_DIR_normal"])
    raise SystemExit(f"error: no build settings for target {TARGET}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--stringsdata", type=Path, help="build directory that contains the .stringsdata files")
    parser.add_argument("--from-build", action="store_true", help="find the .stringsdata files of the Debug build")
    arguments = parser.parse_args()
    if arguments.from_build:
        arguments.stringsdata = build_objects_directory()

    catalog = json.loads(arguments.catalog.read_text())
    issues = catalog_issues(catalog)
    if arguments.stringsdata:
        extracted = extracted_keys(arguments.stringsdata)
        if not extracted:
            print(f"error: no .stringsdata files in {arguments.stringsdata}; build the app first", file=sys.stderr)
            return 2
        issues += extraction_issues(catalog, extracted)
    for issue in issues:
        print(issue.replace("\n", "\\n"))
    if issues:
        print(f"{len(issues)} localization issue(s) in {arguments.catalog.name}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

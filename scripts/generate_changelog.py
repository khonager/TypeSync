#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE_YAML = REPO_ROOT / "changelog" / "changelog.yaml"
OUTPUT_JSON = REPO_ROOT / "assets" / "data" / "changelog.json"
OUTPUT_LATEST_MD = REPO_ROOT / "changelog" / "generated" / "latest.md"
OUTPUT_LATEST_TXT = REPO_ROOT / "changelog" / "generated" / "latest.txt"
OUTPUT_RELEASES_DIR = REPO_ROOT / "changelog" / "generated" / "releases"


@dataclass(frozen=True)
class ParsedLine:
    indent: int
    text: str


def _normalize_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def _split_key_value(text: str) -> tuple[str, str]:
    if ":" not in text:
        raise ValueError(f"Expected key/value pair, got: {text!r}")
    key, value = text.split(":", 1)
    key = key.strip()
    if not key:
        raise ValueError(f"Missing key in: {text!r}")
    return key, _normalize_scalar(value)


def _parse_version(version: str) -> tuple[int, int, int]:
    core = version.strip().split("+", 1)[0].split("-", 1)[0]
    pieces = core.split(".")
    numbers = []
    for piece in pieces[:3]:
        match = re.search(r"\d+", piece)
        numbers.append(int(match.group(0)) if match else 0)
    while len(numbers) < 3:
        numbers.append(0)
    return numbers[0], numbers[1], numbers[2]


def _load_lines(raw: str) -> list[ParsedLine]:
    lines: list[ParsedLine] = []
    for raw_line in raw.splitlines():
        if not raw_line.strip():
            continue
        stripped = raw_line.lstrip(" ")
        if stripped.startswith("#"):
            continue
        indent = len(raw_line) - len(stripped)
        if "\t" in raw_line:
            raise ValueError("Tabs are not supported in changelog.yaml indentation.")
        lines.append(ParsedLine(indent=indent, text=stripped.rstrip()))
    return lines


def parse_changelog_yaml(raw: str) -> dict[str, Any]:
    lines = _load_lines(raw)
    i = 0
    schema_version: int | None = None
    releases: list[dict[str, Any]] = []
    list_section_keys = {
        "important",
        "new_features",
        "fixes_improvements",
        "notes",
        "changes",
    }

    while i < len(lines):
        line = lines[i]
        if line.indent != 0:
            raise ValueError(
                f"Top-level lines must have 0-space indentation (line: {line.text!r})."
            )
        if line.text.startswith("schema_version:"):
            _, value = _split_key_value(line.text)
            schema_version = int(value)
            i += 1
            continue
        if line.text != "releases:":
            raise ValueError(f"Unknown top-level key: {line.text!r}")

        i += 1
        while i < len(lines):
            head = lines[i]
            if head.indent < 2:
                break
            if head.indent != 2 or not head.text.startswith("- "):
                raise ValueError(
                    "Each release entry must start with '  - ' at 2-space indentation."
                )

            release: dict[str, Any] = {}
            inline = head.text[2:].strip()
            if inline:
                key, value = _split_key_value(inline)
                release[key] = value
            i += 1

            while i < len(lines):
                body = lines[i]
                if body.indent < 4:
                    break
                if body.indent != 4:
                    raise ValueError(
                        "Release fields must use 4-space indentation under '- '."
                    )

                if body.text.endswith(":"):
                    section_key = body.text[:-1].strip()
                    if section_key not in list_section_keys:
                        raise ValueError(
                            f"Unknown release list section: {section_key!r}"
                        )
                    i += 1
                    changes: list[str] = []
                    while i < len(lines):
                        bullet = lines[i]
                        if bullet.indent < 6:
                            break
                        if bullet.indent != 6 or not bullet.text.startswith("- "):
                            raise ValueError(
                                "Change bullets must use '      - ' indentation."
                            )
                        changes.append(_normalize_scalar(bullet.text[2:]))
                        i += 1
                    release[section_key] = changes
                    continue

                key, value = _split_key_value(body.text)
                release[key] = value
                i += 1

            releases.append(release)

    if schema_version is None:
        raise ValueError("Missing required top-level key: schema_version")
    if not releases:
        raise ValueError("At least one release entry is required.")

    section_keys = (
        "important",
        "new_features",
        "fixes_improvements",
        "notes",
        "changes",  # legacy alias; mapped into fixes_improvements
    )

    for release in releases:
        for required in ("version", "date", "title"):
            if required not in release:
                raise ValueError(f"Release missing required key: {required!r}")

        for section_key in section_keys:
            value = release.get(section_key)
            if value is None:
                continue
            if not isinstance(value, list):
                raise ValueError(
                    f"Release {release.get('version', '<unknown>')} has non-list section {section_key!r}."
                )

        has_any_section = any(release.get(section_key) for section_key in section_keys)
        if not has_any_section:
            raise ValueError(
                f"Release {release.get('version', '<unknown>')} must include at least one section."
            )

    releases.sort(key=lambda r: _parse_version(str(r["version"])), reverse=True)

    latest_version = str(releases[0]["version"])
    normalized_releases = [
        {
            "version": str(release["version"]),
            "date": str(release["date"]),
            "title": str(release["title"]),
            "important": [str(item) for item in release.get("important", [])],
            "newFeatures": [str(item) for item in release.get("new_features", [])],
            "fixesImprovements": [
                str(item)
                for item in (
                    release.get("fixes_improvements", [])
                    + release.get("changes", [])
                )
            ],
            "notes": [str(item) for item in release.get("notes", [])],
        }
        for release in releases
    ]
    return {
        "schemaVersion": schema_version,
        "latestVersion": latest_version,
        "releases": normalized_releases,
    }


def _release_markdown(release: dict[str, Any]) -> str:
    lines = [
        f"# TypeSync {release['version']}",
        "",
        f"Released: {release['date']}",
        "",
        release["title"],
        "",
    ]
    sections = [
        ("Important", release.get("important", [])),
        ("New Features", release.get("newFeatures", [])),
        ("Fixes & Improvements", release.get("fixesImprovements", [])),
        ("Notes", release.get("notes", [])),
    ]
    for heading, items in sections:
        if not items:
            continue
        lines.append(f"## {heading}")
        lines.extend(f"- {item}" for item in items)
        lines.append("")
    lines.append("")
    return "\n".join(lines)


def _release_text(release: dict[str, Any]) -> str:
    lines = [f"TypeSync {release['version']} - {release['title']}"]
    sections = [
        ("Important", release.get("important", [])),
        ("New Features", release.get("newFeatures", [])),
        ("Fixes & Improvements", release.get("fixesImprovements", [])),
        ("Notes", release.get("notes", [])),
    ]
    for heading, items in sections:
        if not items:
            continue
        lines.append(f"{heading}:")
        lines.extend(f"- {item}" for item in items)
    lines.append("")
    return "\n".join(lines)


def generate(*, check: bool) -> int:
    if not SOURCE_YAML.exists():
        raise FileNotFoundError(f"Missing changelog source: {SOURCE_YAML}")

    parsed = parse_changelog_yaml(SOURCE_YAML.read_text(encoding="utf-8"))
    rendered_json = json.dumps(parsed, indent=2, ensure_ascii=False) + "\n"
    current_json = OUTPUT_JSON.read_text(encoding="utf-8") if OUTPUT_JSON.exists() else None

    if check:
        if current_json != rendered_json:
            print("changelog.json is stale. Run: python3 scripts/generate_changelog.py")
            return 1
        return 0

    OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_JSON.write_text(rendered_json, encoding="utf-8")

    releases = parsed["releases"]
    latest_release = releases[0]
    OUTPUT_LATEST_MD.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_LATEST_MD.write_text(_release_markdown(latest_release), encoding="utf-8")
    OUTPUT_LATEST_TXT.write_text(_release_text(latest_release), encoding="utf-8")

    OUTPUT_RELEASES_DIR.mkdir(parents=True, exist_ok=True)
    for old_file in OUTPUT_RELEASES_DIR.glob("*"):
        if old_file.is_file():
            old_file.unlink()
    for release in releases:
        version = str(release["version"])
        (OUTPUT_RELEASES_DIR / f"{version}.md").write_text(
            _release_markdown(release),
            encoding="utf-8",
        )
        (OUTPUT_RELEASES_DIR / f"{version}.txt").write_text(
            _release_text(release),
            encoding="utf-8",
        )

    print(f"Updated {OUTPUT_JSON.relative_to(REPO_ROOT)}")
    print(f"Updated {OUTPUT_LATEST_MD.relative_to(REPO_ROOT)}")
    print(f"Updated {OUTPUT_LATEST_TXT.relative_to(REPO_ROOT)}")
    print(f"Updated {OUTPUT_RELEASES_DIR.relative_to(REPO_ROOT)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate app changelog artifacts.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail when generated output does not match committed files.",
    )
    args = parser.parse_args()
    return generate(check=args.check)


if __name__ == "__main__":
    raise SystemExit(main())

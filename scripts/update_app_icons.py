#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from decimal import Decimal
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE_SVG = REPO_ROOT / "assets/icons/icon.svg"
RASTER_PNG = REPO_ROOT / "assets/icons/icon.png"
IOS_CONTENTS = REPO_ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
MACOS_CONTENTS = REPO_ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
WINDOWS_ICON = REPO_ROOT / "windows/runner/resources/app_icon.ico"
TOOL_HOME = Path(tempfile.gettempdir()) / "typesync-app-icons-home"
EXPORT_BACKGROUND = "#1d1d1d"

ANDROID_TARGETS = {
    48: [
        REPO_ROOT / "android/app/src/main/res/mipmap-mdpi/launcher_icon.png",
        REPO_ROOT / "android/app/src/main/res/mipmap-mdpi/ic_launcher.png",
    ],
    72: [
        REPO_ROOT / "android/app/src/main/res/mipmap-hdpi/launcher_icon.png",
        REPO_ROOT / "android/app/src/main/res/mipmap-hdpi/ic_launcher.png",
    ],
    96: [
        REPO_ROOT / "android/app/src/main/res/mipmap-xhdpi/launcher_icon.png",
        REPO_ROOT / "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png",
    ],
    144: [
        REPO_ROOT / "android/app/src/main/res/mipmap-xxhdpi/launcher_icon.png",
        REPO_ROOT / "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png",
    ],
    192: [
        REPO_ROOT / "android/app/src/main/res/mipmap-xxxhdpi/launcher_icon.png",
        REPO_ROOT / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png",
    ],
}

WEB_TARGETS = {
    32: [REPO_ROOT / "web/favicon.png"],
    192: [
        REPO_ROOT / "web/icons/Icon-192.png",
        REPO_ROOT / "web/icons/Icon-maskable-192.png",
    ],
    512: [
        REPO_ROOT / "web/icons/Icon-512.png",
        REPO_ROOT / "web/icons/Icon-maskable-512.png",
    ],
}

WINDOWS_ICON_SIZES = [16, 24, 32, 40, 48, 64, 128, 256]


def main() -> int:
    if not SOURCE_SVG.is_file():
        print(f"Missing source SVG: {SOURCE_SVG}", file=sys.stderr)
        return 1

    if shutil.which("inkscape") is None:
        print("Inkscape is required to generate the icon assets.", file=sys.stderr)
        return 1

    (TOOL_HOME / ".config").mkdir(parents=True, exist_ok=True)
    (TOOL_HOME / ".cache").mkdir(parents=True, exist_ok=True)

    export_png(1024, RASTER_PNG)

    generate_explicit_targets(ANDROID_TARGETS)
    generate_explicit_targets(WEB_TARGETS)
    generate_contents_targets(IOS_CONTENTS)
    generate_contents_targets(MACOS_CONTENTS)
    generate_windows_ico()

    print(f"Updated app icons from {SOURCE_SVG}")
    return 0


def generate_explicit_targets(target_map: dict[int, list[Path]]) -> None:
    for size, paths in sorted(target_map.items()):
        for path in paths:
            export_png(size, path)


def generate_contents_targets(contents_path: Path) -> None:
    with contents_path.open() as handle:
        contents = json.load(handle)

    base_dir = contents_path.parent
    generated_paths: set[Path] = set()
    for image in contents.get("images", []):
        filename = image.get("filename")
        if not filename:
            continue
        output_path = base_dir / filename
        if output_path in generated_paths:
            continue
        export_png(pixel_size(image["size"], image["scale"]), output_path)
        generated_paths.add(output_path)


def pixel_size(size_value: str, scale_value: str) -> int:
    width = Decimal(size_value.split("x", 1)[0])
    scale = Decimal(scale_value.removesuffix("x"))
    return int(width * scale)


def export_png(size: int, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        display_path = output_path.relative_to(REPO_ROOT)
    except ValueError:
        display_path = output_path
    print(f"Generating {display_path} ({size}x{size})")
    subprocess.run(
        [
            "inkscape",
            str(SOURCE_SVG),
            "--export-type=png",
            f"--export-filename={output_path}",
            f"--export-width={size}",
            f"--export-height={size}",
            f"--export-background={EXPORT_BACKGROUND}",
            "--export-background-opacity=1",
            "--export-png-color-mode=RGB_8",
        ],
        env=tool_env(),
        check=True,
    )


def generate_windows_ico() -> None:
    with tempfile.TemporaryDirectory(prefix="typesync-app-icon-") as temp_dir:
        temp_root = Path(temp_dir)
        png_payloads: list[tuple[int, bytes]] = []

        for size in WINDOWS_ICON_SIZES:
            png_path = temp_root / f"icon-{size}.png"
            export_png(size, png_path)
            png_payloads.append((size, png_path.read_bytes()))

        ico_bytes = build_ico(png_payloads)
        WINDOWS_ICON.parent.mkdir(parents=True, exist_ok=True)
        WINDOWS_ICON.write_bytes(ico_bytes)
        print(f"Generating {WINDOWS_ICON.relative_to(REPO_ROOT)}")


def build_ico(images: list[tuple[int, bytes]]) -> bytes:
    header = struct.pack("<HHH", 0, 1, len(images))
    entries: list[bytes] = []
    payload = bytearray()
    offset = 6 + (16 * len(images))

    for size, data in images:
        width = 0 if size >= 256 else size
        height = 0 if size >= 256 else size
        entries.append(
            struct.pack(
                "<BBBBHHII",
                width,
                height,
                0,
                0,
                1,
                32,
                len(data),
                offset,
            )
        )
        payload.extend(data)
        offset += len(data)

    return header + b"".join(entries) + payload


def tool_env() -> dict[str, str]:
    env = os.environ.copy()
    env["HOME"] = str(TOOL_HOME)
    env["XDG_CONFIG_HOME"] = str(TOOL_HOME / ".config")
    env["XDG_CACHE_HOME"] = str(TOOL_HOME / ".cache")
    return env


if __name__ == "__main__":
    raise SystemExit(main())

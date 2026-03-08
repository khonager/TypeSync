#!/usr/bin/env python3
"""Normalize legacy Firestore note documents.

Fixes malformed `notes.type` values (outside current NoteType range 0..2).
Optionally backfills common missing fields used by the app.

Usage:
  cd functions
  python scripts/migrate_note_types.py --dry-run
  python scripts/migrate_note_types.py
"""

from __future__ import annotations

import argparse
from typing import Any

try:
  import firebase_admin
  from firebase_admin import firestore
except ModuleNotFoundError as exc:
  raise SystemExit(
      "Missing dependency: firebase_admin.\n"
      "Install dependencies from the functions directory:\n"
      "  python -m pip install -r requirements.txt\n"
      "Then re-run this script."
  ) from exc

from google.auth.exceptions import DefaultCredentialsError


VALID_TYPE_MIN = 0
VALID_TYPE_MAX = 2  # NoteType: text(0), markdown(1), pdf(2)


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(description="Migrate invalid Firestore note types.")
  parser.add_argument(
      "--collection",
      default="notes",
      help="Collection name to scan (default: notes).",
  )
  parser.add_argument(
      "--batch-size",
      type=int,
      default=400,
      help="Write batch size (default: 400; max Firestore batch is 500).",
  )
  parser.add_argument(
      "--dry-run",
      action="store_true",
      help="Print what would change without writing updates.",
  )
  parser.add_argument(
      "--fix-missing-fields",
      action="store_true",
      help="Also backfill common optional fields used by the app.",
  )
  return parser.parse_args()


def is_valid_type(value: Any) -> bool:
  return isinstance(value, int) and VALID_TYPE_MIN <= value <= VALID_TYPE_MAX


def normalized_type(value: Any) -> int:
  if isinstance(value, int) and VALID_TYPE_MIN <= value <= VALID_TYPE_MAX:
    return value
  if isinstance(value, str):
    try:
      parsed = int(value)
      if VALID_TYPE_MIN <= parsed <= VALID_TYPE_MAX:
        return parsed
    except ValueError:
      pass
  return 0


def main() -> None:
  args = parse_args()

  if not firebase_admin._apps:
    firebase_admin.initialize_app()

  try:
    db = firestore.client()
  except DefaultCredentialsError as exc:
    raise SystemExit(
        "Google credentials not found.\n"
        "Choose one of these options, then re-run:\n"
        "  1) gcloud auth application-default login\n"
        "  2) export GOOGLE_APPLICATION_CREDENTIALS=/abs/path/service-account.json\n"
        "If needed, also set project for ADC:\n"
        "  gcloud config set project <your-project-id>"
    ) from exc
  docs = db.collection(args.collection).stream()

  scanned = 0
  changed = 0
  batch_count = 0
  committed = 0
  batch = db.batch()

  for doc in docs:
    scanned += 1
    data = doc.to_dict() or {}
    updates: dict[str, Any] = {}

    current_type = data.get("type")
    safe_type = normalized_type(current_type)
    if not is_valid_type(current_type):
      updates["type"] = safe_type
      updates["legacyType"] = current_type

    if args.fix_missing_fields:
      if "tags" not in data:
        updates["tags"] = []
      if "attachments" not in data:
        updates["attachments"] = []
      if "isFavorite" not in data:
        updates["isFavorite"] = False
      if "isDeleted" not in data:
        updates["isDeleted"] = False
      if "characterCount" not in data:
        updates["characterCount"] = 0
      if "lineCount" not in data:
        updates["lineCount"] = 0
      if "size" not in data:
        updates["size"] = 0

    if not updates:
      continue

    changed += 1
    print(f"[change] {doc.id}: {updates}")

    if args.dry_run:
      continue

    batch.update(doc.reference, updates)
    batch_count += 1

    if batch_count >= args.batch_size:
      batch.commit()
      committed += batch_count
      print(f"[commit] {committed} updates committed")
      batch = db.batch()
      batch_count = 0

  if not args.dry_run and batch_count > 0:
    batch.commit()
    committed += batch_count
    print(f"[commit] {committed} updates committed")

  print("\nDone.")
  print(f"Scanned: {scanned}")
  print(f"Would change: {changed}" if args.dry_run else f"Changed: {changed}")


if __name__ == "__main__":
  main()

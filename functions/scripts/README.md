# Migration Scripts

## `migrate_note_types.py`

Normalizes malformed Firestore note docs, especially legacy `type` values outside current enum range (`0..2`).

### Run

From `functions/` install dependencies first:

```bash
python -m pip install -r requirements.txt
```

If `python -m pip` fails with `No module named pip` (common on Nix system Python),
create/use a virtual environment:

```bash
python3 -m venv venv
source venv/bin/activate
python -m pip install -r requirements.txt
```

If `functions/venv` already exists but shows `bad interpreter`, recreate it:

```bash
rm -rf venv
python3 -m venv venv
source venv/bin/activate
python -m pip install -r requirements.txt
```

If you use a virtual environment (recommended):

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

If you are using ADC/service-account auth locally, configure one of:

```bash
gcloud auth application-default login
gcloud config set project <your-project-id>
```

or:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/service-account.json"
```

Then run:

```bash
python scripts/migrate_note_types.py --dry-run
python scripts/migrate_note_types.py
```

### Optional flags

- `--fix-missing-fields` to backfill common optional fields (`attachments`, `tags`, etc.)
- `--batch-size 400` to control write batch size (must be <= 500)
- `--collection notes` to target another collection name

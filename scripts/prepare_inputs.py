"""Materialize every provider export into staged/ for dbt to read.

Every input is strict-decoded to UTF-8 with normalized line endings, so dbt reads
one directory of uniform files. raw/ is never written to.
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from normalize_encoding import normalize

RAW = Path("raw")
STAGED = Path("staged")

# filename -> encoding the provider declares, used only if the UTF-8 probe fails
INPUTS = {
    "payment_engine_log.csv": "utf-8",
    "paypal_us_activity_20260601_20260703.csv": "utf-8",
    "paypal_eu_activity_20260601_20260703.csv": "cp1252",
    "adyen_payment_accounting_20260601_20260703.csv": "utf-8",
    "dlocal_transactions_20260601_20260703.csv": "utf-8",
    "google_play_earnings_202606.csv": "utf-8",
    "google_play_earnings_202607_partial.csv": "utf-8",
    "fx_rates.csv": "utf-8",
    "fee_schedule.csv": "utf-8",
}


def prepare() -> list[dict]:
    STAGED.mkdir(exist_ok=True)
    manifest = []

    for filename, declared in INPUTS.items():
        src, dst = RAW / filename, STAGED / filename
        if not src.exists():
            raise FileNotFoundError(f"missing input: {src}")
        manifest.append(normalize(src, dst, declared))

    (STAGED / "_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main() -> int:
    argparse.ArgumentParser(description=__doc__).parse_args()
    try:
        manifest = prepare()
    except (UnicodeDecodeError, FileNotFoundError) as e:
        print(f"QUARANTINE: {e}", file=sys.stderr)
        return 1

    for e in manifest:
        print(f"{Path(e['dst']).name:<48} {e['encoding_used']:<9} "
              f"{e['lines']:>6} lines  {e['crlf_stripped']:>6} crlf")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

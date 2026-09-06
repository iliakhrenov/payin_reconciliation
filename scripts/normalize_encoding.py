"""Normalize a provider export to UTF-8 before it reaches dbt.

Fails loudly rather than emitting replacement characters: a half-decoded
merchant name is a reconciliation that half-works.
"""

import argparse
import hashlib
import json
import sys
import unicodedata
from pathlib import Path

# utf-32 first: its LE BOM starts with the utf-16 LE BOM
BOMS = [
    (b"\xff\xfe\x00\x00", "utf-32"),
    (b"\x00\x00\xfe\xff", "utf-32"),
    (b"\xef\xbb\xbf", "utf-8-sig"),
    (b"\xff\xfe", "utf-16"),
    (b"\xfe\xff", "utf-16"),
]


def normalize(src: Path, dst: Path, declared: str = "cp1252") -> dict:
    data = src.read_bytes()

    for bom, enc in BOMS:
        if data.startswith(bom):
            encoding = enc
            break
    else:
        try:
            data.decode("utf-8", errors="strict")
            encoding = "utf-8"          # already converted upstream
        except UnicodeDecodeError:
            encoding = declared

    text = data.decode(encoding, errors="strict")   # let it raise

    nfc = unicodedata.normalize("NFC", text)
    out = nfc.replace("\r\n", "\n")
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(out, encoding="utf-8", newline="\n")

    return {
        "src": str(src),
        "dst": str(dst),
        "declared": declared,
        "encoding_used": encoding,
        "sha256_in": hashlib.sha256(data).hexdigest(),
        "sha256_out": hashlib.sha256(out.encode("utf-8")).hexdigest(),
        "bytes_in": len(data),
        "bytes_out": len(out.encode("utf-8")),
        "nfc_changed": nfc != text,
        "crlf_stripped": text.count("\r\n"),
        "lines": out.count("\n"),
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("src", type=Path)
    p.add_argument("dst", type=Path)
    p.add_argument("--declared", default="cp1252", help="fallback encoding (default: cp1252)")
    a = p.parse_args()

    try:
        report = normalize(a.src, a.dst, a.declared)
    except UnicodeDecodeError as e:
        print(
            f"QUARANTINE {a.src}: strict decode failed at byte {e.start} "
            f"using '{e.encoding}' -- declared encoding is wrong ({e.reason})",
            file=sys.stderr,
        )
        return 1

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

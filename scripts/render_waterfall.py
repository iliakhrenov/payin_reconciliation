"""Render the reconciliation waterfall as the markdown table the CFO summary opens with.

Reads exports/recon_waterfall_<month>.csv, which dbt writes on every build. The Total column
is computed here rather than stored: a total row in the model would sit at a different grain
from the per-provider rows and invite double-counting.

    uv run python scripts/render_waterfall.py [--month 2026-06]
"""

import argparse
import csv
import sys
from pathlib import Path

LINE_LABELS = {
    "backend_booked": "Backend booked",
    "backend_fx_faults": "Backend FX faults",
    "backend_restated": "Backend restated",
    "provider_variance": "Provider variance",
    "provider_gross": "Provider gross",
    "provider_fees": "Provider fees",
    "net_receipts": "Net receipts",
}

PSP_LABELS = {
    "adyen": "Adyen",
    "dlocal": "dLocal",
    "google_play": "Google Play",
    "paypal_eu": "PayPal EU",
    "paypal_us": "PayPal US",
}


def money(value: float, bold: bool) -> str:
    """Accounting format: parentheses for negatives, em-dash for nil, bold for subtotals."""
    if abs(value) < 0.005:
        cell = "—"
    elif value < 0:
        cell = f"({abs(value):,.2f})"
    else:
        cell = f"{value:,.2f}"
    return f"**{cell}**" if bold and cell != "—" else cell


def render(rows: list[dict]) -> str:
    psps = sorted({r["psp"] for r in rows})
    lines = sorted({int(r["line_seq"]) for r in rows})

    by_seq: dict[int, dict] = {}
    for r in rows:
        seq = int(r["line_seq"])
        entry = by_seq.setdefault(
            seq,
            {"item": r["line_item"], "subtotal": r["is_subtotal"].lower() == "true", "by_psp": {}},
        )
        entry["by_psp"][r["psp"]] = float(r["usd"])

    header = [""] + [PSP_LABELS.get(p, p) for p in psps] + ["**Total**"]
    out = [
        "| " + " | ".join(header) + " |",
        "| --- |" + " ---: |" * (len(psps) + 1),
    ]

    for seq in lines:
        entry = by_seq[seq]
        bold = entry["subtotal"]
        label = LINE_LABELS.get(entry["item"], entry["item"])
        label = f"**{label}**" if bold else label

        cells = [money(entry["by_psp"].get(p, 0.0), bold) for p in psps]
        total = sum(entry["by_psp"].get(p, 0.0) for p in psps)
        cells.append(f"**{money(total, False)}**")

        out.append("| " + " | ".join([label] + cells) + " |")

    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--month", default="2026-06", help="reporting month, YYYY-MM")
    parser.add_argument("--exports", default="exports", type=Path)
    args = parser.parse_args()

    path = args.exports / f"recon_waterfall_{args.month}.csv"
    if not path.exists():
        print(f"missing {path} - run `dbt build` first", file=sys.stderr)
        return 1

    with path.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))

    if not rows:
        print(f"{path} is empty", file=sys.stderr)
        return 1

    print(render(rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

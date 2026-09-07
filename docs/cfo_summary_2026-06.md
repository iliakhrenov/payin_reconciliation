# Payin reconciliation — June 2026

**Providers report $127,062.78 net for June across five accounts. The backend and the providers now tell the same story, and every dollar of difference is accounted for — nothing is unexplained.**

Our backend payment engine said $335,668.57 gross. That figure is wrong by $200,679.50 and must be restated before anything else is discussed.

## The one number that matters

**Our payment backend engine overstates June gross revenue by $200,679.50.** Three dLocal transactions were booked with no currency conversion applied at all — local amounts entered the ledger as if they were dollars.

| Transaction | Currency | Local | Booked as | Actually worth | Overstated |
| --- | --- | --- | --- | --- | --- |
| TXN-107965 | COP | 199,900.00 | $199,900.00 | $48.78 | $199,851.22 |
| TXN-107964 | MXN | 799.00 | $799.00 | $44.08 | $754.92 |
| TXN-107963 | BRL | 89.90 | $89.90 | $16.60 | $73.30 |

dLocal independently reports the correct figure on all three, so the restatement is evidenced, not inferred. This is a backend defect, not a provider dispute — no money is missing, it was never there.

Three further FX faults are immaterial in total ($1.06) but are the same class of defect: two transactions priced against the wrong day's rate, one against a rate the provider had since republished.

## June waterfall

|  | Adyen | dLocal | Google Play | PayPal EU | PayPal US | **Total** |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Backend booked | 32,912.09 | 215,642.53 | 14,744.63 | 36,323.01 | 36,046.31 | **335,668.57** |
| Backend FX faults | 0.03 | (200,678.97) | — | (0.56) | — | **(200,679.50)** |
| **Backend restated** | **32,912.12** | **14,963.56** | **14,744.63** | **36,322.45** | **36,046.31** | **134,989.07** |
| Provider variance | (115.98) | (14.11) | — | (92.35) | 34.98 | **(187.46)** |
| **Provider gross** | **32,796.14** | **14,949.45** | **14,744.63** | **36,230.10** | **36,081.29** | **134,801.61** |
| Provider fees | (829.42) | (751.25) | (2,249.20) | (1,700.50) | (2,208.46) | **(7,738.83)** |
| **Net receipts** | **31,966.72** | **14,198.20** | **12,495.43** | **34,529.60** | **33,872.83** | **127,062.78** |

## Discrepancy by cause

**Total absolute discrepancy $205,576.14 across 21 transactions and 4,712 fee lines. Unexplained: $0.00.**

| Scope | Matched rows | Explained rows | Unexplained rows | Absolute USD | Signed USD |
| --- | ---: | ---: | ---: | ---: | ---: |
| Backend FX faults | 7,707 | 6 | 0 | 200,680.50 | (200,679.50) |
| Gross — backend vs provider | 7,702 | 15 | 0 | 293.40 | (187.46) |
| Fees — provider vs contract | 2,334 | 4,712 | 0 | 4,602.24 | (4,602.24) |

Signed figures are the impact on net USD receipts. Negative means the payment engine's books overstate what we keep.

### What is worth acting on

Six causes carry real money. Each is sized against the book it belongs to — that base changes from row to row, so it is spelled out rather than left as a bare percentage.

| Cause | Who has to fix it | USD | Sized against |
| --- | --- | ---: | --- |
| FX conversion not applied on 3 dLocal transactions | **Our payment engine** | 200,679.44 | 93% of everything our engine booked for dLocal |
| Fees charged with no contract on file | **Our contract file** | 2,208.46 | all of PayPal US's June fee bill |
| Fees charged with no contract on file | **Our contract file** | 1,700.50 | all of PayPal EU's June fee bill |
| Fees charged with no contract on file | **Our contract file** | 682.56 | 91% of dLocal's June fee bill † |
| Fee overcharge against contract | Google Play | 9.00 | 0.4% of Google Play's June fee bill |
| Fee overcharge against contract | Adyen | 1.72 | 0.2% of Adyen's June fee bill |

† Why 91% and not 100%: the other 9% is not contracted either — none of dLocal's fee bill is. The remaining $68.69 is billed on 109 declined attempts and one disputed transaction, where no money moved, so there is nothing to reconcile it against and it sits outside the fee scope entirely. dLocal is the only provider that charges on transactions that never settled; the other four return zero.

**Five of the six are ours.** Only the last two are a provider doing something we did not agree to; the top four are our engine mis-booking and our own contract file being incomplete. The dLocal FX fault in particular is not a dLocal problem — dLocal reported those three transactions correctly and our engine failed to convert them.

So June has exactly two stories. One engine defect worth 93% of what we booked for dLocal, and $4,591.52 of fees we are paying without a contract to check them against.

### Gross variance — all 15 transactions

Here is how the rest of the reconciliation looks like in detail:

$187.46 net on $134.8k of settled volume: 0.14%. Fifteen transactions, individually named.

| Provider | Order | Cause | USD | What happened |
| --- | --- | --- | ---: | --- |
| PayPal EU | ORD-507788 | psp_claims_chargeback | (65.36) | Chargeback the backend never booked |
| Adyen | ORD-507808 | psp_claims_chargeback | (64.79) | Chargeback the backend never booked |
| PayPal EU | ORD-507806 | psp_claims_refund | (26.99) | Refund the backend never booked |
| Adyen | ORD-507792 | psp_claims_partial_capture | (26.15) | Adyen captured less than authorised |
| PayPal US | ORD-507786 | engine_capture_not_recorded | 24.99 | PayPal settled and charged its fee; the backend row is still `pending` |
| Adyen | ORD-507793 | psp_claims_partial_capture | (14.21) | Adyen captured less than authorised |
| Adyen | ORD-507785 | psp_claims_declined | (10.90) | Backend booked a sale Adyen refused |
| Adyen | ORD-507811 | psp_claims_sale | 10.86 | Adyen settled a sale the backend has no row for |
| Adyen | ORD-507794 | psp_claims_captured_different_period | (10.79) | Backend captured 28 Jun, Adyen settled 2 Jul |
| PayPal US | ORD-507809 | psp_claims_duplicate_row | 9.99 | PayPal exported the same line twice |
| dLocal | ORD-507812 | engine_claims_sale | (7.42) | Backend has the sale; dLocal's export omits it |
| dLocal | ORD-507807 | psp_claims_different_amount | (7.36) | dLocal refunded 50%, backend booked 30% |
| dLocal | ORD-507810 | psp_claims_duplicate_row | 7.13 | dLocal exported the same line twice |
| dLocal | ORD-507787 | psp_claims_disputed | (6.45) | dLocal in mediation; backend says settled |
| dLocal | ORD-507781 | psp_fx_date_basis | (0.01) | Month-boundary sale, rounding |

Google Play ties to $0.00 — see caveat below on what that does and does not prove.

## Fees

$7,738.83 charged in June. Only $3,078.62 of it can be checked against a contract.

| | Fees | Contract on file | Variance |
| --- | ---: | --- | ---: |
| Adyen | 829.42 | yes | (1.72) |
| Google Play | 2,249.20 | yes | (9.00) |
| dLocal | 751.25 | **no** | (682.56) |
| PayPal EU | 1,700.50 | **no** | (1,700.50) |
| PayPal US | 2,208.46 | **no** | (2,208.46) |

dLocal is the only row where variance is smaller than the fee bill. The $68.69 difference is billed on declined and disputed transactions, which are outside the fee reconciliation — see the footnote above. It is uncontracted too, just unreconcilable.

**Where contracts exist, the providers are close to right.** Two Adyen fees over by $1.72 total.

**Google Play overcharged $9.00 — six transactions billed at 30% against a contracted 15%.** All on 2026-06-17 between 02:21 and 07:30 LA, all US / USD / `sub_monthly` / $9.99. Charges either side of that window are billed correctly, which reads as a pricing-tier misapplication for a few hours. Recoverable.

**$4,591.52 of fees cannot be verified because we hold no contract.** dLocal charges a flat 4.5% and PayPal 3.49% + $0.49 (US) / 2.90% + €0.35 / 2.90% + £0.30 (EU), consistently on every settled sale. These look like real commercial terms, and they are booked as charged. But contract fees data has no dLocal or PayPal entry, so nothing confirms the rates. **Retrieving those two contracts is the single highest-value follow-up in this report** — it converts 59% of June's fee spend from unverifiable to checked.

## Caveats

**Google Play's $0.00 tie is weaker evidence than it looks.** The backend does not initiate these purchases; it creates its row from Google's own notification. Both sides share a source, so the reconciliation proves clean ingestion — it cannot detect a transaction Google never reported. Google Play is also the only provider with zero declines and zero chargebacks in the backend log, where the others run 7–8% declines.

**No fee is returned on any reversal.** $2,121.17 was refunded or charged back in June and the providers kept the original processing fee on all of it. That is a real cost with no contract stating it, so it is named here rather than booked as a discrepancy.

**dLocal charged $68.69 in fees on transactions where no money moved** — 109 declined attempts and one disputed transaction. The export gives no way to tell whether dLocal actually bills these. Flagged, not booked; the contract retrieval settles it.

**One transaction is in dispute.** dLocal holds ORD-507787 (BRL 34.90, $6.45) in mediation while the backend calls it settled. Treated as unsettled — dLocal charged its 4.5% regardless.

**The June Google Play file is not June.** Google cuts its statement on LA-local dates, so it contains one $9.99 transaction that is July on our basis. Both sides agree it is July, so it carries no discrepancy — noted so Google's statement total ties to the figure above rather than appearing $9.99 off.

**Period basis.** A transaction belongs to the month it settled in. One Adyen sale captured 28 June settles 2 July and appears in June on one side only — a real month-end timing difference, reported rather than netted away.

## The numbers behind this

`exports/recon_summary_2026-06.csv` — provider × scope × cause, with row counts, absolute and signed USD, the base each is measured against, and three share columns.

## What we are asking for

Detail, owners and evidence in [`action_items.md`](action_items.md).

1. **Fix the FX conversion gap in the payment backend** — $200,679.50 mis-booked in one month on three transactions. Highest severity.
2. **Retrieve the dLocal and PayPal contracts** — unlocks $4,591.52/month of unverifiable fees. If those are standard rates -- reflect them as a contract with a `is_default` flag.
3. **Recover $9.00 from Google Play** and ask why the rate moved for four hours.
4. **Three reversals and one capture never reached the backend** — $132.15 net. Worth understanding as a pattern, not four one-offs.

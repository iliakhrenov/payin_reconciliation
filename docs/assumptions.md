# Assumptions

Calls made where the data is ambiguous. Each one is enforced in code and tested.

## FX

**The engine prices at the last published business day, not the transaction date.**
`fx_rates` publishes business days only (and skips 2026-06-19). The engine applies the most
recent rate on or before the transaction date — true for 5,145 of 5,147 foreign-currency rows.
That rule, not the transaction date, is the baseline the two exceptions are measured against.

**A republished rate supersedes the original; it is not a second as-of rate.**
BRL 2026-06-10 was published twice — 0.185352, then 0.190542 two days later. dLocal priced
every BRL transaction that day at the corrected rate, and so did the engine for 23 of 24. So
the correction is authoritative and the original is simply wrong. `stg__fx_rates` ranks
versions and consumers pin `is_current_rate`.

**Wrong rates are restated. A wrong rate *date* is only flagged.**
Where the engine's rate disagrees with the published rate for the day it chose, the conversion
is redone — dLocal independently reports the restated figure for all four such rows, so the
correction is evidenced, not inferred. Where the rate is right but priced against the wrong
day, nothing is restated: providers report local amounts only and cannot say which day was
correct. Those two rows carry a reason code and are settled in the provider reconciliation.

**Corrections never overwrite.** `amount_usd_engine` is the backend's claim and is preserved
untouched; `amount_usd_recon` is the restated figure. The difference is the FX share of the
discrepancy — the number the reconciliation exists to report — so it has to stay visible.

# Assumptions

Calls made where the data is ambiguous. Every one is enforced in code and covered by a test — if an assumption stops holding, the build fails rather than the number quietly changing.

Seven decisions carry the report. The rest are listed as one-liners; each is in the model it names.

## The calls that carry the report

**Both sides are priced at the last rate published on or before the transaction date.**
`fx_rates` publishes business days only and skips 2026-06-19 entirely, so pricing on the transaction date is impossible. This "as-of" rule is not our invention — the engine already follows it on 5,145 of its 5,147 foreign-currency rows, so its own dominant behaviour sets the baseline and the two deviants are measured against it. Providers report local amounts and are re-priced the same way, which is what makes a matched row show zero FX noise instead of rounding chatter.

**A correction never overwrites the original.**
`amount_usd_engine` is preserved untouched as the backend's claim; `amount_usd_recon` is the restated figure. The difference *is* the FX share of the discrepancy — $200,679.50 of it — so overwriting would erase the single largest finding in the report. This is why the reconciliation has a scope for the backend against itself at all.

**The unit of reconciliation is provider × order reference × operation.**
Not the transaction id. Adyen reuses the original sale's PSP reference for every refund and chargeback while the engine mints a fresh one, so a PSP-reference join silently loses every one of the 38 reversals in the export. Order plus operation is the only key every provider agrees on. Each staging model derives a `match_key` from **its own columns only** — the order reference where one exists, and for Google Play, which publishes no identifier at all, the UTC capture timestamp plus SKU and country. Neither side ever reads the other's columns, so the two remain independent evidence. `assert_recon_grain` fails the build if any provider stops being 1:1.

**Settlement is recognition, so a transaction belongs to the month it settled in.**
Where a provider settles, its settlement time decides the period; otherwise the attempt does. A sale the backend captures on 28 June and Adyen settles on 2 July therefore counts in June on one side and July on the other. That is a real month-end difference and it is reported as one rather than netted away.

**A declined attempt is worth zero dollars.**
Both sides carry the attempted amount, but only money that moved is reconciled. This is what turns "the engine booked a sale the provider refused" into its full value instead of nothing.

**Fees are a third reconciliation, never part of the second.**
The backend records no fees at all, so a fee variance is the provider against the contract — not the provider against the backend. Different counterparties, so the two never net against each other; adding them would imply the backend held a fee opinion to disagree with. They share a grain, so they share a summary.

**A fee the provider reports is a fee we paid, contract or no contract.**
`fee_schedule.csv` is our record of what was agreed, not evidence of what was charged — and a provider processing 1,150 transactions for free is not a credible reading. So where a settled sale carries a fee we hold no contract for, the whole charge is booked against us as `psp_claims_fee_out_of_contract`: $4,591.52 across dLocal and both PayPal accounts. The gap is in our contract file, not in the charge.

**Only settled sales are fee-reconciled.**
Providers return no fee on a refunded or charged-back sale and no contract on file says they should. The fee retained on a reversal is a real cost that stays with us, but it is a commercial term to renegotiate, not a reconciliation break. One consequence worth knowing: dLocal also bills 4.5% on 109 declined attempts and one disputed row — $68.69 that no money moved against. It sits outside the fee scope and is reported as a caveat, which is why dLocal's out-of-contract figure is 91% of its fee bill rather than 100%. It is uncontracted too, just unreconcilable.

**The whole thing is one waterfall, not three exercises.**
What the backend booked, plus its own FX faults, plus the provider variance, equals what the provider says it took — then fees carry that down to net. Each section hands a clean number to the next, which is why FX is settled first: a gross comparison is meaningless until both sides believe the same rate. `assert_recon_waterfall_closes` fails the build if the identity breaks.

## Everything else

**FX**
- A republished rate supersedes the original rather than being a second as-of rate — BRL 2026-06-10 was published twice, and both dLocal and the engine used the correction. `stg__fx_rates` ranks versions; consumers pin `is_current_rate`.
- Every row is priced at the as-of rate including the six the engine got wrong, so there is one pricing basis.

**Naming**
- A cause names the claimant, not our verdict: `psp_claims_*` is the provider asserting something the backend does not, `engine_claims_*` the reverse, `engine_fx_*` the backend's own booking at fault. The prefix alone says which side to go and ask.
- Negative always means the same thing in every scope — the backend's books overstate what we actually keep — so the scopes can be added for a total.

**Adyen**
- Only `Settled` rows carry money; `Authorised` duplicates gross on 1,617 of 1,619 sales and must never be summed.
- The contracted 2.5% is `Commission + Markup`, never `Commission` alone — Adyen splits it, and checking the first column alone fails on every row.
- A partial capture is priced on what was captured, which is why June's GBP effective rate reads 2.480% rather than 2.500%.
- `Batch Number` is not a period filter — batch 27 straddles the month end.
- `Creation Date` is Europe/Amsterdam; converted to UTC it matches the engine exactly, unconverted it matches nothing.

**dLocal**
- `local_amount` is minor units scaled by the row's own `currency_exponent` — CLP carries 0 and the rest carry 2, so a blanket ÷100 is wrong in both directions. 1,318 of the export's 1,319 lines then tie to the engine's local amount; the miss is the under-booked ORD-507807 refund.
- `IN_MEDIATION` is not settlement — disputed money is not confirmed ours, so ORD-507787 is treated as unsettled and reported as a $6.45 break.
- The byte-identical duplicated export line is a defect, not a second payment. Deduplicated in staging, kept in the report at +$7.13 so dLocal's own total still explains.
- dLocal's `usd_amount` is a cross-check only; its `fx_rate` is inverted (local per USD) and both sides are re-priced at our published rate regardless.
- ORD-507781 straddles the month boundary and we accept the $0.01: importing the engine's timestamp to fix it would destroy the independence of the two sides for one cent.

**Google Play**
- The LA-local timestamp converted to UTC is the join key — it matches the engine on 820 of 820 rows, unconverted it matches 0. SKU and country resolve the single collision.
- Capture is the recognition time; Google publishes no authorisation instant.
- Google's USD fee is taken as reported, not recomputed from the local column — recomputing disagrees by a cent on 59 rows and would surface as a fake fee variance.
- Google's own conversion rate equals our published as-of rate on all 130 non-USD (currency, date) pairs, so it is a cross-check and changes nothing.
- The June file is not June: Google cuts on LA-local dates, so it contains one $9.99 transaction that is July on our basis. Both sides agree, so it carries no discrepancy — listed only so Google's statement total ties.
- A $0.00 tie here means the feed is clean, not that revenue is confirmed. The backend builds its row from Google's notification, so both sides share a source; it cannot detect a transaction Google never reported.

**PayPal**
- The two files are one PSP with two accounts, differing only in dialect. 2,166 export rows land on US and 1,893 on EU, none elsewhere. The engine holds 1,891 EU rows — the two-row gap is exactly ORD-507788 and ORD-507806, the reversals it never booked.
- `Transaction ID` is the row-level join key, not `Invoice ID`, which fans out to 2 on reversals.
- `Time Zone = GMT` is taken at face value because it verifies — parsed timestamps equal the engine's `captured_at_utc` to the second on 3,741 of 3,742 settled rows. The single miss is ORD-507786, where the engine has no capture at all. No conversion is applied; adding one would break every row.
- Three PayPal EU rows are `MM/DD/YYYY` inside a `DD/MM/YYYY` file. The rule: parse each row in its file's declared order, and where that lands outside the export's own declared window (`export_window_start`/`end` in `dbt_project.yml`, taken from the filenames), re-parse in the other order. Applied symmetrically — US fires zero overrides, EU fires exactly three, and `assert_paypal_date_format_override_is_bounded` pins it there. Trusting the file-level format instead invents a €29.97 break. Deriving the window from the file's own unambiguous rows does not work, because only days > 12 are self-evident.
- `Denied` rows carry an attempted amount that is not money — all 315 have `Fee = 0` and `Net = 0`. Counted, never summed.
- Signs are taken from the file: PayPal already signs reversals negative, so the engine side is the one that gets a derived sign.
- PayPal's fee is exact on all 3,645 distinct settled sales (3,646 export lines, one a duplicate) at 3.49% + $0.49, 2.90% + €0.35, 2.90% + £0.30.
- The fixed fee is per-currency and `fee_schedule` cannot express that today — adding PayPal needs one row per currency, not one row with a currency caveat.
- The fee retained on all 99 reversals is reported, not booked: no contract we hold states it and the export cannot separate "kept by policy" from "not applicable".
- ORD-507786 gets its own cause, `engine_capture_not_recorded`, ahead of the period branches — the engine has no period at all, not a different one, so filing it as timing would read as self-correcting next month.

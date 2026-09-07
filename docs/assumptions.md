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

**Every row is priced at the as-of rate, including the ones with the wrong date.**
The reconciliation needs one pricing basis or the two sides are not comparable, so
`amount_usd_recon` is the local amount at the rate published for the as-of date — no carve-outs.
For the four rows where the rate itself was wrong the correction is evidenced, not inferred:
dLocal independently reports the restated figure. For the two priced against the wrong day the
engine adjudicates itself — it follows the as-of rule on 5,145 of 5,147 foreign-currency rows,
so its own dominant behaviour convicts the deviants. We do not need the provider to arbitrate.

**Corrections never overwrite.** `amount_usd_engine` is the backend's claim and is preserved
untouched; `amount_usd_recon` is the restated figure. The difference is the FX share of the
discrepancy — the number the reconciliation exists to report — so it has to stay visible.

## Reconciliation

**The unit of reconciliation is provider × order reference × operation.** Not the transaction id — for Adyen the engine issues its own reference for every refund and chargeback while the provider reuses the original sale's, so a PSP-reference join loses them. (dLocal is the opposite: it mints a fresh id per refund and the engine records it, so the reference happens to hold there.) Order reference plus operation is the only key every provider agrees on. A full outer join on it is 1:1 for Adyen, and a test fails the build if any provider breaks that.

**A transaction belongs to the period it was recognised in, and settlement is recognition.** Where a provider settles, its settlement time decides the period; otherwise the attempt does. So a sale the backend captures on 28 June and Adyen settles on 2 July counts in June on one side and July on the other. That is a real month-end difference, not a matching failure, and it is reported as one rather than netted away.

**A declined attempt is worth zero dollars.** Both sides carry the attempted amount, but only money that moved is reconciled. This is what turns "the engine booked a sale the provider refused" into its full value instead of nothing.

**Both sides are valued at the same published rate.** Providers report local amounts; USD comes from the last rate published on or before the transaction date — the same as-of rule the engine is held to. A matched row therefore shows no FX noise, and where the engine priced against the wrong day the difference surfaces in dollars instead of disappearing.

**The cause name says who is making the claim.** `psp_claims_*` is the provider asserting something the backend does not; `engine_claims_*` is the backend asserting something the provider does not; `engine_fx_*` is the backend's own booking at fault. Reading a summary, the prefix alone says which side to go and ask — which is why a cause names the claimant, not our verdict. `psp_claims_different_amount` covers a refund we believe the backend under-booked, because the provider is still the party that moved the money.

**Fees are a third reconciliation, not part of the second.** The backend records no fees, so a fee variance is the provider against the contract, not the provider against the backend. They share a grain, so they share a row and a summary — but they never net against each other, because the counterparties are different and adding them would imply the backend had a fee opinion to disagree with.

**Only settled sales are fee-reconciled.** Providers return no fee when a sale is refunded or charged back, and no contract on file says they should. The fee on a reversed sale is a real cost that stays with us; it is a commercial term to renegotiate, not a reconciliation break.

**A fee the provider reports is a fee we paid, contract or no contract.** `fee_schedule` is our record of what was agreed, not evidence of what was charged — and a provider processing 1,150 transactions for nothing is not a credible reading. So where a settled sale carries a provider fee we hold no contract for, the whole charge is booked against us as `psp_claims_fee_out_of_contract`. The gap is in our contract file, not in the charge. A settled sale with no contract *and* no fee stays `fee_not_contracted` at zero dollars, still visible as a row count.

**Negative always means the same thing.** In both scopes the signed figure is the impact on net USD receipts: negative means the backend's books overstate what we actually keep. Gross and fees can therefore be added for a total, even though they are measured against different counterparties.

**The reconciliation is a waterfall, not three separate exercises.** What the backend booked, plus its own bugs, plus the provider variance, equals what the provider says it took — then fees carry that down to net. Each section hands a clean number to the next, which is why FX faults are settled in the first one: a gross comparison is only meaningful once both sides believe the same rate. A test fails the build if the identity stops holding.

## Adyen

**Only `Settled` rows carry money.** Adyen emits two rows per transaction — `Authorised` then `Settled` — and gross is identical on 1,617 of 1,619. Summing both double-counts June. `Settled` is the row with the fees, the settlement timestamp that matches the engine's `captured_at_utc`, and the money that actually moved. `Refused` never settled and is not a discrepancy; it is counted, never added. A test fails the build if an `Authorised` row reaches a sum.

**The join is `Merchant Reference` plus operation, not `Psp Reference`.** The engine mints a fresh reference for each of the 37 refunds and chargebacks while Adyen reuses the original sale's, so a PSP-reference join collapses every reversal onto its sale. This is the case that set the framework's key for every provider.

**The contracted fee is `Commission + Markup`, never `Commission` alone.** The contract says 2.5%; Adyen reports it split — `Commission` at 1.9% of gross and `Markup` as the remainder to 2.5%. Checking `Commission` against the contract fails on all 1,619 settled rows and would report the entire book as undercharged by 0.6%. Summed, the formula is exact on 1,617 of 1,619, and `Net Credit` ties with zero residual.

**A partial capture is priced on what was captured.** ORD-507793 authorises GBP 21.99 and settles GBP 11.00; Adyen charges its 2.5% on the 11.00. That is correct behaviour, and it is why June's GBP effective rate reads 2.480% rather than 2.500% — the apparent 0.02pp shortfall is the partial capture already counted in the gross scope, not a fee variance. Booking it twice was the trap.

**`Batch Number` is not a period filter.** Batches run Mon–Sun (23–27 across the export) and batch 27 straddles the month end — it authorises ORD-507794 in June and settles it in July. The period is decided by the UTC settle date, like every other provider.

**`Creation Date` is Europe/Amsterdam, and converting it verifies.** UTC+2 in June. Converted, `Authorised` equals the engine's `created_at_utc` on all 1,618 joinable sales and `Settled` equals `captured_at_utc` on 1,617 — the one miss being the July settlement above. Taken unconverted, nothing matches.

## dLocal

**`local_amount` is minor units, scaled by the row's own `currency_exponent`.** CLP carries exponent 0 and the other four currencies carry 2, so a blanket ÷100 is wrong in both directions. Scaled per row, 1,318 of 1,319 rows tie to the engine's local amount exactly — the engine adjudicates the rule.

**`IN_MEDIATION` is not settlement.** dLocal has one such row (`ORD-507787`, BRL 34.90) where the engine says settled. Mediation means the money is disputed and not confirmed ours, and only money that moved is reconciled — so it is treated as unsettled and reported as a $6.45 discrepancy rather than matched. dLocal charges its 4.5% on it regardless.

**The duplicated export line is a defect, not a second payment.** `DL-90001316` / `ORD-507810` appears twice, byte-identical, on adjacent lines. Staging deduplicates on the full row. Kept in the discrepancy report at +$7.13 so the provider's own total is explained rather than silently corrected.

**dLocal's `usd_amount` is a cross-check, not an input.** Its `fx_rate` is inverted (local per USD) and its USD column is internally consistent with it on 1,317 of 1,319 rows. Both sides are re-priced at the published as-of rate regardless, so the two cent-level exceptions carry no weight.

**`ORD-507781` is priced on its creation date, and we accept the cent.** The sale is created 2026-05-31 23:59:50 and settles 2026-06-01 00:05. Both dLocal and the engine use the 29 May rate; dLocal's export publishes only the settlement timestamp, so pricing the provider side off its own file gives the 1 June rate and a $0.01 break. Importing the engine's timestamp into a provider staging model would destroy the independence of the two sides for one cent, so the cent is named and classified instead of engineered away.

**dLocal's reported fee is authoritative; `fee_schedule` is incomplete.** The effective rate is exactly 4.5% on every row and `fee_schedule` has no dLocal entry at all. We treat the export as the record of what was charged and the contract file as the thing with the gap, so June's 1,150 settled sales carry $682.56 as `psp_claims_fee_out_of_contract` rather than $0.00 as unverifiable. This is the one place the reconciliation books a number the backend has no opinion on — Finance should retrieve the dLocal contract and confirm the 4.5%.

**Only settled sales carry that charge, and the rest is flagged instead.** dLocal also reports a 4.5% fee on 109 rejected attempts ($68.40) and on the disputed row ($0.29). No money moved on those, and the export gives no way to tell whether dLocal actually bills them. $68.69 is reported as a caveat rather than classified — booking it would assert a billing behaviour we cannot evidence, and it is the same contract retrieval that settles it.

## Google Play

**The provider timestamp, converted to UTC, is the join key.** The export carries no order id and the engine's `psp_reference` is null on all 820 Google Play rows, so there is no identifier to join on. Converting the LA-local timestamp to UTC matches the engine's `captured_at_utc` on 820 of 820 rows; unconverted it matches 0, and the engine's `created_at_utc` matches 0. Adding SKU and country resolves the one timestamp collision. This is a deterministic key, not fuzzy matching — a full outer join is 1:1 with nothing on either wing, and the same test that guards the other providers guards this one.

**`captured_at_utc` is the recognition time; `created_at_utc` is not in the file.** The engine records an authorisation 5 min to 1h50m before capture. Google publishes only the capture instant, so capture is what both sides are compared and periodised on — consistent with the settlement-is-recognition rule.

**Google's USD fee is taken as reported, not recomputed.** Google derives the fee in USD from the USD gross (`round(gross_usd × 15%, 2)`), not by converting the local fee. Recomputing from the local column disagrees by a cent on 59 rows ($0.33 across the file) — noise that would surface as a fake fee variance.

**Google's own conversion rate is a cross-check, not an input.** It equals our published as-of rate on all 130 (currency, date) pairs and the engine applies the same rate on every row, so both sides are re-priced at the published rate as usual and nothing changes. Note Google's basis is the LA date while ours is the UTC date; the two never diverge in this data because no non-USD transaction falls after 17:00 LA. If the mix changes, this needs revisiting.

**The June file is not June.** Google's statement boundary is LA-local, so the June file contains one transaction — `ORD-507797`, $9.99 — that is July on the UTC recognition basis. Both sides agree it is July, so it carries no discrepancy; it is listed explicitly so Google's own statement total ties to the reported June figure rather than appearing to be off by $9.99.

**A $0.00 tie here means the feed is clean, not that revenue is confirmed.** Google Play is the only PSP with no declines and no chargebacks in the engine log, because the backend does not initiate the purchase — the engine row is created from Google's notification. The two sides share a source. The reconciliation proves complete, correctly priced ingestion; it cannot detect a transaction Google never reported.

**The reconciliation key is `match_key`, not the order reference.** Google Play publishes no identifier at all, so the framework's spine generalises: every provider staging model emits a `match_key` it derives from its own columns — the order reference where one exists, the UTC timestamp plus SKU and country for Google Play — and the engine side derives the same key from its own. Neither side reads the other's columns, so the two remain independent. The full outer join and the grain test move to that key.

**The contracted fee is stated in USD the way the provider states its own.** Where a provider reports a native USD fee, the contracted comparison is struck on the USD gross (`round(amount_usd × pct, 2)`); otherwise the local contracted fee is converted. Google derives its USD fee from the USD gross, so converting our local contracted fee instead left a cent of variance on 59 rows — $0.57 of fee discrepancy that no provider had actually charged. The cause classification was always struck in local currency and was right throughout; only the dollar figure was wrong. Adyen and dLocal are unaffected.

## PayPal

**The two files are one PSP with two accounts.** They share every column and differ only in dialect — delimiter, encoding, decimal separator, date order. Staging normalises both into one model with `psp_account` in ('paypal_us', 'paypal_eu'); the reconciliation matches on account, and no transaction id crosses between them (2,166 land on US, 1,891 on EU, zero elsewhere).

**`Transaction ID` is the join key, not `Invoice ID`.** Unlike Adyen, the engine mints a fresh `psp_reference` per refund that equals the refund's own provider transaction id — 97 of 97. So the transaction id keys every operation type 1:1, while `Invoice ID` fans out to 2 on reversals. `match_key` is still the order reference for entity-level grouping; the transaction id is what the row-level join uses.

**`Time Zone = GMT` is taken at face value, because it verifies.** The parsed `Date + Time` equals the engine's `captured_at_utc` to the second on 3,739 of 3,742 settled rows (the 3 misses are the date-format rows below). No `at time zone` conversion is applied — adding one would break every row.

**Three PayPal EU rows are `MM/DD/YYYY` inside a `DD/MM/YYYY` file, and the export window decides which.** `ORD-507782/507783/507784` read as `DD/MM` land in March, September and December 2026 — outside the export's declared coverage. The rule: parse each row in its file's declared order, and where that lands outside the window, re-parse in the other order.

The window is the export's own metadata, not a guess — the filenames declare `20260601_20260703`, so it lives in `dbt_project.yml` as `export_window_start` / `export_window_end` alongside the delimiter and encoding that `_sources.yml` already hardcodes per file. Nothing is read from the engine log; the engine independently agrees with all three re-parsed dates to the second, which is how we know the rule is right rather than how the rule works.

Applied symmetrically to both files: US declares `MM/DD` and fires zero overrides, EU declares `DD/MM` and fires exactly three. The staging model exposes `date_format_overridden` and `assert_paypal_date_format_override_is_bounded` pins it to those three orders — if a future export changes its date handling the build fails rather than quietly moving money between months. Trusting the file-level format instead pushes two of the three out of June and invents a €29.97 break.

Two things were ruled out. Deriving the window from the EU file's own unambiguous rows does not work: only days > 12 are self-evident, so the range starts 13 June and a genuine `03/06/2026` would be flipped to 6 March. Guessing per row from proximity to its neighbours is worse — it would silently repair a real transposition.

**`Denied` rows carry a gross figure that is not money.** PayPal reports the attempted amount with `Fee = 0` and `Net = 0` on all 315 denied rows. They map to the engine's `declined` 1:1 and are excluded from every sum; they are counted, never added.

**Signs are taken from the file.** PayPal already signs reversals negative. The engine stores them positive (`dq_issues.md` §4), so the engine side is the one that gets a derived sign, not PayPal.

**PayPal's fee is the record; there is no contract to check it against.** `fee_schedule.csv` has no PayPal entry. The charge is exactly `round(gross × pct, 2) + fixed` on 3,646 of 3,646 settled sales — 3.49% + $0.49 USD, 2.90% + €0.35, 2.90% + £0.30. June's $3,908.96 — $2,208.46 US, $1,700.50 EU — is classified `psp_claims_fee_out_of_contract`, the same treatment as dLocal: booked as charged, with the contract named as the gap. Finance should retrieve the PayPal contract and confirm all three currency variants.

**The fixed fee is per-currency, and the schedule cannot express that today.** `int__psp_transactions` zeroes a contracted fixed fee when `fixed_fee_currency` differs from the transaction currency — correct for a single-currency contract, wrong for PayPal, which charges a fixed fee denominated in whatever the customer paid. If PayPal is ever added to `fee_schedule` it needs one row per currency, not one row with a currency caveat.

**The retained refund fee is reported, not booked.** PayPal returns `Fee = 0.00` on all 99 reversals — the original processing fee is kept. That is a real cost of the $909.65, €749.74 and £125.94 reversed across the export window, but no contract we hold states it and the export gives no way to separate "kept by policy" from "not applicable". It is named in the summary rather than classified.

**Recognition is the capture instant, and it moves two US sales into July.** `ORD-507779` and `ORD-507780` are created 2026-06-30 23:59 and captured 2026-07-01 00:04. Both sides agree they are July, so they carry no discrepancy — but recognising on creation would flip them on the engine side only and open a $19.98 hole. USD, so no FX consequence either way.

**`ORD-507786` gets its own cause: `engine_capture_not_recorded`.** The engine row is `pending` with no capture timestamp while PayPal reports the sale settled and charged its fee. Without it the row falls through to `psp_claims_captured_different_period`, which is wrong in a way that matters — the engine has no period at all, not a different one, so a lost capture would be filed as timing and read as self-correcting next month. It sits ahead of the period branches in `int__recon_classified`. $24.99, one row.

**`psp_claims_*` now names the operation type rather than enumerating two of them.** The old chain had `psp_claims_sale` and `psp_claims_chargeback` and nothing for a refund, so PayPal's unbooked €24.99 refund fell through to the period branch as well. `'psp_claims_' || operation_type` covers all three and mirrors the existing `engine_claims_` branch. The distinction is worth keeping in the label: a sale the backend missed understates revenue, a reversal it never booked overstates it.

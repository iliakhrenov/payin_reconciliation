# Profiling — fee schedule

`raw/fee_schedule.csv`

3 rows. The smallest file in the set and the largest gap: it covers two of five provider accounts.

```
psp,account,valid_from,percent_fee,fixed_fee,fixed_fee_currency
adyen,LumoECOM_EU,2026-01-01,2.5,0.00,
adyen,LumoAPP_US,2026-01-01,2.5,0.00,
google_play,LumoPlayMain,2026-01-01,15.0,0.00,
```

### 1. What is covered

| account | provider | contracted | June fees | verifiable |
| --- | --- | ---: | ---: | --- |
| LumoECOM_EU | adyen | 2.5% + 0 | 672.42 | yes |
| LumoAPP_US | adyen | 2.5% + 0 | 157.00 | yes |
| LumoPlayMain | google_play | 15.0% + 0 | 2,249.20 | yes |
| — | dlocal | **no entry** | 751.25 | **no** |
| — | paypal_us | **no entry** | 2,208.46 | **no** |
| — | paypal_eu | **no entry** | 1,700.50 | **no** |

**$4,660.21 of June's $7,738.83 — 60% — has no contract to check against.** The providers charge consistently (dLocal a flat 4.5%; PayPal 3.49% + $0.49 US, 2.90% + €0.35 / £0.30 EU, exact on all 3,646 settled sales), which is why the charges are booked as real rather than disputed. But consistency is not authorisation. Retrieving these two contracts is `action_items.md` F1.

### 2. Structural limits

**`valid_from` with no `valid_to`.** All three rows start 2026-01-01 and nothing closes them, so the file expresses one rate per account forever. No mid-period rate change exists in this data — but the schema cannot represent one, and a provider that repriced mid-month would be silently reconciled against the wrong rate. Handled today by asserting a single effective row per account.

**`fixed_fee_currency` is blank on all three rows**, which is consistent because all three fixed fees are 0.00. The column is untested by this data. `int__psp_transactions` zeroes a contracted fixed fee whose currency differs from the transaction currency — right for a single-currency contract, wrong for PayPal, which charges its fixed fee in whatever the customer paid.

**Adding PayPal needs one row per currency, not one row with a currency caveat.** Three rows for PayPal EU alone (EUR, GBP) and one for US. The current shape cannot express a per-currency fixed fee, and this is the change to make before the contracts arrive rather than after.

### 3. What the covered accounts prove

Where a contract exists, the providers are close to right — $10.72 of variance on $3,078.62 of fees.

- **Adyen, $1.72 over.** Two rows charged at 4.40% against 2.5%. Note the contracted rate is not comparable to any single Adyen column: Adyen splits it into `Commission` (1.9%) plus `Markup` (the remainder). Checking `Commission` alone fails on every row.
- **Google Play, $9.00 over.** Six transactions billed at 30% against 15%, all inside a four-hour window on 2026-06-17. Charges either side are correct.

Both are small. The value of the covered accounts is that they demonstrate the check works — which is the argument for extending it to the other 60%.

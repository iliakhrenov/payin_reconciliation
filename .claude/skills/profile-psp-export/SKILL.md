---
name: profile-psp-export
description: Profile a payment provider export against the payment engine log before modelling it - establish grain, prove the join key, derive the fee formula, and account for every dollar of difference. Use when starting work on a new PSP file in raw/ (PayPal US/EU, dLocal, Google Play, Adyen), when asked to profile, stage or reconcile a provider, or before writing a stg__payment_log_<psp> model.
---

# Profile a PSP export

Goal: know the file well enough that staging is mechanical and no discrepancy is a surprise later. The profile is finished when the aggregate difference decomposes exactly into named rows, with nothing left over.

Work in DuckDB against `staged/`, not `raw/`. Read everything `all_varchar=true` so a bad cast surfaces as a finding rather than a silent null.

```sql
create or replace view p as
  select * from read_csv('staged/<file>.csv', header=true, all_varchar=true);
create or replace view e as
  select * from read_csv('staged/payment_engine_log.csv', header=true, all_varchar=true);
```

## 1. Shape

Header plus five rows first, next to the engine log's. Then counts:

```sql
select count(*) as n_rows,
       count(distinct <entity_key>) as n_entity,
       count(distinct <join_key>) as n_join,
       min(<created>) as min_dt, max(<created>) as max_dt
from p;
```

## 2. Grain — establish before summing anything

Providers fan out: one row per lifecycle event, not per transaction. Summing a gross column before you know this double-counts revenue.

```sql
-- candidate key must equal row count
select count(*) as n_rows,
       count(distinct (<key_a> || '|' || <key_b>)) as n_grain
from p;

-- which lifecycle states each entity carries
select types, count(*) as n from (
  select <entity_key> as k, string_agg(distinct <state>, '+' order by <state>) as types
  from p group by 1
) group by 1 order by n desc;
```

The state sets tell you the filter rule: which state carries the money, which is a duplicate, which never settled. Write that rule down — it goes straight into staging.

Then the column population map, because it is state-dependent and decides what you cast:

```sql
select <state>,
       count(*) as n,
       count(<gross_credit>) as gross_credit,
       count(<gross_debit>) as gross_debit,
       count(<fee_col>) as fee
from p group by 1;
```

## 3. Prove the join key — both directions, per state

```sql
-- unmatched, provider side
select p.<join_key> from (select distinct <join_key> from p) p
left join (select distinct order_id from e) e on e.order_id = p.<join_key>
where e.order_id is null;

-- unmatched, engine side
select e.order_id from (select distinct order_id from e where psp = '<psp>') e
left join (select distinct <join_key> from p) p on p.<join_key> = e.order_id
where p.<join_key> is null;

-- matches must land on the right provider, no cross-provider bleed
select e.psp, count(distinct e.order_id)
from e where e.order_id in (select <join_key> from p) group by 1;
```

Run the set diff **per state** as well as in total. Aggregate counts can tie while a sale on one side faces a decline on the other.

**A second identifier that looks like a key usually is not.** Adyen's `Psp Reference` is 1:1 with the merchant reference, but the engine mints a *fresh* reference for every refund and chargeback while the provider reuses the original sale's. Joining on it silently loses every reversal. Test it before trusting it:

```sql
select count(*) as n,
       sum(case when e.psp_reference = p.<psp_ref> then 1 else 0 end) as agree
from e join (select distinct <join_key> as k, <psp_ref> from p) p on p.k = e.order_id
where e.psp = '<psp>';
```

## 4. Amounts — compare in local currency first

USD introduces FX noise and hides the real break. Compare local, then price the findings.

```sql
select p.<join_key>, p.<ccy>, p.<gross>, e.amount_local, p.<gross> - e.amount_local as diff
from p_settled p join e_settled e on e.order_id = p.<join_key>
where p.<gross> <> e.amount_local or p.<ccy> <> e.currency;
```

Also check `authorised <> settled` where the provider reports both — that is partial capture, and it is invisible if staging only keeps the settled row.

## 5. Fees — derive the formula, never assume the column

Check the effective rate before comparing anything to `fee_schedule`:

```sql
select <account>, count(*) as n,
       round(median(<fee>/<gross>)*100, 3) as med_pct,
       round(min(<fee>/<gross>)*100, 3) as min_pct,
       round(max(<fee>/<gross>)*100, 3) as max_pct
from p_settled group by 1;
```

If the median misses the contracted rate, the fee is **split across columns**. Adyen's contracted 2.5% is `Commission` (1.9%) + `Markup` (the remainder) — checking `Commission` alone fails on every row and looks like a systemic overcharge. Sum the candidates and re-test, then pin the exact formula:

```sql
select count(*) as n,
       sum(case when <fee_a> = round(<gross>*0.019, 2) then 1 else 0 end) as a_exact,
       sum(case when <fee_a> + <fee_b> = round(<gross>*0.025, 2) then 1 else 0 end) as total_exact
from p_settled;
```

Bucket the effective rate to separate rounding from real variance — genuine overcharges sit in their own bucket, cents of rounding do not:

```sql
select round((<fee>/<gross>)*100/0.05)*0.05 as pct_bucket, count(*) from p_settled group by 1 order by 1;
```

Check reversals too: whether the fee is returned on a refund is a real cost, and no contract states it.

## 6. Timezone — prove it, do not assume the header

```sql
select count(*) as n,
       sum(case when p_utc = e.created_at_utc then 1 else 0 end) as exact_matches
from ...
```

In DuckDB, convert with two steps — the result is session-timezone independent:

```sql
(cast(<ts> as timestamp) at time zone '<Provider/Zone>') at time zone 'UTC'
```

A single `at time zone` yields a `timestamptz` that renders in the session zone and compares wrong against a plain `timestamp`. If nearly every row mismatches by a whole number of hours, this is why.

## 7. Period boundary

Exports run past the month end. Count what falls outside on the **UTC** recognition date, and check any settlement-batch column: a batch that straddles the boundary is not a substitute for a date filter.

```sql
select <state>, date_trunc('month', <created_utc>) as mth, count(*) from p group by 1, 2 order by 1, 2;
```

## 8. Close the loop — this is the test of the whole profile

Total by currency must equal the sum of the individual findings. Residual zero, or the profile is not done.

```sql
select ccy, provider_total, engine_total, provider_total - engine_total as diff from ...
```

Then decompose by hand: `EUR -33.99 = -24.00 (partial capture) + 9.99 (provider-only sale) - 9.99 (declined) - 9.99 (period straddle)`. If it does not decompose, a finding is still missing — go back to step 3.

Price findings in USD with the as-of rate (last published rate on or before the transaction date), matching `int__psp_transactions`.

## Output

`docs/profiling__<psp>.md`, structured as: shape line, then one numbered section per finding area — grain, join key coverage, fees, timezone and period. Every claim carries its number. Close with the total discrepancy, signed and absolute.

Carry anything that is an engine-log defect rather than a provider quirk into `docs/action_items.md`, as an owned item with the dollars at risk. Record interpretation calls in `docs/assumptions.md`.

## Traps

- **Never sum a gross column before step 2.** The fan-out is the default, not the exception.
- **DuckDB reserved words** break aliases: `rows`, `ref`, `asof` fail as *bare* aliases (`count(*) rows`) though `as rows` is accepted. `asof` fails even as a qualified reference (`asof.rate_date`) because of `ASOF JOIN` — so a lateral join aliased `asof` will not parse. Use `n_rows`, `order_ref`, `latest_rate` and keep `as` explicit.
- **Blank vs null** — providers ship empty strings. `count(col)` and `col is null` disagree; test both.
- **Aggregate agreement is not row agreement.** Two offsetting errors tie at the total. Always diff per state and per currency.
- A provider row absent from the engine is a real finding, not a join bug — check it against the `txn_id`/`order_id` sequence gaps in `docs/profiling__payment_engine_log.md` before assuming a mistake.

-- Every Charge carries exactly one same-timestamp Google fee row, and the fold must keep that
-- 1:1. A fee row left unmatched would silently drop the cost; a duplicated one would double it.
-- Counted against the raw ledger so the test does not just restate the model's own join.
with

ledger as (
  select
    "Transaction Type" as transaction_type,
    "Transaction Date" || ' ' || "Transaction Time" as event_ts,
    "Product ID" as sku,
    "Buyer Country" as country
  from {{ source('payin', 'google_play_earnings_202606') }}
  union all by name
  select
    "Transaction Type",
    "Transaction Date" || ' ' || "Transaction Time",
    "Product ID",
    "Buyer Country"
  from {{ source('payin', 'google_play_earnings_202607_partial') }}
),

counts as (
  select
    event_ts,
    sku,
    country,
    count(*) filter (where transaction_type = 'Charge') as n_charge,
    count(*) filter (where transaction_type = 'Google fee') as n_fee
  from ledger
  group by 1, 2, 3
)

select *
from counts
where n_charge <> n_fee

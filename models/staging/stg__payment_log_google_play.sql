{% set match_key = "strftime(event_at_utc, '%Y-%m-%dT%H:%M:%S') || '|' || sku || '|' || country" %}

with

src as (
  select * from {{ source('payin', 'google_play_earnings_202606') }}
  union all by name
  select * from {{ source('payin', 'google_play_earnings_202607_partial') }}
),

typed as (
  select
    (
      cast(
        strptime("Transaction Date", '%b %-d, %Y') + cast("Transaction Time" as interval)
        as timestamp
      ) at time zone 'America/Los_Angeles'
    ) at time zone 'UTC' as event_at_utc,
    "Transaction Type" as transaction_type,
    "Product ID" as sku,
    "Buyer Country" as country,
    "Buyer Currency" as currency,
    cast("Amount (Buyer Currency)" as decimal(18, 2)) as amount_local,
    cast("Currency Conversion Rate" as decimal(18, 6)) as fx_rate_reported,
    cast("Amount (Merchant Currency)" as decimal(18, 2)) as amount_usd_reported
  from src
),

charges as (
  select * from typed where transaction_type = 'Charge'
),

fees as (
  select
    event_at_utc,
    sku,
    country,
    -amount_local as fee_local,
    -amount_usd_reported as fee_usd
  from typed
  where transaction_type = 'Google fee'
),

sales as (
  select
    charges.event_at_utc,
    charges.sku,
    charges.country,
    'sale' as operation_type,
    charges.currency,
    charges.amount_local,
    fees.fee_local,
    fees.fee_usd
  from charges
  left join fees
    on fees.event_at_utc = charges.event_at_utc
   and fees.sku = charges.sku
   and fees.country = charges.country
),

refunds as (
  select
    event_at_utc,
    sku,
    country,
    'refund' as operation_type,
    currency,
    amount_local,
    cast(null as decimal(18, 2)) as fee_local,
    cast(null as decimal(18, 2)) as fee_usd
  from typed
  where transaction_type = 'Charge refund'
),

final as (
  select
    'google_play' as psp,
    'LumoPlayMain' as psp_account,
    cast(null as varchar) as psp_reference,
    cast(null as varchar) as order_ref,
    {{ match_key }} as match_key,
    operation_type,
    'settled' as status,
    currency,
    amount_local,
    amount_local as amount_local_settled,
    cast(null as decimal(18, 2)) as amount_local_authorised,
    cast(null as decimal(18, 2)) as amount_local_duplicate,
    cast(null as decimal(18, 2)) as fee_commission_local,
    cast(null as decimal(18, 2)) as fee_markup_local,
    fee_local,
    fee_usd as fee_usd_native,
    cast(null as decimal(18, 2)) as net_local,
    event_at_utc as created_at_utc,
    event_at_utc as settled_at_utc,
    cast(null as integer) as batch_number
  from (
    select * from sales
    union all
    select * from refunds
  )
)

select * from final

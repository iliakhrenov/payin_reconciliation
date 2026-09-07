{% set window_start = "date '" ~ var('export_window_start') ~ "'" %}
{% set window_end = "date '" ~ var('export_window_end') ~ "'" %}

with

src as (
  select 'paypal_us' as account, * from {{ source('payin', 'paypal_us_activity') }}
  union all by name
  select 'paypal_eu' as account, * from {{ source('payin', 'paypal_eu_activity') }}
),

typed as (
  select
    account,
    "Transaction ID" as psp_reference,
    nullif("Reference Txn ID", '') as related_psp_reference,
    "Invoice ID" as order_ref,
    "Type" as activity_type,
    "Status" as activity_status,
    "Time Zone" as declared_time_zone,
    "Date" || ' ' || "Time" as event_at_local,
    "Currency" as currency,
    cast(replace("Gross", ',', '.') as decimal(18, 2)) as gross,
    cast(replace("Fee", ',', '.') as decimal(18, 2)) as fee,
    cast(replace("Net", ',', '.') as decimal(18, 2)) as net
  from src
),

parsed as (
  select
    *,
    try_strptime(event_at_local, '%m/%d/%Y %H:%M:%S') as ts_month_first,
    try_strptime(event_at_local, '%d/%m/%Y %H:%M:%S') as ts_day_first
  from typed
),

dated as (
  select
    *,
    case account when 'paypal_us' then ts_month_first else ts_day_first end as ts_declared,
    case account when 'paypal_us' then ts_day_first else ts_month_first end as ts_alternate
  from parsed
),

resolved as (
  select
    *,
    cast(ts_declared as date) not between {{ window_start }} and {{ window_end }} as date_format_overridden,
    coalesce(
      case
        when cast(ts_declared as date) between {{ window_start }} and {{ window_end }} then ts_declared
      end,
      ts_alternate
    ) as event_at_utc
  from dated
),

mapped as (
  select
    *,
    case activity_type
      when 'Website Payment' then 'sale'
      when 'Refund' then 'refund'
      when 'Payment Reversal' then 'chargeback'
    end as operation_type,
    case activity_status
      when 'Completed' then 'settled'
      when 'Refunded' then 'settled'
      when 'Reversed' then 'settled'
      when 'Denied' then 'declined'
    end as status
  from resolved
),

counted as (
  select
    *,
    count(*) over (partition by account, psp_reference) as n_export_rows
  from mapped
),

deduped as (
  select distinct * from counted
),

final as (
  select
    account as psp,
    account as psp_account,
    psp_reference,
    related_psp_reference,
    order_ref,
    order_ref as match_key,
    operation_type,
    status,
    currency,
    gross as amount_local,
    case when status = 'settled' then gross else cast(0 as decimal(18, 2)) end as amount_local_settled,
    cast(null as decimal(18, 2)) as amount_local_authorised,
    case when n_export_rows > 1 then gross * (n_export_rows - 1) end as amount_local_duplicate,
    cast(null as decimal(18, 2)) as fee_commission_local,
    cast(null as decimal(18, 2)) as fee_markup_local,
    -fee as fee_local,
    cast(null as decimal(18, 2)) as fee_usd_native,
    net as net_local,
    event_at_utc as created_at_utc,
    case when status = 'settled' then event_at_utc end as settled_at_utc,
    date_format_overridden,
    cast(null as integer) as batch_number
  from deduped
)

select * from final

with

src as (
  select * from {{ source('payin', 'dlocal_transactions') }}
),

typed as (
  select
    transaction_id as psp_reference,
    invoice_id as order_ref,
    transaction_type,
    status as psp_status,
    cast(created_at_utc as timestamp) as event_at_utc,
    country,
    currency,
    cast(currency_exponent as integer) as currency_exponent,
    cast(local_amount as decimal(24, 4)) as local_minor,
    cast(fx_rate as decimal(18, 6)) as fx_rate_local_per_usd,
    cast(usd_amount as decimal(18, 2)) as usd_amount_reported,
    cast(fee_usd as decimal(18, 2)) as fee_usd_reported
  from src
),

scaled as (
  select
    *,
    cast(
      local_minor / cast(power(10, currency_exponent) as decimal(18, 0))
      as decimal(18, 2)
    ) as amount_local
  from typed
),

counted as (
  select
    *,
    count(*) over (partition by psp_reference, transaction_type) as n_export_rows
  from scaled
),

deduped as (
  select distinct * from counted
),

mapped as (
  select
    *,
    case transaction_type when 'REFUND' then 'refund' else 'sale' end as operation_type,
    case psp_status
      when 'PAID' then 'settled'
      when 'REFUNDED' then 'settled'
      when 'REJECTED' then 'declined'
      when 'IN_MEDIATION' then 'disputed'
    end as status
  from deduped
),

final as (
  select
    'dlocal' as psp,
    cast(null as varchar) as psp_account,
    psp_reference,
    order_ref,
    operation_type,
    status,
    currency,
    case when operation_type = 'refund' then -amount_local else amount_local end as amount_local,
    case
      when status <> 'settled' then cast(0 as decimal(18, 2))
      when operation_type = 'refund' then -amount_local
      else amount_local
    end as amount_local_settled,
    cast(null as decimal(18, 2)) as amount_local_authorised,
    case when n_export_rows > 1 then amount_local * (n_export_rows - 1) end as amount_local_duplicate,
    cast(null as decimal(18, 2)) as fee_commission_local,
    cast(null as decimal(18, 2)) as fee_markup_local,
    cast(null as decimal(18, 2)) as fee_local,
    fee_usd_reported as fee_usd_native,
    cast(null as decimal(18, 2)) as net_local,
    event_at_utc as created_at_utc,
    case when status = 'settled' then event_at_utc end as settled_at_utc,
    cast(null as integer) as batch_number
  from mapped
)

select * from final

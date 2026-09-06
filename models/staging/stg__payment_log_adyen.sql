with

src as (
  select * from {{ source('payin', 'adyen_payment_accounting') }}
),

typed as (
  select
    "Merchant Account" as psp_account,
    "Psp Reference" as psp_reference,
    "Merchant Reference" as order_ref,
    "Record Type" as record_type,
    (cast("Creation Date" as timestamp) at time zone 'Europe/Amsterdam') at time zone 'UTC' as created_at_utc,
    "Gross Currency" as currency,
    cast("Gross Credit" as decimal(18, 2)) as gross_credit,
    cast("Gross Debit" as decimal(18, 2)) as gross_debit,
    cast("Commission" as decimal(18, 2)) as commission,
    cast("Markup" as decimal(18, 2)) as markup,
    cast("Net Credit" as decimal(18, 2)) as net_credit,
    cast("Net Debit" as decimal(18, 2)) as net_debit,
    cast("Batch Number" as integer) as batch_number
  from src
),

authorised as (
  select
    order_ref,
    created_at_utc,
    gross_credit
  from typed
  where record_type = 'Authorised'
),

sales_settled as (
  select
    settled.psp_account,
    settled.psp_reference,
    settled.order_ref,
    'sale' as operation_type,
    'settled' as status,
    settled.currency,
    settled.gross_credit as amount_local,
    settled.gross_credit as amount_local_settled,
    authorised.gross_credit as amount_local_authorised,
    settled.commission as fee_commission_local,
    settled.markup as fee_markup_local,
    settled.net_credit as net_local,
    authorised.created_at_utc as created_at_utc,
    settled.created_at_utc as settled_at_utc,
    settled.batch_number
  from typed as settled
  left join authorised
    on authorised.order_ref = settled.order_ref
  where settled.record_type = 'Settled'
),

sales_declined as (
  select
    psp_account,
    psp_reference,
    order_ref,
    'sale' as operation_type,
    'declined' as status,
    currency,
    gross_credit as amount_local,
    cast(0 as decimal(18, 2)) as amount_local_settled,
    cast(null as decimal(18, 2)) as amount_local_authorised,
    cast(null as decimal(18, 2)) as fee_commission_local,
    cast(null as decimal(18, 2)) as fee_markup_local,
    cast(null as decimal(18, 2)) as net_local,
    created_at_utc,
    cast(null as timestamp) as settled_at_utc,
    batch_number
  from typed
  where record_type = 'Refused'
),

reversals as (
  select
    psp_account,
    psp_reference,
    order_ref,
    case record_type when 'Refunded' then 'refund' else 'chargeback' end as operation_type,
    'settled' as status,
    currency,
    -gross_debit as amount_local,
    -gross_debit as amount_local_settled,
    cast(null as decimal(18, 2)) as amount_local_authorised,
    commission as fee_commission_local,
    markup as fee_markup_local,
    -net_debit as net_local,
    created_at_utc,
    created_at_utc as settled_at_utc,
    batch_number
  from typed
  where record_type in ('Refunded', 'Chargeback')
),

final as (
  select
    'adyen' as psp,
    psp_account,
    psp_reference,
    order_ref,
    operation_type,
    status,
    currency,
    amount_local,
    amount_local_settled,
    amount_local_authorised,
    fee_commission_local,
    fee_markup_local,
    coalesce(fee_commission_local, 0) + coalesce(fee_markup_local, 0) as fee_local,
    net_local,
    created_at_utc,
    settled_at_utc,
    batch_number
  from (
    select * from sales_settled
    union all
    select * from sales_declined
    union all
    select * from reversals
  )
)

select * from final

-- The PayPal EU export writes three rows MM/DD/YYYY inside a DD/MM/YYYY file. They are found by
-- re-parsing any row whose declared-order date falls outside the export window. If the rule ever
-- fires on a different set, the export's date handling has changed and the reconciliation is
-- silently moving money between months.
select
  psp,
  order_ref,
  psp_reference,
  created_at_utc
from {{ ref('stg__payment_log_paypal') }}
where date_format_overridden
  and order_ref not in ('ORD-507782', 'ORD-507783', 'ORD-507784')

union all

select
  'expected_three_overrides' as psp,
  cast(count(*) as varchar) as order_ref,
  null as psp_reference,
  null as created_at_utc
from {{ ref('stg__payment_log_paypal') }}
where date_format_overridden
having count(*) <> 3

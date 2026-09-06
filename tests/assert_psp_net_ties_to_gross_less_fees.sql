-- The net reconciliation only means anything if the provider's own net ties to its gross less
-- its fees. If a provider starts netting something else into it, this is where we find out.
select
  psp,
  order_ref,
  operation_type,
  amount_local_settled,
  fee_local,
  net_local
from {{ ref('int__psp_transactions') }}
where net_local is not null
  and net_local <> amount_local_settled - fee_local

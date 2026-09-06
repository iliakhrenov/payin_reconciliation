-- Staging collapses repeated export lines with select distinct. That is only safe while the
-- repeats are byte-identical; a same-key pair that differs in any field must not be collapsed.
select
  transaction_id,
  transaction_type,
  count(*) as n_distinct_rows
from (
  select distinct * from {{ source('payin', 'dlocal_transactions') }}
)
group by 1, 2
having count(*) > 1

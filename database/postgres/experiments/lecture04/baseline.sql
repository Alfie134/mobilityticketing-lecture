-- Every ticket must point at an existing product (expect 0 rows)
select t.id, t.product_code
from tickets t
left join products p on p.code = t.product_code
where t.product_code is null or p.code is null;

-- Fingerprint of the existing tickets, to compare after the migration
select t.id, t.product_code, t.price, t.currency
from tickets t
order by t.id;
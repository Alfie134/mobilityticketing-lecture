update tickets t
set product_id = p.id
from products p
where t.product_id is null
  and p.code = t.product_code;

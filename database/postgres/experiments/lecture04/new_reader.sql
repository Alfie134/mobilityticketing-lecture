select t.id,
        coalesce(p_new.id, p_old.id) as resolved_product_id,
        t.price,
        t.currency
from tickets t
left join products p_new
    on p_new.id = t.product_id
left join products p_old
    on t.product_id is null
    and p_old.code = t.product_code
order by t.id;
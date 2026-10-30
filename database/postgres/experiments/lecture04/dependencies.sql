select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'tickets'::regclass
  and pg_get_constraintdef(oid) ilike '%product_code%';

select attname, attnotnull
from pg_attribute
where attrelid = 'tickets'::regclass and attname = 'product_code';

select indexname from pg_indexes
where tablename = 'tickets' and indexdef ilike '%product_code%';

select viewname as view_name from pg_views
where schemaname = 'public' and definition ilike '%product_code%'
union all
select matviewname from pg_matviews
where schemaname = 'public' and definition ilike '%product_code%';

select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and prosrc ilike '%product_code%';

select tgname from pg_trigger
where tgrelid = 'tickets'::regclass and not tgisinternal;

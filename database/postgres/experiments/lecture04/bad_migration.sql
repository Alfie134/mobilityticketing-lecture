-- Step 2: the obvious but unsafe migration, tried inside a transaction
begin;

-- 1. remove the old reference
alter table tickets drop column product_code;
savepoint after_drop;

-- 2. add the new one and make it required immediately
alter table tickets add column product_id uuid not null;

-- (the statement above fails, so go back to the savepoint)
rollback to savepoint after_drop;

-- 3. an existing query that expects the old column
select id, product_code, price, currency from tickets order by id;

-- throw everything away: nothing above is permanent
rollback;
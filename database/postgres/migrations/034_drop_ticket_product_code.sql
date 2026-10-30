begin;
set local lock_timeout = '3s';
alter table tickets drop constraint tickets_product_fk;
alter table tickets drop column product_code;
commit;

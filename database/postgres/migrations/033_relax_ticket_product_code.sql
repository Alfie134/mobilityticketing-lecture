begin;
set local lock_timeout = '3s';
alter table tickets alter column product_code drop not null;
commit;

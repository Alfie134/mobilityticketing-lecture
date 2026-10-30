begin;
set local lock_timeout = '3s';

alter table tickets
  validate constraint tickets_product_id_fk;

alter table tickets
  alter column product_id set not null;

commit;

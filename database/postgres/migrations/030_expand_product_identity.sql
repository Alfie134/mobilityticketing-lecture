begin;
set local lock_timeout = '3s';

alter table products add column id uuid;

update products
set id = gen_random_uuid()
where id is null;

alter table products
    alter column id set default gen_random_uuid();

alter table products
    alter column id set not null;

alter table products
    add constraint products_id_unique unique (id);


alter table tickets
    add column product_id uuid;

alter table tickets
    add constraint tickets_product_id_fk
    foreign key (product_id)
    references products(id)
    not valid;

commit;

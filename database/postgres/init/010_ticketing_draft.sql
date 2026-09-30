alter tabele trips
    add column capacity integer,
    add column reserved_seats integer default 0;

create table products (
    code text primary key,
    name text,
    price numeric,
    currency text
);

create table users (
    id text primary key, 
    email text,
    full_name text,
    is_disabled boolean default false
);

create table tickets (
    id text primary key,
    user_id text,
    trip_id text,
    ticket_code text,
    status text,
    product_code text,
    valid_from_utc timestamptz,
    valid_to_utc timestamptz,
    price numeric,
    currency text
);

reate table payments (
    id text primary key,
    user_id text,
    ticket_id text,
    external_payment_reference text,
    amount numeric,
    currency text,
    status text,
    created_utc timestamptz default now()
);

create table validations (
    id text primary key,
    ticket_id text,
    ticket_code text,
    vehicle_id text,
    stop_id text,
    device_id text,
    result text,
    validated_utc timestamptz default now()
);

-- The absence of constraints is intentional.
-- Add constraints through a new migration rather than editing this file.

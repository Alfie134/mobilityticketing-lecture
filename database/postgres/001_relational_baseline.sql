create table operators (
    id text primary key,
    name text not null
);

create table routes (
    id text primary key,
    operator_id text not null references operators(id),
    city_id text not null,
    mode text not null,
    short_name text not null
);

create table stops (
    id text primary key,
    city_id text not null,
    name text not null
);

create table route_stops (
    route_id text not null references routes(id),
    stop_id text not null references stops(id),
    stop_sequence integer not null,
    -- TODO: choose and add the primary key.
    -- Explain whether a stop may occur more than once on the same route.

    -- Primary key is (route_id, stop_sequence): a "route stop" is really a
    -- position along a route, not a route/stop pair. Keying on
    -- (route_id, stop_id) instead would make it impossible for a route to
    -- call at the same physical stop twice (loop routes, out-and-back
    -- routes that pass the same stop on both legs), which is a real pattern
    -- for city bus/tram lines. Keying on (route_id, stop_sequence) allows a
    -- stop_id to repeat within a route while still guaranteeing each
    -- position on the route is unique and ordered.
    constraint route_stops_pk primary key (route_id, stop_sequence),
    constraint route_stops_sequence_positive check (stop_sequence > 0)
);

create table trips (
    id text primary key,
    route_id text not null references routes(id),
    service_date date not null,
    scheduled_departure_utc timestamptz not null,
    status text not null
);

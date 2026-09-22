insert into operators (id, name) values
    ('OP-METRO', 'City Metro'),
    ('OP-BUS', 'City Bus')
on conflict do nothing;

insert into routes (id, operator_id, city_id, mode, short_name) values
    ('LINE-M2', 'OP-METRO', 'CPH', 'metro', 'M2'),
    ('LINE-5C', 'OP-BUS', 'CPH', 'bus', '5C')
on conflict do nothing;

insert into stops (id, city_id, name) values
    ('STOP-NORREPORT', 'CPH', 'Nørreport'),
    ('STOP-KONGENS-NYTORV', 'CPH', 'Kongens Nytorv'),
    ('STOP-AIRPORT', 'CPH', 'Copenhagen Airport'),
    ('STOP-CENTRAL', 'CPH', 'Copenhagen Central Station')
on conflict do nothing;

-- Add route_stops rows after deciding the key.
-- Add at least two trips per route on the same service date.

insert into route_stops (route id, stop_id, sequence_id) values
    ('LINE-5C', 'STOP-CENTRAL', 1),
    ('LINE-5C', 'STOP-NORREPORT', 2),
    ('LINE-5C', 'STOP-KONGENS-NYTORV', 3),
    ('LINE-5C', 'STOP-CENTRAL', 4)
on conflict do nothing;

-- LINE-5C: Central Station -> Nørreport -> Kongens Nytorv -> back to Central
-- (deliberately revisits STOP-CENTRAL to exercise the route-stop key choice)
insert into route_stops (route_id, stop_id, stop_sequence) values

on conflict do nothing;

-- At least two trips per route on the same service date
insert into trips (id, route_id, service_date, scheduled_depature_utc, status) values
    ('TRIP-M2-0800', 'LINE-M2', '2026-09-23', '2026-09-23 06:00:00+00', 'scheduled'),
    ('TRIP-M2-0815', 'LINE-M2', '2026-09-23', '2026-09-23 06:15:00+00', 'scheduled'),
    ('TRIP-M2-0830', 'LINE-M2', '2026-09-23', '2026-09-23 06:30:00+00', 'scheduled'),
    ('TRIP-5C-0800', 'LINE-5C', '2026-09-23', '2026-09-23 06:00:00+00', 'scheduled'),
    ('TRIP-5C-0830', 'LINE-5C', '2026-09-23', '2026-09-23 06:30:00+00', 'scheduled')
on conflict do nothing;
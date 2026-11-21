\set ON_ERROR_STOP on

DO $role$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'inspector') THEN
        CREATE ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    ELSE
        ALTER ROLE inspector WITH LOGIN PASSWORD 'NetoSQL2025';
    END IF;
END
$role$;

GRANT ALL PRIVILEGES ON SCHEMA makarova_food TO inspector;
GRANT USAGE ON SCHEMA exts TO inspector;
GRANT USAGE ON SCHEMA information_schema, pg_catalog TO inspector;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA makarova_food TO inspector;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA makarova_food TO inspector;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA makarova_food TO inspector;
GRANT USAGE ON TYPE
    makarova_food.restaurant_status,
    makarova_food.product_status,
    makarova_food.courier_status,
    makarova_food.order_status,
    makarova_food.order_pay_status,
    makarova_food.payment_status,
    makarova_food.payment_type,
    makarova_food.review_entity_type
TO inspector;

ALTER DEFAULT PRIVILEGES IN SCHEMA makarova_food
    GRANT ALL PRIVILEGES ON TABLES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA makarova_food
    GRANT ALL PRIVILEGES ON SEQUENCES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA makarova_food
    GRANT ALL PRIVILEGES ON ROUTINES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA makarova_food
    GRANT USAGE ON TYPES TO inspector;

ALTER ROLE inspector SET search_path TO makarova_food, exts, public;

BEGIN;

DO $check_exts$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_extension e
        JOIN pg_namespace n ON n.oid = e.extnamespace
        WHERE e.extname = 'uuid-ossp'
          AND n.nspname = 'exts'
    ) THEN
        RAISE EXCEPTION
            'Требуется заранее созданное расширение uuid-ossp в схеме exts';
    END IF;
END
$check_exts$;

CREATE SCHEMA makarova_food;
COMMENT ON SCHEMA makarova_food IS 'База данных сервиса доставки еды FoodExpress';

COMMIT;


BEGIN;

SET search_path TO makarova_food, exts;

CREATE OR REPLACE PROCEDURE erase_test_data()
LANGUAGE plpgsql
AS $procedure$
BEGIN
    TRUNCATE TABLE
        review,
        payment,
        order_structure,
        courier_pay,
        "order",
        product,
        product_category,
        restaurant,
        client_address,
        courier,
        client,
        address
    RESTART IDENTITY;
END
$procedure$;

CREATE OR REPLACE PROCEDURE add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar,
    p_price numeric,
    p_rating numeric,
    p_status product_status,
    p_description text,
    p_photo_url text DEFAULT NULL
)
LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM restaurant r WHERE r.restaurant_id = p_restaurant_id
    ) THEN
        RAISE EXCEPTION 'Ресторан % не существует', p_restaurant_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM product_category pc
         WHERE pc.product_category_id = p_product_category_id
    ) THEN
        RAISE EXCEPTION 'Категория блюда % не существует', p_product_category_id;
    END IF;

    INSERT INTO product (
        product_id,
        product_name,
        product_category_id,
        price,
        restaurant_id,
        photo_url,
        rating,
        status,
        description
    )
    VALUES (
        exts.uuid_generate_v4(),
        p_name,
        p_product_category_id,
        p_price,
        p_restaurant_id,
        p_photo_url,
        p_rating,
        p_status,
        p_description
    );
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Некорректные данные блюда: %', SQLERRM;
END
$procedure$;

CREATE OR REPLACE PROCEDURE insert_test_data(value integer)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_token text := replace(exts.uuid_generate_v4()::text, '-', '');
    v_restaurant_statuses restaurant_status[] := enum_range(NULL::restaurant_status);
    v_product_statuses product_status[] := enum_range(NULL::product_status);
    v_courier_statuses courier_status[] := enum_range(NULL::courier_status);
    v_order_statuses order_status[] := enum_range(NULL::order_status);
    v_order_pay_statuses order_pay_status[] := enum_range(NULL::order_pay_status);
    v_payment_statuses payment_status[] := enum_range(NULL::payment_status);
    v_payment_types payment_type[] := enum_range(NULL::payment_type);
    v_review_types review_entity_type[] := enum_range(NULL::review_entity_type);
BEGIN
    IF value IS NULL OR value <= 0 THEN
        RAISE EXCEPTION 'Параметр value должен быть положительным целым числом';
    END IF;

    CREATE TEMP TABLE tmp_clients (
        rn integer PRIMARY KEY,
        id uuid NOT NULL
    ) ON COMMIT DROP;

    CREATE TEMP TABLE tmp_couriers (
        rn integer PRIMARY KEY,
        id uuid NOT NULL
    ) ON COMMIT DROP;

    CREATE TEMP TABLE tmp_categories (
        rn integer PRIMARY KEY,
        id uuid NOT NULL
    ) ON COMMIT DROP;

    CREATE TEMP TABLE tmp_restaurant_addresses (
        rn integer PRIMARY KEY,
        id uuid NOT NULL
    ) ON COMMIT DROP;

    CREATE TEMP TABLE tmp_client_addresses (
        rn integer PRIMARY KEY,
        id uuid NOT NULL
    ) ON COMMIT DROP;

    CREATE TEMP TABLE tmp_restaurants (
        rn integer PRIMARY KEY,
        id uuid NOT NULL,
        address_id uuid NOT NULL
    ) ON COMMIT DROP;

    CREATE TEMP TABLE tmp_products (
        rn integer PRIMARY KEY,
        id uuid NOT NULL,
        restaurant_id uuid NOT NULL,
        category_id uuid NOT NULL,
        price numeric(12,2) NOT NULL
    ) ON COMMIT DROP;

    CREATE TEMP TABLE tmp_orders (
        rn integer PRIMARY KEY,
        id uuid NOT NULL,
        courier_id uuid NOT NULL,
        client_id uuid NOT NULL,
        address_id uuid NOT NULL,
        restaurant_id uuid NOT NULL,
        product_id uuid NOT NULL,
        order_ts timestamp without time zone NOT NULL,
        order_state order_status NOT NULL
    ) ON COMMIT DROP;

    INSERT INTO tmp_clients (rn, id)
    SELECT i, exts.uuid_generate_v4()
      FROM generate_series(1, value) AS g(i);

    INSERT INTO client (client_id, login, password, phone_number)
    SELECT tc.id,
           'client_' || left(v_token, 12) || '_' || tc.rn,
           md5(random()::text),
           '+7' || lpad(
               mod(
                   ('x' || substr(md5(v_token || '_client_' || tc.rn), 1, 15))::bit(60)::bigint,
                   10000000000
               )::text,
               10,
               '0'
           )
      FROM tmp_clients tc;

    INSERT INTO tmp_couriers (rn, id)
    SELECT i, exts.uuid_generate_v4()
      FROM generate_series(1, value) AS g(i);

    INSERT INTO courier (
        courier_id,
        fio,
        phone_number,
        status,
        hire_date,
        dismissal_date,
        coefficient
    )
    SELECT tc.id,
           'Курьер ' || left(v_token, 8) || ' ' || tc.rn,
           '+7' || lpad(
               mod(
                   ('x' || substr(md5(v_token || '_courier_' || tc.rn), 1, 15))::bit(60)::bigint,
                   10000000000
               )::text,
               10,
               '0'
           ),
           CASE
               WHEN value > 1 AND tc.rn % 5 = 0 THEN v_courier_statuses[4]
               ELSE v_courier_statuses[1 + ((tc.rn - 1) % 3)]
           END,
           (current_date - interval '6 months' + interval '1 day')::date,
           CASE
               WHEN value > 1 AND tc.rn % 5 = 0 THEN current_date
               ELSE NULL
           END,
           0.10
      FROM tmp_couriers tc;

    INSERT INTO tmp_categories (rn, id)
    SELECT i, exts.uuid_generate_v4()
      FROM generate_series(1, value) AS g(i);

    INSERT INTO product_category (product_category_id, product_category_name)
    SELECT t.id,
           'Категория ' || left(v_token, 10) || ' ' || t.rn
      FROM tmp_categories t;

    INSERT INTO tmp_restaurant_addresses (rn, id)
    SELECT i, exts.uuid_generate_v4()
      FROM generate_series(1, value) AS g(i);

    INSERT INTO address (address_id, street, house_number, apartment_office)
    SELECT t.id,
           'Ресторанная улица ' || left(v_token, 10) || ' ' || t.rn,
           (100 + t.rn)::text,
           NULL
      FROM tmp_restaurant_addresses t;

    INSERT INTO tmp_client_addresses (rn, id)
    SELECT i, exts.uuid_generate_v4()
      FROM generate_series(1, value * 4) AS g(i);

    INSERT INTO address (address_id, street, house_number, apartment_office)
    SELECT t.id,
           'Клиентская улица ' || left(v_token, 10) || ' ' || t.rn,
           (200 + t.rn)::text,
           CASE WHEN t.rn % 4 = 0 THEN NULL ELSE (1 + t.rn)::text END
      FROM tmp_client_addresses t;

    INSERT INTO client_address (client_id, address_id)
    SELECT tc.id, ta.id
      FROM tmp_clients tc
      JOIN tmp_client_addresses ta
        ON ta.rn BETWEEN (tc.rn - 1) * 4 + 1 AND tc.rn * 4;

    INSERT INTO tmp_restaurants (rn, id, address_id)
    SELECT ta.rn, exts.uuid_generate_v4(), ta.id
      FROM tmp_restaurant_addresses ta;

    INSERT INTO restaurant (
        restaurant_id,
        restaurant_name,
        address_id,
        description,
        work_start,
        work_end,
        company_details,
        rating,
        status
    )
    SELECT tr.id,
           'Ресторан ' || left(v_token, 10) || ' ' || tr.rn,
           tr.address_id,
           'Описание ресторана ' || tr.rn,
           time '09:00',
           time '23:00',
           'ИНН ' || lpad(tr.rn::text, 10, '0') || '; ОГРН ' || left(v_token, 13),
           NULL,
           v_restaurant_statuses[1 + ((tr.rn - 1) % array_length(v_restaurant_statuses, 1))]
      FROM tmp_restaurants tr;

    INSERT INTO tmp_products (rn, id, restaurant_id, category_id, price)
    SELECT i,
           exts.uuid_generate_v4(),
           tr.id,
           tc.id,
           (1000 + i * 25)::numeric(12,2)
      FROM generate_series(1, value * 5) AS g(i)
      JOIN tmp_restaurants tr
        ON tr.rn = 1 + ((i - 1) % value)
      JOIN tmp_categories tc
        ON tc.rn = 1 + ((i - 1) % value);

    INSERT INTO product (
        product_id,
        product_name,
        product_category_id,
        price,
        restaurant_id,
        photo_url,
        rating,
        status,
        description
    )
    SELECT tp.id,
           'Блюдо ' || left(v_token, 10) || ' ' || tp.rn,
           tp.category_id,
           tp.price,
           tp.restaurant_id,
           CASE
               WHEN tp.rn % 3 = 0
                   THEN 'https://example.test/products/' || tp.id || '.jpg'
               ELSE NULL
           END,
           NULL,
           v_product_statuses[1 + ((tp.rn - 1) % array_length(v_product_statuses, 1))],
           'Описание блюда ' || tp.rn
      FROM tmp_products tp;

    INSERT INTO tmp_orders (
        rn,
        id,
        courier_id,
        client_id,
        address_id,
        restaurant_id,
        product_id,
        order_ts,
        order_state
    )
    SELECT i,
           exts.uuid_generate_v4(),
           tco.id,
           tcl.id,
           ta.id,
           tr.id,
           tp.id,
           date_trunc('month', localtimestamp)
               - make_interval(months => ((i - 1) % 6))
               + make_interval(
                   days => least(extract(day FROM current_date)::integer - 1, 9)
               ),
           CASE
               WHEN i % 5 = 0 THEN v_order_statuses[5]
               ELSE v_order_statuses[4]
           END
      FROM generate_series(1, value * 5) AS g(i)
      JOIN tmp_clients tcl
        ON tcl.rn = 1 + ((i - 1) % value)
      JOIN tmp_couriers tco
        ON tco.rn = 1 + ((i - 1) % value)
      JOIN tmp_restaurants tr
        ON tr.rn = 1 + ((i - 1) % value)
      JOIN tmp_products tp
        ON tp.rn = i
      JOIN tmp_client_addresses ta
        ON ta.rn = ((tcl.rn - 1) * 4) + 1 + ((i - 1) % 4);

    INSERT INTO "order" (
        order_id,
        courier_id,
        client_id,
        address_id,
        restaurant_id,
        order_timestamp,
        delivery_timestamp,
        order_amount,
        status,
        pay_status,
        description
    )
    SELECT tor.id,
           tor.courier_id,
           tor.client_id,
           tor.address_id,
           tor.restaurant_id,
           tor.order_ts,
           CASE
               WHEN tor.order_state = v_order_statuses[4]
                   THEN least(tor.order_ts + interval '1 hour', localtimestamp)
               ELSE NULL
           END,
           tp.price,
           tor.order_state,
           v_order_pay_statuses[1],
           'Тестовый заказ ' || tor.rn
      FROM tmp_orders tor
      JOIN tmp_products tp ON tp.id = tor.product_id;

    INSERT INTO order_structure (order_id, product_id, quantity)
    SELECT tor.id, tor.product_id, 1.000
      FROM tmp_orders tor;

    INSERT INTO payment (
        payment_id,
        order_id,
        payment_type,
        amount,
        transaction_id,
        transaction_timestamp,
        status
    )
    SELECT exts.uuid_generate_v4(),
           tor.id,
           v_payment_types[1 + ((tor.rn - 1) % array_length(v_payment_types, 1))],
           o.total_amount,
           'txn_' || v_token || '_' || tor.rn,
           least(tor.order_ts + interval '30 minutes', localtimestamp),
           v_payment_statuses[1]
      FROM tmp_orders tor
      JOIN "order" o ON o.order_id = tor.id;

    INSERT INTO review (
        review_id,
        client_id,
        review_timestamp,
        entity_id,
        entity_type,
        order_id,
        description,
        photo_url,
        rating
    )
    SELECT exts.uuid_generate_v4(),
           tor.client_id,
           least(tor.order_ts + interval '2 hours', localtimestamp),
           CASE v_review_types[1 + ((tor.rn - 1) % array_length(v_review_types, 1))]
               WHEN 'блюдо' THEN tor.product_id
               WHEN 'ресторан' THEN tor.restaurant_id
               WHEN 'заказ' THEN tor.id
           END,
           v_review_types[1 + ((tor.rn - 1) % array_length(v_review_types, 1))],
           tor.id,
           'Отзыв на тестовый заказ ' || tor.rn,
           CASE
               WHEN tor.rn % 4 = 0
                   THEN 'https://example.test/reviews/' || tor.id || '.jpg'
               ELSE NULL
           END,
           (1 + ((tor.rn - 1) % 5))::numeric(2,1)
      FROM tmp_orders tor;

    INSERT INTO courier_pay (
        year,
        month,
        courier_id,
        amount,
        coefficient_used
    )
    SELECT extract(year FROM m.month_start)::integer,
           extract(month FROM m.month_start)::integer,
           tc.id,
           round(coalesce(sum(o.commission), 0) * 0.10, 2),
           0.10
      FROM tmp_couriers tc
      CROSS JOIN LATERAL (
          SELECT date_trunc('month', current_date)::date
                   - make_interval(months => n) AS month_start
            FROM generate_series(0, 5) AS gs(n)
      ) m
      LEFT JOIN "order" o
        ON o.courier_id = tc.id
       AND o.status = v_order_statuses[4]
       AND o.order_timestamp >= m.month_start
       AND o.order_timestamp < m.month_start + interval '1 month'
     GROUP BY m.month_start, tc.id;

    WITH current_month_counts AS (
        SELECT c.courier_id,
               count(o.order_id) AS delivered_count
          FROM courier c
          LEFT JOIN "order" o
            ON o.courier_id = c.courier_id
           AND o.status = v_order_statuses[4]
           AND o.order_timestamp >= date_trunc('month', localtimestamp)
           AND o.order_timestamp < date_trunc('month', localtimestamp) + interval '1 month'
         WHERE c.courier_id IN (SELECT id FROM tmp_couriers)
         GROUP BY c.courier_id
    )
    UPDATE courier c
       SET coefficient = CASE
           WHEN cmc.delivered_count <= 150 THEN 0.10
           WHEN cmc.delivered_count <= 250 THEN 0.20
           WHEN cmc.delivered_count <= 500 THEN 0.30
           ELSE 0.50
       END
      FROM current_month_counts cmc
     WHERE c.courier_id = cmc.courier_id
       AND c.status <> v_courier_statuses[4];

    DROP TABLE
        tmp_orders,
        tmp_products,
        tmp_restaurants,
        tmp_client_addresses,
        tmp_restaurant_addresses,
        tmp_categories,
        tmp_couriers,
        tmp_clients;
END
$procedure$;

CREATE OR REPLACE PROCEDURE courier_salary()
LANGUAGE plpgsql
AS $procedure$
BEGIN
    WITH monthly AS (
        SELECT c.courier_id,
               c.coefficient,
               coalesce(sum(o.commission), 0) AS commission_sum
          FROM courier c
          LEFT JOIN "order" o
            ON o.courier_id = c.courier_id
           AND o.status = 'доставлен'
           AND o.order_timestamp >= date_trunc('month', localtimestamp)
           AND o.order_timestamp < date_trunc('month', localtimestamp) + interval '1 month'
         GROUP BY c.courier_id, c.coefficient
    ),
    calculation AS (
        SELECT m.courier_id,
               m.commission_sum,
               coalesce(cp.coefficient_used, m.coefficient) AS coefficient_for_current_month
          FROM monthly m
          LEFT JOIN courier_pay cp
            ON cp.courier_id = m.courier_id
           AND cp.year = extract(year FROM current_date)::integer
           AND cp.month = extract(month FROM current_date)::integer
    )
    INSERT INTO courier_pay (
        year,
        month,
        courier_id,
        amount,
        coefficient_used
    )
    SELECT extract(year FROM current_date)::integer,
           extract(month FROM current_date)::integer,
           calc.courier_id,
           round(calc.commission_sum * calc.coefficient_for_current_month, 2),
           calc.coefficient_for_current_month
      FROM calculation calc
    ON CONFLICT (year, month, courier_id)
    DO UPDATE
          SET amount = EXCLUDED.amount,
              coefficient_used = EXCLUDED.coefficient_used;

    WITH delivered AS (
        SELECT c.courier_id,
               count(o.order_id) AS delivered_count
          FROM courier c
          LEFT JOIN "order" o
            ON o.courier_id = c.courier_id
           AND o.status = 'доставлен'
           AND o.order_timestamp >= date_trunc('month', localtimestamp)
           AND o.order_timestamp < date_trunc('month', localtimestamp) + interval '1 month'
         GROUP BY c.courier_id
    )
    UPDATE courier c
       SET coefficient = CASE
           WHEN d.delivered_count <= 150 THEN 0.10
           WHEN d.delivered_count <= 250 THEN 0.20
           WHEN d.delivered_count <= 500 THEN 0.30
           ELSE 0.50
       END
      FROM delivered d
     WHERE c.courier_id = d.courier_id
       AND c.status <> 'уволен';
END
$procedure$;

COMMIT;

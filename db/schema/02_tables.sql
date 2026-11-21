BEGIN;

SET search_path TO makarova_food, exts;

CREATE TABLE address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar(120) NOT NULL,
    house_number varchar(20) NOT NULL,
    apartment_office varchar(20),
    CONSTRAINT ck_address_street_nonempty
        CHECK (btrim(street) <> ''),
    CONSTRAINT ck_address_house_nonempty
        CHECK (btrim(house_number) <> ''),
    CONSTRAINT ck_address_apartment_nonempty
        CHECK (apartment_office IS NULL OR btrim(apartment_office) <> ''),
    CONSTRAINT uq_address_physical
        UNIQUE NULLS NOT DISTINCT (street, house_number, apartment_office)
);

CREATE TABLE client (
    client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login varchar(80) NOT NULL,
    password varchar(32) NOT NULL,
    phone_number varchar(16) NOT NULL,
    CONSTRAINT uq_client_login UNIQUE (login),
    CONSTRAINT uq_client_phone UNIQUE (phone_number),
    CONSTRAINT ck_client_login_nonempty CHECK (btrim(login) <> ''),
    CONSTRAINT ck_client_password_md5 CHECK (password ~ '^[0-9a-f]{32}$'),
    CONSTRAINT ck_client_phone_format CHECK (phone_number ~ '^\+[0-9]{11,15}$')
);

CREATE TABLE client_address (
    client_id uuid NOT NULL,
    address_id uuid NOT NULL,
    CONSTRAINT pk_client_address PRIMARY KEY (client_id, address_id),
    CONSTRAINT fk_client_address_client
        FOREIGN KEY (client_id) REFERENCES client (client_id) ON DELETE CASCADE,
    CONSTRAINT fk_client_address_address
        FOREIGN KEY (address_id) REFERENCES address (address_id) ON DELETE RESTRICT
);

CREATE TABLE restaurant (
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(160) NOT NULL,
    address_id uuid NOT NULL,
    description text NOT NULL,
    work_start time without time zone NOT NULL,
    work_end time without time zone NOT NULL,
    company_details text NOT NULL,
    rating numeric(3,2),
    status restaurant_status NOT NULL,
    CONSTRAINT uq_restaurant_address UNIQUE (address_id),
    CONSTRAINT ck_restaurant_name_nonempty CHECK (btrim(restaurant_name) <> ''),
    CONSTRAINT ck_restaurant_description_nonempty CHECK (btrim(description) <> ''),
    CONSTRAINT ck_restaurant_company_details_nonempty CHECK (btrim(company_details) <> ''),
    CONSTRAINT ck_restaurant_work_time CHECK (work_end > work_start),
    CONSTRAINT ck_restaurant_rating CHECK (rating IS NULL OR rating BETWEEN 0 AND 5),
    CONSTRAINT fk_restaurant_address
        FOREIGN KEY (address_id) REFERENCES address (address_id) ON DELETE RESTRICT
);

CREATE TABLE product_category (
    product_category_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(100) NOT NULL,
    CONSTRAINT ck_product_category_name_nonempty
        CHECK (btrim(product_category_name) <> '')
);

CREATE TABLE product (
    product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name varchar(160) NOT NULL,
    product_category_id uuid NOT NULL,
    price numeric(12,2) NOT NULL,
    restaurant_id uuid NOT NULL,
    photo_url text,
    rating numeric(3,2),
    status product_status NOT NULL,
    description text NOT NULL,
    CONSTRAINT ck_product_name_nonempty CHECK (btrim(product_name) <> ''),
    CONSTRAINT ck_product_price CHECK (price >= 0),
    CONSTRAINT ck_product_photo_url CHECK (photo_url IS NULL OR btrim(photo_url) <> ''),
    CONSTRAINT ck_product_rating CHECK (rating IS NULL OR rating BETWEEN 0 AND 5),
    CONSTRAINT ck_product_description_nonempty CHECK (btrim(description) <> ''),
    CONSTRAINT fk_product_category
        FOREIGN KEY (product_category_id)
        REFERENCES product_category (product_category_id) ON DELETE RESTRICT,
    CONSTRAINT fk_product_restaurant
        FOREIGN KEY (restaurant_id)
        REFERENCES restaurant (restaurant_id) ON DELETE RESTRICT
);

CREATE TABLE courier (
    courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio varchar(200) NOT NULL,
    phone_number varchar(16) NOT NULL,
    status courier_status NOT NULL,
    hire_date date NOT NULL,
    dismissal_date date,
    coefficient numeric(3,2) NOT NULL DEFAULT 0.10,
    CONSTRAINT ck_courier_fio_nonempty CHECK (btrim(fio) <> ''),
    CONSTRAINT ck_courier_phone_format CHECK (phone_number ~ '^\+[0-9]{11,15}$'),
    CONSTRAINT ck_courier_coefficient CHECK (coefficient BETWEEN 0.10 AND 0.50),
    CONSTRAINT ck_courier_dismissal_required
        CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL),
    CONSTRAINT ck_courier_dismissal_after_hire
        CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date)
);

CREATE TABLE courier_pay (
    year integer NOT NULL,
    month integer NOT NULL,
    courier_id uuid NOT NULL,
    amount numeric(14,2) NOT NULL,
    coefficient_used numeric(3,2) NOT NULL,
    CONSTRAINT pk_courier_pay PRIMARY KEY (year, month, courier_id),
    CONSTRAINT ck_courier_pay_year CHECK (year > 0),
    CONSTRAINT ck_courier_pay_month CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT ck_courier_pay_amount CHECK (amount >= 0),
    CONSTRAINT ck_courier_pay_coefficient CHECK (coefficient_used BETWEEN 0.10 AND 0.50),
    CONSTRAINT fk_courier_pay_courier
        FOREIGN KEY (courier_id) REFERENCES courier (courier_id) ON DELETE RESTRICT
);

CREATE TABLE "order" (
    order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id uuid NOT NULL,
    client_id uuid NOT NULL,
    address_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    order_timestamp timestamp without time zone NOT NULL DEFAULT localtimestamp,
    delivery_timestamp timestamp without time zone,
    order_amount numeric(14,2) NOT NULL,
    commission numeric(14,2)
        GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,
    total_amount numeric(14,2)
        GENERATED ALWAYS AS (round(order_amount + round(order_amount * 0.10, 2), 2)) STORED,
    status order_status NOT NULL DEFAULT 'создан',
    pay_status order_pay_status NOT NULL DEFAULT 'ожидает',
    description text NOT NULL,
    CONSTRAINT ck_order_amount_nonnegative CHECK (order_amount >= 0),
    CONSTRAINT ck_order_minimum_total CHECK (total_amount >= 1000),
    CONSTRAINT ck_order_delivery_time
        CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
    CONSTRAINT ck_order_delivery_status
        CHECK (
            (status = 'доставлен' AND delivery_timestamp IS NOT NULL)
            OR
            (status <> 'доставлен' AND delivery_timestamp IS NULL)
        ),
    CONSTRAINT ck_order_description_nonempty CHECK (btrim(description) <> ''),
    CONSTRAINT fk_order_courier
        FOREIGN KEY (courier_id) REFERENCES courier (courier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_client
        FOREIGN KEY (client_id) REFERENCES client (client_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_address
        FOREIGN KEY (address_id) REFERENCES address (address_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_restaurant
        FOREIGN KEY (restaurant_id) REFERENCES restaurant (restaurant_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_client_address
        FOREIGN KEY (client_id, address_id)
        REFERENCES client_address (client_id, address_id) ON DELETE RESTRICT
);

CREATE TABLE payment (
    payment_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL,
    payment_type payment_type NOT NULL,
    amount numeric(14,2) NOT NULL,
    transaction_id varchar(120) NOT NULL,
    transaction_timestamp timestamp without time zone NOT NULL DEFAULT localtimestamp,
    status payment_status NOT NULL,
    CONSTRAINT uq_payment_transaction UNIQUE (transaction_id),
    CONSTRAINT ck_payment_amount CHECK (amount > 0),
    CONSTRAINT ck_payment_transaction_nonempty CHECK (btrim(transaction_id) <> ''),
    CONSTRAINT fk_payment_order
        FOREIGN KEY (order_id) REFERENCES "order" (order_id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX uq_payment_one_success_per_order
    ON payment (order_id)
    WHERE status = 'успех';

CREATE TABLE order_structure (
    order_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity numeric(12,3) NOT NULL,
    CONSTRAINT pk_order_structure PRIMARY KEY (order_id, product_id),
    CONSTRAINT ck_order_structure_quantity CHECK (quantity > 0),
    CONSTRAINT fk_order_structure_order
        FOREIGN KEY (order_id) REFERENCES "order" (order_id) ON DELETE CASCADE,
    CONSTRAINT fk_order_structure_product
        FOREIGN KEY (product_id) REFERENCES product (product_id) ON DELETE RESTRICT
);

CREATE TABLE review (
    review_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id uuid NOT NULL,
    review_timestamp timestamp without time zone NOT NULL DEFAULT localtimestamp,
    entity_id uuid NOT NULL,
    entity_type review_entity_type NOT NULL,
    order_id uuid NOT NULL,
    description text NOT NULL,
    photo_url text,
    rating numeric(2,1) NOT NULL,
    CONSTRAINT uq_review_order_entity UNIQUE (order_id, entity_type, entity_id),
    CONSTRAINT ck_review_description_nonempty CHECK (btrim(description) <> ''),
    CONSTRAINT ck_review_photo_url CHECK (photo_url IS NULL OR btrim(photo_url) <> ''),
    CONSTRAINT ck_review_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT fk_review_client
        FOREIGN KEY (client_id) REFERENCES client (client_id) ON DELETE RESTRICT,
    CONSTRAINT fk_review_order
        FOREIGN KEY (order_id) REFERENCES "order" (order_id) ON DELETE CASCADE
);

CREATE INDEX ix_order_status_timestamp
    ON "order" (status, order_timestamp);
CREATE INDEX ix_order_restaurant_status
    ON "order" (restaurant_id, status);
CREATE INDEX ix_order_courier_status_timestamp
    ON "order" (courier_id, status, order_timestamp);
CREATE INDEX ix_order_structure_product
    ON order_structure (product_id);
CREATE INDEX ix_review_entity
    ON review (entity_type, entity_id);
CREATE INDEX ix_courier_pay_period
    ON courier_pay (year, month);

COMMIT;

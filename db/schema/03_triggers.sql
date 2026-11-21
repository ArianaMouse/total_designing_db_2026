BEGIN;

SET search_path TO makarova_food, exts;

CREATE OR REPLACE FUNCTION validate_order_structure_restaurant()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_order_restaurant uuid;
    v_product_restaurant uuid;
BEGIN
    SELECT restaurant_id
      INTO v_order_restaurant
      FROM "order"
     WHERE order_id = NEW.order_id;

    IF v_order_restaurant IS NULL THEN
        RAISE EXCEPTION 'Заказ % не существует', NEW.order_id;
    END IF;

    SELECT restaurant_id
      INTO v_product_restaurant
      FROM product
     WHERE product_id = NEW.product_id;

    IF v_product_restaurant IS NULL THEN
        RAISE EXCEPTION 'Блюдо % не существует', NEW.product_id;
    END IF;

    IF v_order_restaurant <> v_product_restaurant THEN
        RAISE EXCEPTION
            'Блюдо % принадлежит другому ресторану и не может быть добавлено в заказ %',
            NEW.product_id, NEW.order_id;
    END IF;

    RETURN NEW;
END
$function$;

CREATE TRIGGER trg_order_structure_same_restaurant
BEFORE INSERT OR UPDATE OF order_id, product_id
ON order_structure
FOR EACH ROW
EXECUTE FUNCTION validate_order_structure_restaurant();

CREATE OR REPLACE FUNCTION validate_payment_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_total numeric(14,2);
BEGIN
    SELECT total_amount
      INTO v_total
      FROM "order"
     WHERE order_id = NEW.order_id;

    IF v_total IS NULL THEN
        RAISE EXCEPTION 'Заказ % не существует', NEW.order_id;
    END IF;

    IF NEW.amount <> v_total THEN
        RAISE EXCEPTION
            'Сумма платежа % должна быть равна сумме заказа %',
            NEW.amount, v_total;
    END IF;

    RETURN NEW;
END
$function$;

CREATE TRIGGER trg_payment_validate_amount
BEFORE INSERT OR UPDATE OF order_id, amount
ON payment
FOR EACH ROW
EXECUTE FUNCTION validate_payment_amount();

CREATE OR REPLACE FUNCTION sync_order_pay_status()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_order_id uuid;
    v_pay_status order_pay_status;
BEGIN
    v_order_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;

    SELECT CASE
               WHEN bool_or(p.status = 'успех')
                   THEN 'оплачен'::order_pay_status
               WHEN bool_or(p.status = 'в_обработке')
                   THEN 'ожидает'::order_pay_status
               WHEN count(*) > 0
                   THEN 'ошибка'::order_pay_status
               ELSE 'ожидает'::order_pay_status
           END
      INTO v_pay_status
      FROM payment p
     WHERE p.order_id = v_order_id;

    UPDATE "order"
       SET pay_status = v_pay_status
     WHERE order_id = v_order_id;

    IF TG_OP = 'UPDATE' AND OLD.order_id <> NEW.order_id THEN
        SELECT CASE
                   WHEN bool_or(p.status = 'успех')
                       THEN 'оплачен'::order_pay_status
                   WHEN bool_or(p.status = 'в_обработке')
                       THEN 'ожидает'::order_pay_status
                   WHEN count(*) > 0
                       THEN 'ошибка'::order_pay_status
                   ELSE 'ожидает'::order_pay_status
               END
          INTO v_pay_status
          FROM payment p
         WHERE p.order_id = OLD.order_id;

        UPDATE "order"
           SET pay_status = v_pay_status
         WHERE order_id = OLD.order_id;
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END
$function$;

CREATE TRIGGER trg_payment_sync_order_status
AFTER INSERT OR UPDATE OF order_id, status OR DELETE
ON payment
FOR EACH ROW
EXECUTE FUNCTION sync_order_pay_status();

CREATE OR REPLACE FUNCTION validate_review_target()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_client_id uuid;
    v_restaurant_id uuid;
    v_valid boolean;
BEGIN
    SELECT client_id, restaurant_id
      INTO v_client_id, v_restaurant_id
      FROM "order"
     WHERE order_id = NEW.order_id;

    IF v_client_id IS NULL THEN
        RAISE EXCEPTION 'Заказ % не существует', NEW.order_id;
    END IF;

    IF NEW.client_id <> v_client_id THEN
        RAISE EXCEPTION 'Отзыв может оставить только клиент, оформивший заказ %', NEW.order_id;
    END IF;

    CASE NEW.entity_type
        WHEN 'заказ' THEN
            v_valid := NEW.entity_id = NEW.order_id;
        WHEN 'ресторан' THEN
            v_valid := NEW.entity_id = v_restaurant_id;
        WHEN 'блюдо' THEN
            SELECT EXISTS (
                SELECT 1
                  FROM order_structure os
                 WHERE os.order_id = NEW.order_id
                   AND os.product_id = NEW.entity_id
            ) INTO v_valid;
    END CASE;

    IF NOT coalesce(v_valid, false) THEN
        RAISE EXCEPTION
            'Объект % типа % не относится к заказу %',
            NEW.entity_id, NEW.entity_type, NEW.order_id;
    END IF;

    RETURN NEW;
END
$function$;

CREATE TRIGGER trg_review_validate_target
BEFORE INSERT OR UPDATE OF client_id, order_id, entity_id, entity_type
ON review
FOR EACH ROW
EXECUTE FUNCTION validate_review_target();

CREATE OR REPLACE FUNCTION recalculate_entity_rating(
    p_entity_type review_entity_type,
    p_entity_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_rating numeric(3,2);
BEGIN
    IF p_entity_type = 'блюдо' THEN
        SELECT round(avg(r.rating), 2)
          INTO v_rating
          FROM review r
         WHERE r.entity_type = 'блюдо'
           AND r.entity_id = p_entity_id;

        UPDATE product
           SET rating = v_rating
         WHERE product_id = p_entity_id;
    ELSIF p_entity_type = 'ресторан' THEN
        SELECT round(avg(r.rating), 2)
          INTO v_rating
          FROM review r
         WHERE r.entity_type = 'ресторан'
           AND r.entity_id = p_entity_id;

        UPDATE restaurant
           SET rating = v_rating
         WHERE restaurant_id = p_entity_id;
    END IF;
END
$function$;

CREATE OR REPLACE FUNCTION rating_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        PERFORM recalculate_entity_rating(OLD.entity_type, OLD.entity_id);
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM recalculate_entity_rating(NEW.entity_type, NEW.entity_id);
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END
$function$;

CREATE TRIGGER trg_review_rating_change
AFTER INSERT OR UPDATE OR DELETE
ON review
FOR EACH ROW
EXECUTE FUNCTION rating_change();

COMMIT;

BEGIN;

SET search_path TO makarova_food, exts;

CREATE OR REPLACE FUNCTION get_statistic()
RETURNS TABLE (
    restaurant_name varchar,
    best_product_name varchar,
    total_amount numeric,
    avg_amount numeric,
    best_user varchar
)
LANGUAGE sql
AS $function$
    WITH delivered_orders AS MATERIALIZED (
        SELECT o.order_id,
               o.restaurant_id,
               o.client_id,
               o.total_amount
          FROM "order" o
         WHERE o.status = 'доставлен'
    ),
    restaurant_totals AS (
        SELECT d.restaurant_id,
               sum(d.total_amount) AS total_amount,
               avg(d.total_amount) AS avg_amount
          FROM delivered_orders d
         GROUP BY d.restaurant_id
    ),
    product_totals AS (
        SELECT d.restaurant_id,
               p.product_id,
               p.product_name,
               sum(os.quantity) AS total_quantity
          FROM delivered_orders d
          JOIN order_structure os ON os.order_id = d.order_id
          JOIN product p ON p.product_id = os.product_id
         GROUP BY d.restaurant_id, p.product_id, p.product_name
    ),
    best_products AS (
        SELECT DISTINCT ON (pt.restaurant_id)
               pt.restaurant_id,
               pt.product_name
          FROM product_totals pt
         ORDER BY pt.restaurant_id, pt.total_quantity DESC, random()
    ),
    user_totals AS (
        SELECT d.restaurant_id,
               c.client_id,
               c.login,
               count(*) AS order_count
          FROM delivered_orders d
          JOIN client c ON c.client_id = d.client_id
         GROUP BY d.restaurant_id, c.client_id, c.login
    ),
    best_users AS (
        SELECT DISTINCT ON (ut.restaurant_id)
               ut.restaurant_id,
               ut.login
          FROM user_totals ut
         ORDER BY ut.restaurant_id, ut.order_count DESC, random()
    )
    SELECT r.restaurant_name,
           bp.product_name AS best_product_name,
           coalesce(round(rt.total_amount, 2), 0::numeric) AS total_amount,
           coalesce(round(rt.avg_amount, 2), 0::numeric) AS avg_amount,
           bu.login AS best_user
      FROM restaurant r
      LEFT JOIN restaurant_totals rt ON rt.restaurant_id = r.restaurant_id
      LEFT JOIN best_products bp ON bp.restaurant_id = r.restaurant_id
      LEFT JOIN best_users bu ON bu.restaurant_id = r.restaurant_id;
$function$;

CREATE OR REPLACE VIEW how_much_money AS
WITH RECURSIVE
bounds AS (
    SELECT min(date_trunc('month', o.order_timestamp))::date AS first_month,
           max(date_trunc('month', o.order_timestamp))::date AS last_month
      FROM "order" o
     WHERE o.status = 'доставлен'
),
months (month_start) AS (
    SELECT b.first_month
      FROM bounds b
     WHERE b.first_month IS NOT NULL

    UNION ALL

    SELECT (m.month_start + interval '1 month')::date
      FROM months m
      CROSS JOIN bounds b
     WHERE m.month_start < b.last_month
),
order_sums AS (
    SELECT date_trunc('month', o.order_timestamp)::date AS month_start,
           sum(o.order_amount) AS sum_no_commission,
           sum(o.total_amount) AS sum_with_commission
      FROM "order" o
     WHERE o.status = 'доставлен'
     GROUP BY date_trunc('month', o.order_timestamp)::date
),
pay_sums AS (
    SELECT make_date(cp.year, cp.month, 1) AS month_start,
           sum(cp.amount) AS courier_pay
      FROM courier_pay cp
     GROUP BY make_date(cp.year, cp.month, 1)
),
monthly AS (
    SELECT m.month_start,
           coalesce(os.sum_no_commission, 0::numeric) AS sum_no_commission,
           coalesce(os.sum_with_commission, 0::numeric) AS sum_with_commission,
           coalesce(os.sum_with_commission, 0::numeric)
               - coalesce(os.sum_no_commission, 0::numeric) AS commission,
           coalesce(ps.courier_pay, 0::numeric) AS courier_pay
      FROM months m
      LEFT JOIN order_sums os ON os.month_start = m.month_start
      LEFT JOIN pay_sums ps ON ps.month_start = m.month_start
),
with_previous AS (
    SELECT mo.*,
           lag(mo.commission) OVER (ORDER BY mo.month_start) AS prev_commission
      FROM monthly mo
)
SELECT to_char(wp.month_start, 'YYYY-MM')::text AS year_month,
       wp.sum_no_commission::numeric AS sum_no_commission,
       wp.sum_with_commission::numeric AS sum_with_commission,
       wp.commission::numeric AS commission,
       wp.prev_commission::numeric AS prev_commission,
       (wp.commission - wp.prev_commission)::numeric AS commission_diff,
       wp.courier_pay::numeric AS courier_pay,
       (wp.commission - wp.courier_pay)::numeric AS net_profit
  FROM with_previous wp;

COMMIT;


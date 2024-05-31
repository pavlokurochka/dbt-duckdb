WITH raw_orders AS (
    SELECT *
    FROM
        {{ ref('jaffle_shop_orders') }}
),

raw_customers AS (
    SELECT *
    FROM
        {{ ref('jaffle_shop_customers') }}
),

raw_payments AS (
    SELECT *
    FROM
        {{ ref('stripe_payments') }}
),

paid_orders AS (
    SELECT
        orders.id AS order_id,
        orders.user_id AS customer_id,
        orders.order_date AS order_placed_at,
        orders.status AS order_status,
        p.total_amount_paid,
        p.payment_finalized_date,
        c.first_name AS customer_first_name,
        c.last_name AS customer_last_name
    FROM
        raw_orders AS orders
    LEFT JOIN (
        SELECT
            orderid AS order_id,
            max(created) AS payment_finalized_date,
            sum(amount) / 100.0 AS total_amount_paid
        FROM
            raw_payments
        WHERE
            status <> 'fail'
        GROUP BY
            1
    ) p ON orders.id = p.order_id
    LEFT JOIN raw_customers c ON orders.user_id = c.id
),

customer_orders AS (
    SELECT
        c.id AS customer_id,
        min(orders.order_date) AS first_order_date,
        max(orders.order_date) AS most_recent_order_date,
        count(orders.id) AS number_of_orders
    FROM
        raw_customers c
    LEFT JOIN raw_orders AS orders ON c.id = orders.user_id
    GROUP BY
        1
)

SELECT
    p.*,
    row_number() OVER (
        ORDER BY
            p.order_id
    ) AS transaction_seq,
    row_number() OVER (
        PARTITION BY p.customer_id
        ORDER BY
            p.order_id
    ) AS customer_sales_seq,
    CASE
        WHEN c.first_order_date = p.order_placed_at THEN 'new'
        ELSE 'return'
    END AS nvsr,
    x.clv_bad AS customer_lifetime_value,
    c.first_order_date AS fdos
FROM
    paid_orders p
LEFT JOIN customer_orders AS c ON p.customer_id = c.customer_id
LEFT OUTER JOIN (
    SELECT
        p.order_id,
        sum(t2.total_amount_paid) AS clv_bad
    FROM
        paid_orders p
    LEFT JOIN paid_orders t2
        ON
            p.customer_id = t2.customer_id
            AND p.order_id >= t2.order_id
    GROUP BY
        1
    ORDER BY
        p.order_id
) x ON p.order_id = x.order_id
ORDER BY
    p.order_id

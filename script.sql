CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dw;

CREATE TABLE IF NOT EXISTS staging.sales (
    row_id        INTEGER        NOT NULL PRIMARY KEY,
    order_id      VARCHAR(20)    NOT NULL,
    order_date    DATE           NOT NULL,
    ship_date     DATE           NOT NULL,
    ship_mode     VARCHAR(20)    NOT NULL,
    customer_id   VARCHAR(20)    NOT NULL,
    customer_name VARCHAR(60)    NOT NULL,
    segment       VARCHAR(20)    NOT NULL,
    country       VARCHAR(40)    NOT NULL,
    city          VARCHAR(60)    NOT NULL,
    state         VARCHAR(40)    NOT NULL,
    postal_code   VARCHAR(10)    NOT NULL,
    region        VARCHAR(20)    NOT NULL,
    product_id    VARCHAR(20)    NOT NULL,
    category      VARCHAR(30)    NOT NULL,
    sub_category  VARCHAR(30)    NOT NULL,
    product_name  VARCHAR(200)   NOT NULL,
    sales         NUMERIC(12,2)  NOT NULL
);

-- ENUNCIADO 10
SELECT COUNT(*)                                        AS linhas,
       SUM(sales)                                      AS soma_sales,
       MIN(order_date)                                 AS menor_data_pedido,
       MAX(ship_date)                                  AS maior_data_envio,
       COUNT(*) FILTER (WHERE postal_code = 'N/D')     AS codigos_postais_nd,
       COUNT(*) FILTER (WHERE ship_date < order_date)  AS envio_antes_do_pedido
FROM staging.sales;
-- Resultado (preencher com a execução real):
--   linhas = 9800
--   soma_sales = 2261536.97
--   menor_data_pedido = 2015-01-03
--   maior_data_envio = 2019-01-05
--   codigos_postais_nd = 11
--   envio_antes_do_pedido = 0
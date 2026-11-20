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

-- ENUNCIADO 11
DROP TABLE IF EXISTS dw.dim_date CASCADE;
CREATE TABLE dw.dim_date (
    date_sk      INTEGER PRIMARY KEY,         -- no formato AAAAMMDD
    full_date    DATE        NOT NULL UNIQUE,
    day          SMALLINT    NOT NULL,
    month        SMALLINT    NOT NULL,
    month_name   VARCHAR(15) NOT NULL,
    quarter      SMALLINT    NOT NULL,
    year         SMALLINT    NOT NULL,
    day_of_week  VARCHAR(15) NOT NULL,
    is_weekend   BOOLEAN     NOT NULL
);

INSERT INTO dw.dim_date
SELECT
    CAST(TO_CHAR(d, 'YYYYMMDD') AS INTEGER),
    d::DATE,
    EXTRACT(DAY     FROM d)::SMALLINT,
    EXTRACT(MONTH   FROM d)::SMALLINT,
    TO_CHAR(d, 'TMMonth'),
    EXTRACT(QUARTER FROM d)::SMALLINT,
    EXTRACT(YEAR    FROM d)::SMALLINT,
    TO_CHAR(d, 'TMDay'),
    EXTRACT(DOW FROM d) IN (0, 6)
FROM generate_series(
         -- 1o de janeiro do ano do primeiro pedido
         (SELECT date_trunc('year', MIN(order_date)) FROM staging.sales),
         -- 31 de dezembro do ano do ultimo envio
         (SELECT date_trunc('year', MAX(ship_date)) + INTERVAL '1 year - 1 day'
            FROM staging.sales),
         INTERVAL '1 day') g(d);

SELECT MIN(full_date), MAX(full_date), COUNT(*) FROM dw.dim_date;

/*O calendário termina com base na maior data de envio, e não na maior data de pedido,
porque um pedido pode ser enviado dias ou meses depois de sua realização.
Dessa forma, garantimos que todas as datas de envio estejam contempladas na dimensão,
permitindo analisar tanto quando os pedidos foram realizados quanto quando foram enviados.*/

-- ENUNCIADO 12
-- (a) product_id com mais de um product_name
SELECT COUNT(*) AS product_id_com_mais_de_um_nome
FROM (
    SELECT product_id
    FROM staging.sales
    GROUP BY product_id
    HAVING COUNT(DISTINCT product_name) > 1
) AS x;
-- Resultado: 32

-- (b) customer_id com mais de um customer_name ou mais de um segment
SELECT COUNT(*) AS customer_id_com_atributo_duplicado
FROM (
    SELECT customer_id
    FROM staging.sales
    GROUP BY customer_id
    HAVING COUNT(DISTINCT customer_name) > 1
        OR COUNT(DISTINCT segment) > 1
) AS x;
-- Resultado: 0

-- (c) combinações de cidade, estado e código postal com mais de uma região
SELECT COUNT(*) AS combinacoes_com_mais_de_uma_regiao
FROM (
    SELECT city, state, postal_code
    FROM staging.sales
    GROUP BY city, state, postal_code
    HAVING COUNT(DISTINCT region) > 1
) AS x;
-- Resultado: 0


-- Enunciado 13 

DROP TABLE IF EXISTS dw.dim_ship_mode CASCADE;
CREATE TABLE dw.dim_ship_mode (
    ship_mode_sk SERIAL PRIMARY KEY,
    ship_mode    VARCHAR(20) NOT NULL UNIQUE
);

DROP TABLE IF EXISTS dw.dim_customer CASCADE;
CREATE TABLE dw.dim_customer (
    customer_sk   SERIAL PRIMARY KEY,
    customer_id   VARCHAR(20) NOT NULL UNIQUE,
    customer_name VARCHAR(60) NOT NULL,
    segment       VARCHAR(20) NOT NULL
);

DROP TABLE IF EXISTS dw.dim_product CASCADE;
CREATE TABLE dw.dim_product (
    product_sk   SERIAL PRIMARY KEY,
    product_id   VARCHAR(20)  NOT NULL UNIQUE,
    product_name VARCHAR(200) NOT NULL,
    category     VARCHAR(30)  NOT NULL,
    sub_category VARCHAR(30)  NOT NULL
);

DROP TABLE IF EXISTS dw.dim_location CASCADE;
CREATE TABLE dw.dim_location (
    location_sk SERIAL PRIMARY KEY,
    country     VARCHAR(40) NOT NULL,
    state       VARCHAR(40) NOT NULL,
    city        VARCHAR(60) NOT NULL,
    postal_code VARCHAR(10) NOT NULL,
    region      VARCHAR(20) NOT NULL,
    UNIQUE (country, state, city, postal_code)
);

DROP TABLE IF EXISTS dw.fact_sales CASCADE;
CREATE TABLE dw.fact_sales (
    sale_sk        SERIAL PRIMARY KEY,
    row_nk         INTEGER       NOT NULL UNIQUE,
    order_nk       VARCHAR(20)   NOT NULL,
    order_date_sk  INTEGER       NOT NULL REFERENCES dw.dim_date(date_sk),
    ship_date_sk   INTEGER       NOT NULL REFERENCES dw.dim_date(date_sk),
    customer_sk    INTEGER       NOT NULL REFERENCES dw.dim_customer(customer_sk),
    product_sk     INTEGER       NOT NULL REFERENCES dw.dim_product(product_sk),
    location_sk    INTEGER       NOT NULL REFERENCES dw.dim_location(location_sk),
    ship_mode_sk   INTEGER       NOT NULL REFERENCES dw.dim_ship_mode(ship_mode_sk),
    sales          NUMERIC(12,2) NOT NULL,
    ship_days      INTEGER       NOT NULL
);

CREATE INDEX ix_fs_order_date ON dw.fact_sales(order_date_sk);
CREATE INDEX ix_fs_ship_date  ON dw.fact_sales(ship_date_sk);
CREATE INDEX ix_fs_customer   ON dw.fact_sales(customer_sk);
CREATE INDEX ix_fs_product    ON dw.fact_sales(product_sk);
CREATE INDEX ix_fs_location   ON dw.fact_sales(location_sk);
CREATE INDEX ix_fs_ship_mode  ON dw.fact_sales(ship_mode_sk);

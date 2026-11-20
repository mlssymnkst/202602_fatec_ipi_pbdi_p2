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

-- ENUNCIADO 14 (PROCEDURE PARA CARREGAR O DW)
CREATE OR REPLACE PROCEDURE dw.carrega_dw()
LANGUAGE plpgsql
AS $$
DECLARE
    v_linhas   BIGINT;
    v_fato     BIGINT;
    v_staging  BIGINT;
BEGIN
    -- (a) esvazia a fato e as quatro dimensões (dim_date fica intacta)
    TRUNCATE dw.fact_sales, dw.dim_customer, dw.dim_product,
             dw.dim_location, dw.dim_ship_mode
             RESTART IDENTITY CASCADE;

    -- (b) Regra para chaves naturais com mais de um valor de atributo:
    -- usa-se o MENOR valor em ordem alfabética (MIN). A escolha é
    -- determinística e repetível: a mesma staging gera sempre as mesmas
    -- dimensões, independentemente da ordem em que o Spark gravou as linhas.

    INSERT INTO dw.dim_ship_mode (ship_mode)
    SELECT DISTINCT ship_mode
    FROM staging.sales
    ORDER BY ship_mode;
    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RAISE NOTICE 'dim_ship_mode: % linhas inseridas', v_linhas;

    INSERT INTO dw.dim_customer (customer_id, customer_name, segment)
    SELECT customer_id, MIN(customer_name), MIN(segment)
    FROM staging.sales
    GROUP BY customer_id
    ORDER BY customer_id;
    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RAISE NOTICE 'dim_customer: % linhas inseridas', v_linhas;

    INSERT INTO dw.dim_product (product_id, product_name, category, sub_category)
    SELECT product_id, MIN(product_name), MIN(category), MIN(sub_category)
    FROM staging.sales
    GROUP BY product_id
    ORDER BY product_id;
    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RAISE NOTICE 'dim_product: % linhas inseridas', v_linhas;

    INSERT INTO dw.dim_location (country, state, city, postal_code, region)
    SELECT country, state, city, postal_code, MIN(region)
    FROM staging.sales
    GROUP BY country, state, city, postal_code
    ORDER BY country, state, city, postal_code;
    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RAISE NOTICE 'dim_location: % linhas inseridas', v_linhas;

    -- (c) fato: surrogate keys por JOIN; chaves de data por formatação
    INSERT INTO dw.fact_sales
        (row_nk, order_nk, order_date_sk, ship_date_sk,
         customer_sk, product_sk, location_sk, ship_mode_sk,
         sales, ship_days)
    SELECT s.row_id,
           s.order_id,
           to_char(s.order_date, 'YYYYMMDD')::INT,
           to_char(s.ship_date,  'YYYYMMDD')::INT,
           c.customer_sk,
           p.product_sk,
           l.location_sk,
           m.ship_mode_sk,
           s.sales,
           (s.ship_date - s.order_date)
    FROM staging.sales s
    JOIN dw.dim_customer  c ON c.customer_id = s.customer_id
    JOIN dw.dim_product   p ON p.product_id  = s.product_id
    JOIN dw.dim_location  l ON l.country     = s.country
                           AND l.state       = s.state
                           AND l.city        = s.city
                           AND l.postal_code = s.postal_code
    JOIN dw.dim_ship_mode m ON m.ship_mode   = s.ship_mode;
    GET DIAGNOSTICS v_linhas = ROW_COUNT;
    RAISE NOTICE 'fact_sales: % linhas inseridas', v_linhas;

    -- (e) confere se algum JOIN descartou linhas em silêncio
    SELECT COUNT(*) INTO v_fato    FROM dw.fact_sales;
    SELECT COUNT(*) INTO v_staging FROM staging.sales;
    IF v_fato <> v_staging THEN
        RAISE EXCEPTION 'Carga incompleta: fact_sales tem % linhas e staging.sales tem %',
            v_fato, v_staging;
    END IF;
    RAISE NOTICE 'Carga conferida: % linhas na fato e na staging', v_fato;
END;
$$;

-- EXECUTA A PROCEDURE PARA CARREGAR O DW
CALL dw.carrega_dw();

-- CONSULTA PARA CONFERIR O RESULTADO DA CARGA
SELECT 'dim_customer' AS tabela, COUNT(*) AS linhas FROM dw.dim_customer
UNION ALL
SELECT 'dim_product',  COUNT(*) FROM dw.dim_product
UNION ALL
SELECT 'dim_location', COUNT(*) FROM dw.dim_location
UNION ALL
SELECT 'dim_ship_mode', COUNT(*) FROM dw.dim_ship_mode
UNION ALL
SELECT 'fact_sales',   COUNT(*) FROM dw.fact_sales;

-- Resultado:
--   dim_customer  = 793
--   dim_product   = 1861
--   dim_location  = 628
--   dim_ship_mode = 4
--   fact_sales    = 9800
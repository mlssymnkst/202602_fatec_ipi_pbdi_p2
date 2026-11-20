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

-- ENUNCIADO 15
DROP TABLE IF EXISTS dw.carga_log CASCADE;
CREATE TABLE dw.carga_log (
    log_id   SERIAL      PRIMARY KEY,
    sale_sk  INTEGER,
    row_nk   INTEGER,
    operacao VARCHAR(10) NOT NULL,
    usuario  TEXT        NOT NULL DEFAULT current_user,
    momento  TIMESTAMP   NOT NULL DEFAULT now()
);

-- Cria a função de auditoria
CREATE OR REPLACE FUNCTION dw.audita_fact_sales()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.sales <= 0 THEN
        RAISE EXCEPTION 'Venda rejeitada (row_nk=%, order_nk=%): valor % deve ser maior que zero',
            NEW.row_nk, NEW.order_nk, NEW.sales;
    END IF;
-- Validação
    IF NEW.ship_days < 0 THEN
        RAISE EXCEPTION 'Venda rejeitada (row_nk=%, order_nk=%): ship_days % não pode ser negativo',
            NEW.row_nk, NEW.order_nk, NEW.ship_days;
    END IF;

-- Registra a operação no log de auditoria
    INSERT INTO dw.carga_log (sale_sk, row_nk, operacao, usuario, momento)
    VALUES (NEW.sale_sk, NEW.row_nk, TG_OP, current_user, now());

    RETURN NEW;   -- sem o RETURN NEW, a linha seria descartada em silêncio
END;
$$;
-- Cria o gatilho de auditoria
DROP TRIGGER IF EXISTS trg_audita_fact_sales ON dw.fact_sales;
CREATE TRIGGER trg_audita_fact_sales
    BEFORE INSERT ON dw.fact_sales
    FOR EACH ROW
    EXECUTE FUNCTION dw.audita_fact_sales();

-- TESTE COM LINHA VALIDA
INSERT INTO dw.fact_sales
    (row_nk, order_nk, order_date_sk, ship_date_sk,
     customer_sk, product_sk, location_sk, ship_mode_sk, sales, ship_days)
SELECT 999999999, 'TESTE-0001',
       (SELECT MIN(date_sk)      FROM dw.dim_date),
       (SELECT MIN(date_sk)      FROM dw.dim_date),
       (SELECT MIN(customer_sk)  FROM dw.dim_customer),
       (SELECT MIN(product_sk)   FROM dw.dim_product),
       (SELECT MIN(location_sk)  FROM dw.dim_location),
       (SELECT MIN(ship_mode_sk) FROM dw.dim_ship_mode),
       10.00, 2;

SELECT * FROM dw.carga_log WHERE row_nk = 999999999;

--  TESTE COM LINHA INVALIDA 
-- INSERT INTO dw.fact_sales
--     (row_nk, order_nk, order_date_sk, ship_date_sk,
--      customer_sk, product_sk, location_sk, ship_mode_sk, sales, ship_days)
-- SELECT 999999998, 'TESTE-0002',
--        (SELECT MIN(date_sk)      FROM dw.dim_date),
--        (SELECT MIN(date_sk)      FROM dw.dim_date),
--        (SELECT MIN(customer_sk)  FROM dw.dim_customer),
--        (SELECT MIN(product_sk)   FROM dw.dim_product),
--        (SELECT MIN(location_sk)  FROM dw.dim_location),
--        (SELECT MIN(ship_mode_sk) FROM dw.dim_ship_mode),
--        0, 2;
       
--        ERROR:  Venda rejeitada (row_nk=999999998, order_nk=TESTE-0002): valor 0.00 deve ser maior que zero

-- esvaziar o log, recarregar e conferir
TRUNCATE dw.carga_log RESTART IDENTITY;
CALL dw.carrega_dw();   

SELECT (SELECT COUNT(*) FROM dw.carga_log)  AS linhas_no_log,
       (SELECT COUNT(*) FROM dw.fact_sales) AS linhas_na_fato;

-- LINHAS NO LOG = 9800
-- LINHAS NA FATO = 9800

-- ENUNCIADO 16
SELECT l.region,
       p.category,
       COUNT(DISTINCT f.order_nk) AS pedidos,
       COUNT(*)                   AS itens,
       SUM(f.sales)               AS receita
FROM dw.fact_sales f
JOIN dw.dim_location l ON l.location_sk = f.location_sk
JOIN dw.dim_product  p ON p.product_sk  = f.product_sk
GROUP BY l.region, p.category
ORDER BY receita DESC;
/*
 region  |    category     | pedidos | itens |  receita  
---------+-----------------+---------+-------+-----------
 East    | Technology      |     436 |   527 | 263116.59
 West    | Technology      |     483 |   589 | 247404.95
 West    | Furniture       |     582 |   691 | 245348.36
 West    | Office Supplies |    1150 |  1860 | 217466.46
 East    | Furniture       |     480 |   591 | 206461.36
 East    | Office Supplies |    1048 |  1667 | 199940.90
 Central | Technology      |     348 |   408 | 168739.19
 Central | Office Supplies |     865 |  1399 | 163590.15
 Central | Furniture       |     393 |   470 | 160317.56
 South   | Technology      |     252 |   289 | 148195.21
--More--
*/

-- ENUNCIADO 17
SELECT m.ship_mode,
       COUNT(*)                     AS itens,
       ROUND(AVG(f.ship_days), 1)   AS media_ship_days,
       MIN(f.ship_days)             AS menor_ship_days,
       MAX(f.ship_days)             AS maior_ship_days
FROM dw.fact_sales f
JOIN dw.dim_ship_mode m ON m.ship_mode_sk = f.ship_mode_sk
GROUP BY m.ship_mode
ORDER BY AVG(f.ship_days) ASC;

/*
   ship_mode    | itens | media_ship_days | menor_ship_days | maior_ship_days 
----------------+-------+-----------------+-----------------+-----------------
 Same Day       |   538 |             0.0 |               0 |               1
 First Class    |  1501 |             2.2 |               1 |               4
 Second Class   |  1902 |             3.2 |               1 |               5
 Standard Class |  5859 |             5.0 |               3 |               7
*/

-- ENUNCIADO 18
WITH receita_cliente AS (
    SELECT c.customer_sk,
           c.customer_name,
           c.segment,
           SUM(f.sales) AS receita
    FROM dw.fact_sales f
    JOIN dw.dim_customer c ON c.customer_sk = f.customer_sk
    GROUP BY c.customer_sk, c.customer_name, c.segment
)
SELECT customer_name,
       segment,
       receita,
       ROUND(100.0 * receita / SUM(receita) OVER (), 2) AS participacao_pct
FROM receita_cliente
ORDER BY receita DESC
LIMIT 10;
/*
   customer_name    |   segment   | receita  | participacao_pct 
--------------------+-------------+----------+------------------
 Sean Miller        | Home Office | 25043.07 |             1.11
 Tamara Chand       | Corporate   | 19052.22 |             0.84
 Raymond Buch       | Consumer    | 15117.35 |             0.67
 Tom Ashbrook       | Home Office | 14595.62 |             0.65
 Adrian Barton      | Consumer    | 14473.57 |             0.64
 Ken Lonsdale       | Consumer    | 14175.23 |             0.63
 Sanjit Chand       | Consumer    | 14142.34 |             0.63
 Hunter Lopez       | Consumer    | 12873.30 |             0.57
 Sanjit Engle       | Consumer    | 12209.44 |             0.54
 Christopher Conant | Consumer    | 12129.08 |             0.54
(10 rows)
*/

-- ENUNCIADO 19
SELECT od.year                                      AS ano_pedido,
       COUNT(*)                                     AS itens,
       SUM(f.sales)                                 AS receita,
       COUNT(*) FILTER (WHERE sd.is_weekend)        AS itens_enviados_fim_de_semana
FROM dw.fact_sales f
JOIN dw.dim_date od ON od.date_sk = f.order_date_sk
JOIN dw.dim_date sd ON sd.date_sk = f.ship_date_sk
GROUP BY od.year
ORDER BY od.year;

/*
 ano_pedido | itens |  receita  | itens_enviados_fim_de_semana 
------------+-------+-----------+------------------------------
       2015 |  1953 | 479856.27 |                          632
       2016 |  2055 | 459435.94 |                          661
       2017 |  2534 | 600192.80 |                          812
       2018 |  3258 | 722051.96 |                          867
(4 rows)
*/ 
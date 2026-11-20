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
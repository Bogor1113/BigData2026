CREATE DATABASE IF NOT EXISTS ads
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;

USE ads;

CREATE TABLE IF NOT EXISTS ads.ads_user_daily_report (
    stat_date                 VARCHAR(20)     NOT NULL COMMENT '统计日期',
    valid_users_count         BIGINT          DEFAULT NULL COMMENT '有效用户数（有首单日期的用户）',
    daily_active_users        BIGINT          DEFAULT NULL COMMENT '日活跃用户数（当日下单用户）',
    order_count               BIGINT          DEFAULT NULL COMMENT '订单量',
    order_amount              DECIMAL(20,2)   DEFAULT NULL COMMENT '订单金额',
    pay_order_count           BIGINT          DEFAULT NULL COMMENT '支付订单数',
    pay_amount                DECIMAL(20,2)   DEFAULT NULL COMMENT '支付金额',
    order_conversion_rate     DECIMAL(20,4)   DEFAULT NULL COMMENT '下单转化率 = 订单量/有效用户数',
    pay_conversion_rate       DECIMAL(20,4)   DEFAULT NULL COMMENT '支付转化率 = 支付订单数/有效用户数',
    avg_order_amount          DECIMAL(20,2)   DEFAULT NULL COMMENT '人均订单金额 = 总订单金额/有效用户数',
    order_count_dod_rate      DECIMAL(20,2)   DEFAULT NULL COMMENT '订单量环比增长率(%)',
    pay_amount_dod_rate       DECIMAL(20,2)   DEFAULT NULL COMMENT '支付金额环比增长率(%)',
    PRIMARY KEY (stat_date)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_general_ci
  COMMENT='用户每日统计报表';
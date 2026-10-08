-- ============================================================
-- ADS 层：用户每日统计报表
-- 调度传参：--hiveconf dt=yyyy-MM-dd（数据日期，正常调度为昨天）
-- 按 stat_date 分区写入，重跑同一日期自动覆盖，幂等
-- ============================================================

create database if not exists ads;

create table if not exists ads.ads_user_daily_report
(
    valid_users_count     BIGINT        COMMENT '有效用户数（有首单日期的用户）',
    daily_active_users    BIGINT        COMMENT '日活跃用户数（当日下单用户）',
    order_count           BIGINT        COMMENT '订单量',
    order_amount          DECIMAL(20,2) COMMENT '订单金额',
    pay_order_count       BIGINT        COMMENT '支付订单数',
    pay_amount            DECIMAL(20,2) COMMENT '支付金额',
    order_conversion_rate DECIMAL(20,4) COMMENT '下单转化率 = 订单量/有效用户数',
    pay_conversion_rate   DECIMAL(20,4) COMMENT '支付转化率 = 支付订单数/有效用户数',
    avg_order_amount      DECIMAL(20,2) COMMENT '人均订单金额 = 总订单金额/有效用户数',
    order_count_dod_rate  DECIMAL(20,2) COMMENT '订单量环比增长率(%)',
    pay_amount_dod_rate   DECIMAL(20,2) COMMENT '支付金额环比增长率(%)'
)
partitioned by (stat_date STRING COMMENT '统计日期')
stored as textfile;

with cur as (
    select
        -- 原写法 first_order_date is not null or first_order_date != '' 属于恒真条件，改为只判非空
        sum(if(first_order_date is not null, 1, 0))          as valid_users_count,
        count(if(is_current_order_ct != 0, 1, null))         as daily_active_users,
        sum(is_current_order_ct)                             as order_count,
        sum(is_current_order_amount)                          as order_amount,
        count(if(is_current_pay_ct != 0, 1, null))           as pay_order_count,
        sum(is_current_pay_amount)                            as pay_amount,
        sum(total_order_amount)                              as total_order_amount
    from dws.dws_user_topic_wide
),
pre as (
    -- 前天快照：用于计算环比
    select
        sum(day_order_count) as pre_order_count,
        sum(day_pay_amount)  as pre_pay_amount
    from dws.dws_user_day_snapshot
    where dt = date_sub('${hiveconf:dt}', 2)
)
insert overwrite table ads.ads_user_daily_report partition (stat_date = '${hiveconf:dt}')
select
    c.valid_users_count,
    c.daily_active_users,
    c.order_count,
    c.order_amount,
    c.pay_order_count,
    c.pay_amount,
    -- 除数可能为 0，用 nullif 兜底，避免除零得到 NULL 或报错
    c.order_count       / nullif(c.valid_users_count, 0)                             as order_conversion_rate,
    c.pay_order_count   / nullif(c.valid_users_count, 0)                             as pay_conversion_rate,
    c.total_order_amount / nullif(c.valid_users_count, 0)                            as avg_order_amount,
    (c.order_count - p.pre_order_count) / nullif(p.pre_order_count, 0) * 100         as order_count_dod_rate,
    (c.pay_amount  - p.pre_pay_amount)  / nullif(p.pre_pay_amount, 0)  * 100         as pay_amount_dod_rate
from cur c
cross join pre p;

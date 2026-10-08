-- ============================================================
-- DWS 层：用户日快照（增量计算）
--   day_*   当天指标（当天为用户下单/支付的部分）
--   total_* 累计指标 = 前一天快照累计 + 当天增量
-- 注意：首次初始化或数据回补后，请用 dws_user_day_snapshot_full.sql 全量重刷
-- 调度传参：--hiveconf dt=yyyy-MM-dd
-- ============================================================

set hive.merge.tezfiles = true;
set hive.merge.smallfiles.avgsize = 134217728;
set hive.merge.size.per.task = 268435456;

create database if not exists dws;

create table if not exists dws.dws_user_day_snapshot
(
    user_id           bigint        COMMENT '用户ID',
    day_order_count   int           COMMENT '当日订单数',
    day_order_amount  decimal(10,2) COMMENT '当日订单金额',
    day_pay_count     int           COMMENT '当日支付订单数',
    day_pay_amount    decimal(10,2) COMMENT '当日支付金额',
    total_order_count int           COMMENT '累计订单数',
    total_pay_amount  decimal(20,2) COMMENT '累计支付金额'
)
partitioned by (dt string)
stored as orc
tblproperties ('orc.compress' = 'SNAPPY');

-- 1) 当天订单：dwd 一条订单商品一行，先收敛到订单粒度
with cur_order as (
    select
        user_id,
        order_id,
        max(create_time)        as create_time,
        max(payment_time)       as payment_time,
        max(order_total_amount) as order_total_amount,
        max(order_pay_amount)   as order_pay_amount
    from dwd.dwd_user_order_clean
    where dt = '${hiveconf:dt}'
    group by user_id, order_id
),
-- 2) 当天用户级增量
cur as (
    select
        user_id,
        count(order_id)                                                      as day_order_count,
        sum(order_total_amount)                                              as day_order_amount,
        sum(if(payment_time is not null and payment_time != '', 1, 0))       as day_pay_count,
        sum(if(payment_time is not null and payment_time != '', order_pay_amount, 0)) as day_pay_amount,
        count(order_id)                                                      as incr_order_count,
        sum(order_pay_amount)                                                as incr_pay_amount
    from cur_order
    group by user_id
),
-- 3) 前一天快照里的累计值
pre as (
    select user_id, total_order_count, total_pay_amount
    from dws.dws_user_day_snapshot
    where dt = date_sub('${hiveconf:dt}', 1)
)
insert overwrite table dws.dws_user_day_snapshot partition (dt = '${hiveconf:dt}')
select
    cast(nvl(c.user_id, p.user_id) as bigint)                            as user_id,
    nvl(c.day_order_count, 0)                                           as day_order_count,
    nvl(c.day_order_amount, 0)                                          as day_order_amount,
    nvl(c.day_pay_count, 0)                                             as day_pay_count,
    nvl(c.day_pay_amount, 0)                                            as day_pay_amount,
    nvl(p.total_order_count, 0) + nvl(c.incr_order_count, 0)            as total_order_count,
    nvl(p.total_pay_amount, 0)  + nvl(c.incr_pay_amount, 0)             as total_pay_amount
from cur c
full join pre p on cast(c.user_id as bigint) = p.user_id;

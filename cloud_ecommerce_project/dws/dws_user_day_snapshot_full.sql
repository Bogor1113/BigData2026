-- ============================================================
-- DWS 层：用户日快照（全量重刷）
--   扫描 dt 及以前的全部分区重算累计指标，用于首次初始化、
--   历史数据回补后的重算；日常调度用 dws_user_day_snapshot.sql（增量）
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

-- 先收敛到订单粒度，避免商品行重复计数
with order_all as (
    select
        user_id,
        order_id,
        max(create_time)        as create_time,
        max(payment_time)       as payment_time,
        max(order_total_amount) as order_total_amount,
        max(order_pay_amount)   as order_pay_amount
    from dwd.dwd_user_order_clean
    where dt <= '${hiveconf:dt}'
    group by user_id, order_id
)
insert overwrite table dws.dws_user_day_snapshot partition (dt = '${hiveconf:dt}')
select
    cast(user_id as bigint)                                                        as user_id,
    count(if(substr(create_time, 1, 10) = '${hiveconf:dt}', order_id, null))        as day_order_count,
    sum(if(substr(create_time, 1, 10) = '${hiveconf:dt}', order_total_amount, 0))   as day_order_amount,
    sum(if(substr(payment_time,1,10) = '${hiveconf:dt}' and payment_time != '', 1, 0))                   as day_pay_count,
    sum(if(substr(payment_time,1,10) = '${hiveconf:dt}' and payment_time != '', order_pay_amount, 0))    as day_pay_amount,
    count(order_id)                                                                 as total_order_count,
    sum(order_pay_amount)                                                           as total_pay_amount
from order_all
group by user_id;

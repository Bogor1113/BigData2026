-- ============================================================
-- DWS 层：用户主题宽表（每用户一行，全量覆盖）
-- 内容：用户维度 + 订单行为指标 + 偏好 + RFM 分层与运营策略
-- 调度传参：--hiveconf dt=yyyy-MM-dd（数据日期，正常调度为昨天）
-- ============================================================

set hive.merge.tezfiles = true;
set hive.merge.smallfiles.avgsize = 134217728;
set hive.merge.size.per.task = 268435456;
set hive.auto.convert.join = true;

create database if not exists dws;

create table if not exists dws.dws_user_topic_wide
(
    -- ========== 用户维度 ==========
    user_id          BIGINT        COMMENT '用户ID',
    username         STRING        COMMENT '用户名',
    gender           STRING        COMMENT '性别',
    age              INT           COMMENT '年龄',
    phone            STRING        COMMENT '手机号',
    city             STRING        COMMENT '城市',
    province         STRING        COMMENT '省份',
    register_date    STRING        COMMENT '注册日期',
    register_channel STRING        COMMENT '注册渠道',
    user_level       STRING        COMMENT '用户等级',
    status           STRING        COMMENT '用户状态',
    -- ========== 订单行为指标 ==========
    first_order_date       STRING        COMMENT '首次下单日期',
    last_order_date        STRING        COMMENT '最近下单日期',
    first_pay_date         STRING        COMMENT '首次支付日期',
    last_pay_date          STRING        COMMENT '最近支付日期',
    order_count            BIGINT        COMMENT '累计订单数',
    total_order_amount     DECIMAL(20,2) COMMENT '累计订单总金额',
    pay_order_count        BIGINT        COMMENT '累计支付订单数',
    total_pay_amount       DECIMAL(20,2) COMMENT '累计支付总金额',
    is_current_order_ct    BIGINT        COMMENT '当日下单数',
    is_current_order_amount DECIMAL(20,2) COMMENT '当日下单金额',
    is_current_pay_ct      BIGINT        COMMENT '当日支付数',
    is_current_pay_amount   DECIMAL(20,2) COMMENT '当日支付金额',
    is_current_avg_price   DECIMAL(20,2) COMMENT '当日客单价',
    -- ========== 偏好 ==========
    brand_fav    ARRAY<STRING> COMMENT '品牌偏好',
    category_fav ARRAY<STRING> COMMENT '品类偏好',
    payment_fav  ARRAY<STRING> COMMENT '支付偏好',
    -- ========== 分层与运营策略 ==========
    r                       DOUBLE COMMENT 'R值(最近消费距今/数据日期天数)',
    f                       INT    COMMENT 'F值(消费频次)',
    user_segment            STRING COMMENT '用户分层',
    user_operation_strategy STRING COMMENT '运营策略'
)
stored as orc
tblproperties ('orc.compress' = 'SNAPPY');

-- ============================================================
-- 1. 订单粒度基础表：dwd 只扫这一次，同时把用户维度透传下来
-- ============================================================
create temporary table if not exists tmp_order_level as
select
    user_id,
    order_id,
    max(create_time)                    as create_time,
    max(payment_time)                   as payment_time,
    max(order_total_amount)             as order_total_amount,
    max(order_pay_amount)               as order_pay_amount,
    max(username)                       as username,
    max(gender)                         as gender,
    max(age)                            as age,
    max(if(phone != '****', phone, '')) as phone,
    max(city)                           as city,
    max(province)                       as province,
    max(register_date)                  as register_date,
    max(register_channel)               as register_channel,
    max(user_level)                     as user_level,
    max(status)                         as status
from dwd.dwd_user_order_clean
group by user_id, order_id;

-- ============================================================
-- 2. 用户维度表（每用户一行）
-- ============================================================
create temporary table if not exists tmp_user_dim as
select
    user_id,
    max(username)         as username,
    max(gender)           as gender,
    max(age)              as age,
    max(phone)            as phone,
    max(city)             as city,
    max(province)         as province,
    max(register_date)    as register_date,
    max(register_channel) as register_channel,
    max(user_level)       as user_level,
    max(status)           as status
from tmp_order_level
group by user_id;

-- ============================================================
-- 3. 用户订单行为指标
-- ============================================================
create temporary table if not exists tmp_user_metrics as
select
    user_id,
    date(min(create_time))  as first_order_date,
    date(max(create_time))  as last_order_date,
    date(min(payment_time)) as first_pay_date,
    date(max(payment_time)) as last_pay_date,
    count(order_id)         as order_count,
    sum(order_total_amount) as total_order_amount,
    -- 已支付订单数（原写法 payment_time is not null or payment_time != '' 恒真，改为 and）
    sum(if(payment_time is not null and payment_time != '', 1, 0)) as pay_order_count,
    sum(order_pay_amount)   as total_pay_amount,
    -- 当日指标：以数据日期 dt 为准，便于补跑
    sum(if(substr(create_time,  1, 10) = '${hiveconf:dt}', 1, 0))                  as is_current_order_ct,
    sum(if(substr(create_time,  1, 10) = '${hiveconf:dt}', order_total_amount, 0)) as is_current_order_amount,
    sum(if(substr(payment_time, 1, 10) = '${hiveconf:dt}', 1, 0))                  as is_current_pay_ct,
    sum(if(substr(payment_time, 1, 10) = '${hiveconf:dt}', order_pay_amount, 0))   as is_current_pay_amount,
    round(
        sum(if(substr(create_time, 1, 10) = '${hiveconf:dt}', order_total_amount, 0))
        / nullif(sum(if(substr(create_time, 1, 10) = '${hiveconf:dt}', 1, 0)), 0)
    , 2) as is_current_avg_price
from tmp_order_level
group by user_id;

-- ============================================================
-- 4. 用户偏好：支付方式 / 品牌 / 品类各自的 Top1
--    dwd 明细需按维度聚合，因此这里扫 3 次（各维度粒度不同）
-- ============================================================
create temporary table if not exists tmp_user_fav as
with pay_fav as (
    select
        user_id,
        collect_list(concat(payment_method, ':', rk)) as pay_fav
    from (
        select
            user_id,
            payment_method,
            rank() over (partition by user_id order by count(1) desc) as rk
        from dwd.dwd_user_order_clean
        where payment_method is not null and payment_method != ''
        group by user_id, payment_method
    ) t
    where rk = 1
    group by user_id
),
brand_fav as (
    select
        user_id,
        collect_list(concat(brand_name, ':', rk)) as brand_fav
    from (
        select
            user_id,
            brand_name,
            rank() over (partition by user_id order by count(1) desc) as rk
        from dwd.dwd_user_order_clean
        where brand_name is not null and brand_name != ''
        group by user_id, brand_name
    ) t
    where rk = 1
    group by user_id
),
category_fav as (
    select
        user_id,
        collect_list(concat(category_name, ':', rk)) as category_fav
    from (
        select
            user_id,
            category_name,
            rank() over (partition by user_id order by count(1) desc) as rk
        from dwd.dwd_user_order_clean
        where category_name is not null and category_name != ''
        group by user_id, category_name
    ) t
    where rk = 1
    group by user_id
)
-- 原实现三个维度用 inner join，缺少任一维度的用户会整行丢失，改为 full join
select
    coalesce(p.user_id, b.user_id, c.user_id) as user_id,
    p.pay_fav,
    b.brand_fav,
    c.category_fav
from pay_fav p
full join brand_fav b   on p.user_id = b.user_id
full join category_fav c on coalesce(p.user_id, b.user_id) = c.user_id;

-- ============================================================
-- 5. RFM：按全体用户中位数二分，划分 8 类客户
-- ============================================================
create temporary table if not exists tmp_user_rfm as
with b as (
    select
        user_id,
        datediff('${hiveconf:dt}', max(create_time)) as r,
        count(1)                                     as f,
        sum(order_pay_amount)                        as m
    from tmp_order_level
    group by user_id
),
c as (
    select
        cast(percentile_approx(r, 0.5) as bigint)        as avg_r,
        cast(percentile_approx(f, 0.5) as bigint)        as avg_f,
        -- 金额中位数不能转 bigint，会丢掉小数部分
        cast(percentile_approx(m, 0.5) as decimal(20,2)) as avg_m
    from b
)
select /*+ MAPJOIN(c) */
    b.user_id,
    b.r,
    b.f,
    case
        when r <= c.avg_r and f >= c.avg_f and m >= c.avg_m then '重要价值客户'
        when r <= c.avg_r and f <  c.avg_f and m >= c.avg_m then '重要发展客户'
        when r >  c.avg_r and f >= c.avg_f and m >= c.avg_m then '重要保持客户'
        when r >  c.avg_r and f <  c.avg_f and m >= c.avg_m then '重要挽留客户'
        when r <= c.avg_r and f >= c.avg_f and m <  c.avg_m then '一般价值客户'
        when r <= c.avg_r and f <  c.avg_f and m <  c.avg_m then '一般发展客户'
        when r >  c.avg_r and f >= c.avg_f and m <  c.avg_m then '一般保持客户'
        when r >  c.avg_r and f <  c.avg_f and m <  c.avg_m then '一般挽留客户'
        else '其他'
    end as user_segment,
    case
        when r <= c.avg_r and f >= c.avg_f and m >= c.avg_m then '重点维护，VIP 服务'
        when r <= c.avg_r and f <  c.avg_f and m >= c.avg_m then '提升消费频次'
        when r >  c.avg_r and f >= c.avg_f and m >= c.avg_m then '唤回，防止流失'
        when r >  c.avg_r and f <  c.avg_f and m >= c.avg_m then '强唤回，优惠刺激'
        when r <= c.avg_r and f >= c.avg_f and m <  c.avg_m then '提升客单价'
        when r <= c.avg_r and f <  c.avg_f and m <  c.avg_m then '培养消费习惯'
        when r >  c.avg_r and f >= c.avg_f and m <  c.avg_m then '提升客单价 + 唤回'
        when r >  c.avg_r and f <  c.avg_f and m <  c.avg_m then '低成本触达或放弃'
        else '其他'
    end as user_operation_strategy
from b
cross join c;

-- ============================================================
-- 6. 合并落宽表
-- ============================================================
insert overwrite table dws.dws_user_topic_wide
select
    d.user_id,
    d.username,
    d.gender,
    d.age,
    d.phone,
    d.city,
    d.province,
    d.register_date,
    d.register_channel,
    d.user_level,
    d.status,
    m.first_order_date,
    m.last_order_date,
    m.first_pay_date,
    m.last_pay_date,
    m.order_count,
    m.total_order_amount,
    m.pay_order_count,
    m.total_pay_amount,
    m.is_current_order_ct,
    m.is_current_order_amount,
    m.is_current_pay_ct,
    m.is_current_pay_amount,
    m.is_current_avg_price,
    fav.brand_fav,
    fav.category_fav,
    fav.pay_fav,
    rfm.r,
    rfm.f,
    rfm.user_segment,
    rfm.user_operation_strategy
from tmp_user_dim d
left join tmp_user_metrics m   on d.user_id = m.user_id
left join tmp_user_fav     fav on d.user_id = fav.user_id
left join tmp_user_rfm     rfm on d.user_id = rfm.user_id;

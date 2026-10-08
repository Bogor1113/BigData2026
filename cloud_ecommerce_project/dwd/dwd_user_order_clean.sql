-- ============================================================
-- DWD 层：用户订单明细宽表（一条订单商品一行）
-- 来源：ods 层各表；分区 dt 表示订单创建日期
-- 调度传参：--hiveconf dt=yyyy-MM-dd
-- 重建方式：drop table dwd.dwd_user_order_clean; 再执行本脚本
-- ============================================================

-- 小文件合并（Tez 引擎）
set hive.merge.tezfiles = true;
set hive.merge.smallfiles.avgsize = 134217728;
set hive.merge.size.per.task = 268435456;

-- 品牌/品类/码值都是小表，自动转 MapJoin，避免大表走 shuffle
set hive.auto.convert.join = true;
set hive.auto.convert.join.noconditionaltask = true;
set hive.auto.convert.join.noconditionaltask.size = 20000000;

create database if not exists dwd;

create table if not exists dwd.dwd_user_order_clean
(
    -- ============ 用户信息 ============
    user_id          STRING COMMENT '用户ID',
    username         STRING COMMENT '用户名',
    gender           STRING COMMENT '性别：男/女/未知',
    age              INT    COMMENT '年龄',
    phone            STRING COMMENT '脱敏手机号：138****8888',
    city             STRING COMMENT '城市',
    province         STRING COMMENT '省份',
    register_date    STRING COMMENT '注册日期',
    register_channel STRING COMMENT '注册渠道：APP端/PC端/小程序',
    user_level       STRING COMMENT '用户等级',
    status           STRING COMMENT '用户状态：禁用/正常',
    -- ============ 订单信息 ============
    order_id             STRING COMMENT '订单ID',
    freight_amount       DECIMAL(16,2) COMMENT '运费金额',
    discount_amount      DECIMAL(16,2) COMMENT '优惠金额',
    create_time          STRING COMMENT '订单创建时间',
    payment_time         STRING COMMENT '订单支付时间',
    payment_method       STRING COMMENT '支付方式',
    order_status         STRING COMMENT '订单状态',
    delivery_time        STRING COMMENT '发货时间',
    receive_time         STRING COMMENT '收货时间',
    order_product_amount DECIMAL(16,2) COMMENT '商品金额(单价*数量)',
    order_total_amount   DECIMAL(16,2) COMMENT '订单商品总金额(窗口聚合)',
    order_pay_amount     DECIMAL(16,2) COMMENT '订单应付金额=商品总额-优惠+运费',
    -- ============ 商品信息 ============
    product_name  STRING COMMENT '商品名称',
    category_name STRING COMMENT '品类名称',
    brand_name    STRING COMMENT '品牌名称'
)
partitioned by (dt string comment '分区日期 yyyy-MM-dd')
stored as orc
tblproperties ('orc.compress' = 'SNAPPY');

-- 以订单明细为主表，按天清洗
with code as (
    select * from dim.dim_code_value
),
oi as (
    select
        user_id,
        order_id,
        freight_amount,
        discount_amount,
        create_time,
        payment_time,
        payment_method,
        order_status,
        delivery_time,
        receive_time
    from ods.ods_order_info
    where order_status between 1 and 3      -- 只留已付款/已发货/已完成
      and payment_time > create_time        -- 支付时间必须晚于下单时间
      and payment_time != ''
      and dt = '${hiveconf:dt}'
)
insert overwrite table dwd.dwd_user_order_clean partition (dt = '${hiveconf:dt}')
select
    -- 用户信息
    ou.user_id,
    ou.username,
    if(ou.gender = 1, '男', if(ou.gender = 2, '女', '未知'))         as gender,
    ou.age,
    concat(
        substr(regexp_extract(regexp_replace(replace(ou.phone,'+86',''),'[^0-9]',''),'(^1[3-9]\\d{9}$)',1), 1, 4),
        '****',
        substr(regexp_extract(regexp_replace(replace(ou.phone,'+86',''),'[^0-9]',''),'(^1[3-9]\\d{9}$)',1), -4, 4)
    )                                                               as phone,
    if(ou.city = '', '未知城市', ou.city)                             as city,
    if(ou.province = '', '未知省份', ou.province)                     as province,
    ou.register_date,
    case ou.register_channel
        when 'APP' then 'APP端'
        when 'PC'  then 'PC端'
        else '小程序'
    end                                                             as register_channel,
    c1.code_label                                                   as user_level,
    if(ou.status = 0, '禁用', '正常')                                 as status,
    -- 订单信息
    oi.order_id,
    oi.freight_amount,
    oi.discount_amount,
    oi.create_time,
    oi.payment_time,
    c2.code_label                                                   as payment_method,
    c3.code_label                                                   as order_status,
    oi.delivery_time,
    oi.receive_time,
    od.product_price * od.product_quantity                          as order_product_amount,
    sum(od.product_price * od.product_quantity)
        over (partition by od.order_id)                             as order_total_amount,
    sum(od.product_price * od.product_quantity)
        over (partition by od.order_id)
        - oi.discount_amount + oi.freight_amount                    as order_pay_amount,
    -- 商品信息
    opi.product_name,
    ci.category_name,
    bi.brand_name
from oi
left join ods.ods_order_detail  od  on od.order_id    = oi.order_id
left join ods.ods_user_info     ou  on ou.user_id     = oi.user_id
left join ods.ods_product_info  opi on od.product_id  = opi.product_id
left join ods.ods_category_info ci  on ci.category_id = opi.category_id
left join ods.ods_brand_info    bi  on bi.brand_id    = opi.brand_id
left join code c1 on c1.code_value = cast(ou.user_level as string)   and c1.code_group = 'user_level'
left join code c2 on c2.code_value = oi.payment_method               and c2.code_group = 'payment_method'
left join code c3 on c3.code_value = cast(oi.order_status as string) and c3.code_group = 'order_status';

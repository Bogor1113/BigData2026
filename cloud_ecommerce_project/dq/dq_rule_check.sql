-- ============================================================
-- 数据质量规则集
-- 每条规则输出一行：规则分组 | 规则名 | 异常数 | 说明
--   异常数 = 0  → 校验通过
--   异常数 > 0  → 校验不通过，需要排查
-- 调度传参：--hiveconf dt=yyyy-MM-dd（数据日期）
-- 新增规则：在对应分层后面追加一段 union all 即可
-- ============================================================

set hive.cli.print.header = false;

-- ============ ODS 层：源数据入仓质量 ============
select 'ODS' as rule_group, '用户表-主键唯一' as rule_name,
       count(1) as err_cnt, 'user_id 重复条数' as memo
from (select user_id from ods.ods_user_info group by user_id having count(1) > 1) t

union all
select 'ODS', '用户表-手机号格式非法', count(1), '非 11 位手机号'
from ods.ods_user_info
where phone is not null and phone != '' and phone not rlike '^1[3-9][0-9]{9}$'

union all
select 'ODS', '用户表-必填字段为空', count(1), 'username/city/province 为空'
from ods.ods_user_info
where username = '' or city = '' or province = ''

union all
select 'ODS', '商品表-主键唯一', count(1), 'product_id 重复条数'
from (select product_id from ods.ods_product_info group by product_id having count(1) > 1) t

union all
select 'ODS', '订单表-当日分区为空', if(count(1) = 0, 1, 0), '当日无数据视为异常'
from ods.ods_order_info where dt = '${hiveconf:dt}'

union all
select 'ODS', '订单表-主键唯一', count(1), '当日 order_id 重复条数'
from (
    select order_id from ods.ods_order_info
    where dt = '${hiveconf:dt}'
    group by order_id having count(1) > 1
) t

union all
select 'ODS', '订单表-金额勾稽不平', count(1), '总额-优惠+运费 != 实付（容差0.01）'
from ods.ods_order_info
where dt = '${hiveconf:dt}'
  and abs(total_amount - discount_amount + freight_amount - pay_amount) > 0.01

union all
select 'ODS', '订单明细-金额勾稽不平', count(1), '单价*数量 != 明细总额（容差0.01）'
from ods.ods_order_detail
where dt = '${hiveconf:dt}'
  and abs(product_price * product_quantity - total_amount) > 0.01

-- ============ DWD 层：清洗结果质量 ============
union all
select 'DWD', '明细表-当日分区为空', if(count(1) = 0, 1, 0), '当日清洗结果为空视为异常'
from dwd.dwd_user_order_clean where dt = '${hiveconf:dt}'

union all
select 'DWD', '明细表-订单商品重复', count(1), '(order_id, product_name) 重复'
from (
    select order_id, product_name from dwd.dwd_user_order_clean
    where dt = '${hiveconf:dt}'
    group by order_id, product_name having count(1) > 1
) t

union all
select 'DWD', '明细表-应付金额为负', count(1), 'order_pay_amount < 0'
from dwd.dwd_user_order_clean
where dt = '${hiveconf:dt}' and order_pay_amount < 0

union all
select 'DWD', '明细表-必填字段为空', count(1), 'user_id 或 order_id 为空'
from dwd.dwd_user_order_clean
where dt = '${hiveconf:dt}' and (user_id is null or user_id = '' or order_id is null or order_id = '')

-- ============ DWS 层：汇总层质量 ============
union all
select 'DWS', '日快照-当日分区为空', if(count(1) = 0, 1, 0), '当日快照为空视为异常'
from dws.dws_user_day_snapshot where dt = '${hiveconf:dt}'

union all
select 'DWS', '日快照-用户重复', count(1), '同一用户当日多行'
from (
    select user_id from dws.dws_user_day_snapshot
    where dt = '${hiveconf:dt}'
    group by user_id having count(1) > 1
) t

union all
select 'DWS', '日快照-累计小于当日', count(1), '累计订单数不应小于当日订单数'
from dws.dws_user_day_snapshot
where dt = '${hiveconf:dt}' and total_order_count < day_order_count

-- ============ ADS 层：报表质量 ============
union all
select 'ADS', '报表-当日分区为空', if(count(1) = 0, 1, 0), '当日报表为空视为异常'
from ads.ads_user_daily_report where stat_date = '${hiveconf:dt}'

union all
select 'ADS', '报表-转化率为负', count(1), '转化率不应为负数'
from ads.ads_user_daily_report
where stat_date = '${hiveconf:dt}'
  and (order_conversion_rate < 0 or pay_conversion_rate < 0)

-- ============ 跨层一致性 ============
union all
select 'CROSS', 'DWD订单未在ODS中找到', count(1), 'dwd 有而 ods 没有的订单'
from (
    -- dwd 的 order_id 是 string、ods 是 bigint，统一转成 string 再比
    select distinct cast(order_id as string) as order_id
    from dwd.dwd_user_order_clean where dt = '${hiveconf:dt}'
    except
    select distinct cast(order_id as string) as order_id
    from ods.ods_order_info where dt = '${hiveconf:dt}'
) t

union all
select 'CROSS', 'ADS订单量与DWS宽表不一致', count(1), '两处统计口径应一致'
from (
    select order_count from ads.ads_user_daily_report where stat_date = '${hiveconf:dt}'
) a
join (
    select sum(is_current_order_ct) as cnt from dws.dws_user_topic_wide
) b
on a.order_count <> b.cnt;

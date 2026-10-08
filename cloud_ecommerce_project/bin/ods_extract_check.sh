#!/bin/bash
# ============================================================
# ODS 层抽数校验：逐表比对 Hive 与业务库 MySQL 的记录数
# 用法: ods_extract_check.sh [-d yyyy-MM-dd]
#   全量维表      比总行数
#   分区增量表    比 dt=<目标日期> 当天的行数
# 校验不通过返回码 1，可被调度器捕获
# ============================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../conf/env.sh"
LOG_FILE="${LOG_DIR}/ods_extract_check_${TODAY}.log"
RESULT_FILE="${LOG_DIR}/ods_check_result_${TODAY}.txt"

target_date=${YESTERDAY}
if [ $# -ge 2 ] && [ "$1" = "-d" ]; then
    target_date=$2
fi

if ! check_date "${target_date}"; then
    echo "日期非法: ${target_date}，应为真实存在的 yyyy-MM-dd"
    exit 1
fi

mysql_conn="-h${SRC_MYSQL_HOST} -P${SRC_MYSQL_PORT} -u${SRC_MYSQL_USER} -p${SRC_MYSQL_PWD}"

# 全量表（无分区维表）
full_tables="user_info brand_info product_info category_info"
# 增量表（dt 分区）
increment_tables="order_info order_detail payment_info"

total=0
failed=0

# 比对单张表：$1 表名  $2 hive 过滤条件  $3 mysql 过滤条件
check_one() {
    local table_name=$1
    local hive_where=$2
    local mysql_where=$3

    local hive_cnt mysql_cnt
    hive_cnt=$("${HIVE_BIN}" -S -e "select count(1) from ods.ods_${table_name} ${hive_where};" | tail -1 | tr -d '[:space:]')
    mysql_cnt=$(mysql ${mysql_conn} -N -e "select count(1) from ${SRC_MYSQL_DB}.${table_name} ${mysql_where};" | tr -d '[:space:]')

    total=$((total + 1))
    if [ "${hive_cnt}" = "${mysql_cnt}" ]; then
        printf "%-16s hive=%-10s mysql=%-10s PASS\n" "${table_name}" "${hive_cnt}" "${mysql_cnt}" | tee -a "${RESULT_FILE}"
        log "校验通过 ${table_name}: ${hive_cnt}"
    else
        failed=$((failed + 1))
        printf "%-16s hive=%-10s mysql=%-10s FAIL 差异=%s\n" "${table_name}" "${hive_cnt}" "${mysql_cnt}" "$((mysql_cnt - hive_cnt))" | tee -a "${RESULT_FILE}"
        log "校验不通过 ${table_name}: hive=${hive_cnt} mysql=${mysql_cnt}"
    fi
}

log "===== ODS 数据校验开始（增量表比对 dt=${target_date}） ====="
: > "${RESULT_FILE}"   # 每次运行重置结果文件

for t in ${full_tables}; do
    check_one "${t}" "" ""
done

for t in ${increment_tables}; do
    check_one "${t}" "where dt='${target_date}'" "where date(create_time)='${target_date}'"
done

log "===== 校验结束：共 ${total} 张，通过 $((total - failed)) 张，失败 ${failed} 张 ====="

if [ "${failed}" -gt 0 ]; then
    exit 1
fi

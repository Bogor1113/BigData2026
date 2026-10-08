#!/bin/bash
# ============================================================
# ADS 层：生成用户日统计报表并同步到报表库 MySQL
# 用法: ads_user_daily_report.sh [-d yyyy-MM-dd]
#   步骤1  Hive 计算 ads_user_daily_report 的 stat_date 分区
#   步骤2  DataX 把该分区数据写入 MySQL ads 库
# ============================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../conf/env.sh"
LOG_FILE="${LOG_DIR}/ads_user_daily_report_${TODAY}.log"

target_date=${YESTERDAY}
if [ $# -ge 2 ] && [ "$1" = "-d" ]; then
    target_date=$2
fi

if ! check_date "${target_date}"; then
    echo "日期非法: ${target_date}，应为真实存在的 yyyy-MM-dd"
    exit 1
fi

run "生成 ADS 报表 stat_date=${target_date}" \
    "${HIVE_BIN}" --hiveconf "dt=${target_date}" -f "${PROJECT_HOME}/ads/ads_user_daily_report.sql"

run "同步 ADS 报表到 MySQL" \
    "${PYTHON_BIN}" "${DATAX_BIN}" -p"-Dstat_date=${target_date}" \
    "${PROJECT_HOME}/ads/ads_user_daily_report_hdfs_to_mysql.json"

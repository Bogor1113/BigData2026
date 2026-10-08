#!/bin/bash
# ============================================================
# DWS 层用户日快照
# 用法: dws_user_day_snapshot.sh <incr|full> [-d yyyy-MM-dd]
#   incr  增量计算：前一天快照 + 当天 dwd 分区（日常调度用）
#   full  全量重刷：扫描 dt 及以前的所有分区（首次初始化 / 数据回补后用）
# ============================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../conf/env.sh"
LOG_FILE="${LOG_DIR}/dws_user_day_snapshot_${TODAY}.log"

if [ $# -lt 1 ]; then
    echo "用法: $0 <incr|full> [-d yyyy-MM-dd]"
    exit 1
fi

mode=$1
target_date=${YESTERDAY}
if [ $# -ge 3 ] && [ "$2" = "-d" ]; then
    target_date=$3
fi

if ! check_date "${target_date}"; then
    echo "日期非法: ${target_date}，应为真实存在的 yyyy-MM-dd"
    exit 1
fi

case "${mode}" in
    incr) sql_file="${PROJECT_HOME}/dws/dws_user_day_snapshot.sql" ;;
    full) sql_file="${PROJECT_HOME}/dws/dws_user_day_snapshot_full.sql" ;;
    *)
        echo "参数错误: ${mode}（可选 incr / full）"
        exit 1
        ;;
esac

run "用户日快照(${mode}) dt=${target_date}" \
    "${HIVE_BIN}" --hiveconf "dt=${target_date}" -f "${sql_file}"

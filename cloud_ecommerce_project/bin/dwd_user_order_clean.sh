#!/bin/bash
# ============================================================
# DWD 层清洗：按 ods_order_info 的分区清洗到 dwd_user_order_clean
# 用法: dwd_user_order_clean.sh <all|par> [-d yyyy-MM-dd]
#   all  清洗 ods_order_info 的全部已存在分区（首次初始化用）
#   par  只清洗指定分区（默认昨天，日常调度用）
# ============================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../conf/env.sh"
LOG_FILE="${LOG_DIR}/dwd_user_order_clean_${TODAY}.log"

if [ $# -lt 1 ]; then
    echo "用法: $0 <all|par> [-d yyyy-MM-dd]"
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

clean_one() {
    local dt_value=$1
    run "清洗 dwd_user_order_clean dt=${dt_value}" \
        "${HIVE_BIN}" --hiveconf "dt=${dt_value}" -f "${PROJECT_HOME}/dwd/dwd_user_order_clean.sql"
}

case "${mode}" in
    all)
        # show partitions 的输出形如 dt=2026-10-07
        partitions=$("${HIVE_BIN}" -S -e "show partitions ods.ods_order_info")
        for p in ${partitions}; do
            clean_one "${p#dt=}"
        done
        ;;
    par)
        clean_one "${target_date}"
        ;;
    *)
        echo "参数错误: ${mode}（可选 all / par）"
        exit 1
        ;;
esac

#!/bin/bash
# ============================================================
# DWS 层用户主题宽表（每用户一行，全量快照）
# 用法: dws_user_topic_wide.sh [-d yyyy-MM-dd]
#   默认按昨天跑，-d 指定跑批日期（影响"当日指标"口径）
# ============================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../conf/env.sh"
LOG_FILE="${LOG_DIR}/dws_user_topic_wide_${TODAY}.log"

target_date=${YESTERDAY}
if [ $# -ge 2 ] && [ "$1" = "-d" ]; then
    target_date=$2
fi

if ! check_date "${target_date}"; then
    echo "日期非法: ${target_date}，应为真实存在的 yyyy-MM-dd"
    exit 1
fi

run "用户主题宽表 dt=${target_date}" \
    "${HIVE_BIN}" --hiveconf "dt=${target_date}" -f "${PROJECT_HOME}/dws/dws_user_topic_wide.sql"

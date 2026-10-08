#!/bin/bash
# ============================================================
# 数据质量校验：执行规则集并生成质量报告
# 用法: dq_rule_check.sh [-d yyyy-MM-dd]
#   逐条规则统计异常数，异常数 > 0 判定为不通过
#   只要有任一条不通过，脚本返回 1，调度器可据此告警
# ============================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../conf/env.sh"

target_date=${YESTERDAY}
if [ $# -ge 2 ] && [ "$1" = "-d" ]; then
    target_date=$2
fi

if ! check_date "${target_date}"; then
    echo "日期非法: ${target_date}，应为真实存在的 yyyy-MM-dd"
    exit 1
fi

LOG_FILE="${LOG_DIR}/dq_rule_check_${TODAY}.log"
REPORT_FILE="${LOG_DIR}/dq_report_${target_date}.txt"

# ---------- 执行规则集 ----------
log "开始数据质量校验，数据日期 ${target_date}"
result=$("${HIVE_BIN}" -S --hiveconf "dt=${target_date}" -f "${PROJECT_HOME}/dq/dq_rule_check.sql" 2>>"${LOG_FILE}")

# ---------- 输出报告 ----------
{
    echo "======================== 数据质量报告 ========================"
    echo "数据日期: ${target_date}    生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "-------------------------------------------------------------"
} | tee "${REPORT_FILE}"

total=0
failed=0
failed_rules=""

while IFS=$'\t' read -r rule_group rule_name err_cnt memo; do
    # 跳过空行
    if [ -z "${rule_group}" ]; then
        continue
    fi

    total=$((total + 1))
    if [ "${err_cnt}" = "0" ]; then
        echo "[PASS] ${rule_group} | ${rule_name} | 异常 0" | tee -a "${REPORT_FILE}"
    else
        failed=$((failed + 1))
        failed_rules="${failed_rules}
    [${rule_group}] ${rule_name} 异常 ${err_cnt} 条 -- ${memo}"
        echo "[FAIL] ${rule_group} | ${rule_name} | 异常 ${err_cnt} | ${memo}" | tee -a "${REPORT_FILE}"
    fi
done <<< "${result}"

{
    echo "-------------------------------------------------------------"
    echo "合计 ${total} 条规则，通过 $((total - failed)) 条，失败 ${failed} 条"
} | tee -a "${REPORT_FILE}"

log "质量报告: ${REPORT_FILE}"

# 一条结果都没拿到，说明规则集执行异常，绝不能当作"通过"
if [ "${total}" -eq 0 ]; then
    log "未取得任何规则结果，校验判定为失败，请检查 dq_rule_check.sql 是否执行成功"
    exit 1
fi

if [ "${failed}" -gt 0 ]; then
    log "数据质量校验不通过，失败规则如下:${failed_rules}"
    exit 1
fi

log "数据质量校验全部通过"

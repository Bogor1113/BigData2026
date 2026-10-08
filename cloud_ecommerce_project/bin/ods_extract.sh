#!/bin/bash
# ============================================================
# ODS / DIM 层抽数脚本
# 用法: ods_extract.sh <表名> <all|first|increment> [-d yyyy-MM-dd]
#   表目录：ODS 表在 ods/ 下，维表（code_value）在 dim/ 下，脚本自动识别
#   all        全量抽取（无分区维表：user_info/brand_info/product_info/category_info/code_value）
#   first      首次抽取（分区表：从业务库最小日期补到昨天）
#   increment  T+1 增量（分区表：默认抽昨天，-d 可指定补数日期）
# ============================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/../conf/env.sh"
LOG_FILE="${LOG_DIR}/ods_extract_${TODAY}.log"

# ---------- 参数校验 ----------
if [ $# -lt 2 ]; then
    echo "用法: $0 <表名> <all|first|increment> [-d yyyy-MM-dd]"
    exit 1
fi

table_name=$1
extract_type=$2
target_date=${YESTERDAY}

if [ $# -ge 3 ]; then
    if [ "$3" = "-d" ] && [ $# -eq 4 ]; then
        target_date=$4
    else
        echo "用法: $0 <表名> <all|first|increment> [-d yyyy-MM-dd]"
        exit 1
    fi
fi

# 日期必须合法，否则会拼出错误的 HDFS 路径和分区
if ! check_date "${target_date}"; then
    echo "日期非法: ${target_date}，应为真实存在的 yyyy-MM-dd"
    exit 1
fi

# ---------- 路径 ----------
# ODS 表在 ods/ 下，维表（如 code_value）在 dim/ 下
if [ -d "${PROJECT_HOME}/ods/${table_name}" ]; then
    table_dir="${PROJECT_HOME}/ods/${table_name}"
    db_name="ods"
    table_full_name="ods_${table_name}"
    hdfs_table_path="${HDFS_WAREHOUSE}/ods.db/ods_${table_name}"
elif [ -d "${PROJECT_HOME}/dim/${table_name}" ]; then
    table_dir="${PROJECT_HOME}/dim/${table_name}"
    db_name="dim"
    table_full_name="dim_${table_name}"
    hdfs_table_path="${HDFS_WAREHOUSE}/dim.db/dim_${table_name}"
else
    echo "找不到表目录: ${table_name}（应在 ods/ 或 dim/ 下）"
    exit 1
fi
mysql_conn="-h${SRC_MYSQL_HOST} -P${SRC_MYSQL_PORT} -u${SRC_MYSQL_USER} -p${SRC_MYSQL_PWD}"

# 前置检查：脚本和 DataX 配置必须存在，避免跑一半才报错
for f in "${table_dir}/${table_name}.sql" "${table_dir}/${table_name}.json"; do
    if [ ! -f "${f}" ]; then
        echo "文件不存在: ${f}"
        exit 1
    fi
done

# ---------- 全量抽取（无分区维表） ----------
all() {
    log "== 全量抽取 ${table_name} =="
    run "建表 ${db_name}.${table_full_name}" "${HIVE_BIN}" -f "${table_dir}/${table_name}.sql"
    run "DataX 全量抽取 ${table_name}" "${PYTHON_BIN}" "${DATAX_BIN}" "${table_dir}/${table_name}.json"
    log "== 全量抽取 ${table_name} 完成 =="
}

# ---------- 首次抽取（分区表，按天补齐历史） ----------
first() {
    log "== 首次抽取 ${table_name} =="
    run "建表 ${db_name}.${table_full_name}" "${HIVE_BIN}" -f "${table_dir}/${table_name}.sql"

    # 取业务表最小日期作为补数起点
    mindt=$(mysql ${mysql_conn} -N -e "select date(min(create_time)) from ${SRC_MYSQL_DB}.${table_name};" | tr -d '[:space:]')
    if [ -z "${mindt}" ] || [ "${mindt}" = "NULL" ]; then
        log "取不到业务表 ${table_name} 的最小日期，退出"
        exit 1
    fi
    log "业务表最早日期: ${mindt}"

    while [ "${mindt}" != "${TODAY}" ]; do
        run "创建分区目录 dt=${mindt}" "${HADOOP_BIN}" fs -mkdir -p "${hdfs_table_path}/dt=${mindt}"
        run "DataX 抽取 dt=${mindt}" "${PYTHON_BIN}" "${DATAX_BIN}" -p"-Ddt=${mindt}" "${table_dir}/${table_name}.json"
        mindt=$(date -d "${mindt} 1 day" '+%Y-%m-%d')
    done

    run "修复分区 ${db_name}.${table_full_name}" "${HIVE_BIN}" -e "msck repair table ${db_name}.${table_full_name}"
    log "== 首次抽取 ${table_name} 完成 =="
}

# ---------- T+1 增量抽取（分区表） ----------
increment() {
    log "== 增量抽取 ${table_name} dt=${target_date} =="
    # 先删掉目标分区，保证重跑幂等
    run "删除旧分区 dt=${target_date}" "${HIVE_BIN}" -e \
        "set hive.exec.drop.ignorenonexistent=true; alter table ${db_name}.${table_full_name} drop partition (dt='${target_date}');"
    run "创建分区目录 dt=${target_date}" "${HADOOP_BIN}" fs -mkdir -p "${hdfs_table_path}/dt=${target_date}"
    run "DataX 抽取 dt=${target_date}" "${PYTHON_BIN}" "${DATAX_BIN}" -p"-Ddt=${target_date}" "${table_dir}/${table_name}.json"
    run "修复分区 ${db_name}.${table_full_name}" "${HIVE_BIN}" -e "msck repair table ${db_name}.${table_full_name}"
    log "== 增量抽取 ${table_name} dt=${target_date} 完成 =="
}

case "${extract_type}" in
    all)       all ;;
    first)     first ;;
    increment) increment ;;
    *)
        echo "抽取方式错误: ${extract_type}（可选 all / first / increment）"
        exit 1
        ;;
esac

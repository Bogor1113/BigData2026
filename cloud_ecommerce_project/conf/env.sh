#!/bin/bash
# ============================================================
# 云策电商数仓 - 公共配置
# 所有脚本开头 source 本文件，配置只写一份
# 用法：source "$(cd "$(dirname "$0")/.." && pwd)/conf/env.sh"
# ============================================================

# ---------- 路径 ----------
PROJECT_HOME='/home/cloud_ecommerce_project'
LOG_DIR="${PROJECT_HOME}/logs"
HDFS_WAREHOUSE='/hive3/warehouse'

# ---------- 日期 ----------
TODAY=$(date '+%Y-%m-%d')
YESTERDAY=$(date -d '1 days ago' '+%Y-%m-%d')

# ---------- 命令 ----------
HIVE_BIN='hive'
HADOOP_BIN='hadoop'
DATAX_BIN='/opt/datax/bin/datax.py'
PYTHON_BIN='python3'

# ---------- 业务库 MySQL（数据来源） ----------
SRC_MYSQL_HOST='192.168.110.131'
SRC_MYSQL_PORT='3306'
SRC_MYSQL_USER='bigdata'
SRC_MYSQL_PWD='bigdata'
SRC_MYSQL_DB='cloud_ecommerce'

# ---------- 报表库 MySQL（数据出口） ----------
ADS_MYSQL_HOST='192.168.42.101'
ADS_MYSQL_PORT='3306'
ADS_MYSQL_USER='root'
ADS_MYSQL_PWD='123456'
ADS_MYSQL_DB='ads'

# ---------- 公共函数 ----------
# 日志文件：调用脚本可覆盖，默认按天一份
LOG_FILE="${LOG_DIR}/dw_${TODAY}.log"

# 打日志：同时输出到屏幕和日志文件
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# 校验日期：格式必须是 yyyy-MM-dd，且必须是真实存在的日期
# $1 日期   返回值 0=合法 1=非法
check_date() {
    local d="$1"
    echo "${d}" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || return 1
    [ "$(date -d "${d}" '+%Y-%m-%d' 2>/dev/null)" = "${d}" ] || return 1
    return 0
}

# 执行命令：失败立即结束任务（ETL 不允许静默失败），并把退出码透传给调度器
run() {
    local desc="$1"; shift
    log "start | ${desc}"
    local rc=0
    "$@" >> "${LOG_FILE}" 2>&1 || rc=$?
    if [ "${rc}" -eq 0 ]; then
        log "done  | ${desc}"
    else
        log "FAIL  | ${desc} 退出码=${rc}，详见 ${LOG_FILE}"
        exit "${rc}"
    fi
}

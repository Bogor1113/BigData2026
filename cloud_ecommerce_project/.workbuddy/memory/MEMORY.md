# 云策电商数仓 · 项目长期约定

## 目录结构
```
bin/      全部调度脚本（7 个，不含 SQL）
conf/     env.sh —— 公共配置 + log/run/check_date 函数
dq/       数据质量规则 SQL
ods/<表名>/   每张 ODS 表一个目录，内含 <表名>.sql + <表名>.json(DataX 配置)
dim/<表名>/   维表（code_value）同 ods 结构
dwd/ dws/ ads/   各层 SQL（+ ads 的 DataX json）
archive/  草稿与历史产物（按原分层存放）
logs/     日志与报告
```

## 命名规范
> **脚本名 = 它调度的 SQL 文件名（`.sql` → `.sh`）；跨表通用脚本用 `层_动作.sh`。**

- 层前缀统一：`ods_` / `dwd_` / `dws_` / `ads_` / `dq_`
- 全部下划线分词，不用连写（`check_data` 而非 `checkdata`）、不用复数（`extract` 而非 `scripts`）
- 日志/报告文件：`<脚本名>_<日期>.log`，报告 `<用途>_<日期>.txt`

## 调度约定
所有脚本第一个参数或 `-d` 传 **数据日期（业务日期）**，正常调度为昨天。
禁止在 SQL 里用 `current_date` —— 会导致补跑结果不可复现。

## 脚本模板（统一结构）
1. `set -euo pipefail`
2. `SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)` + `source "${SCRIPT_DIR}/../conf/env.sh"`
3. 设 `LOG_FILE` → 参数解析（含 `check_date` 校验）→ 主逻辑 `run "描述" 命令`
4. 失败由 `run()` 记录并透传退出码

## 分层口径
- ODS 分区表（order_info / order_detail / payment_info）：分区 `dt` = 订单创建日期
- ODS 全量维表（user_info / brand_info / product_info / category_info）：无分区
- dim：code_value（字典表）
- DWD `dwd_user_order_clean`：一条订单商品一行，分区 dt
- DWS `dws_user_day_snapshot`：按用户+日的增量快照，累计 = 前日快照 + 当日增量
- DWS `dws_user_topic_wide`：每用户一行全量快照，无分区
- ADS `ads_user_daily_report`：按 `stat_date` 分区，`insert overwrite` 幂等

## 依赖关系（执行顺序）
`ods_extract`（先 all 后 increment）→ `ods_extract_check` → `dwd_user_order_clean` →
`dws_user_day_snapshot` → `dws_user_topic_wide` → `ads_user_daily_report` → `dq_rule_check`

## 术语规范
- 日环比用 `dod`（Day over Day），**不要写 `wow`**（那是周环比）
- 金额字段一律 `amount`，注意不是 `amout`

## 待办（未做）
- DolphinScheduler 工作流定义（当前无调度层）
- 凭据脱敏：MySQL 密码仍明文在 `conf/env.sh` 与 DataX json
- 环境隔离（dev/test/prod）
- 实时链路（项目名含"实时"，目前为空）

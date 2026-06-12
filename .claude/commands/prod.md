# 线上 — 正式环境操作

在生产服务器（eshop.evexport.cn）上执行 Rails 命令或查询数据库。

**服务器信息**
- Host: `eshop.evexport.cn`
- SSH 用户: `root`
- 运行方式: kamal 容器（`bin/kamal app exec`）
- 应用容器名: `eshop_manage-web`

## 用法

`/线上 <自然语言描述或 Ruby 代码>`

## 执行方式

根据 $ARGUMENTS 判断意图，生成并通过 Bash 工具执行以下命令：

```bash
cd /Users/jiyarong/Developer/5/eshop && bin/kamal app exec --reuse "bin/rails runner '<ruby代码>'"
```

多行/复杂代码改用 heredoc 方式：

```bash
cd /Users/jiyarong/Developer/5/eshop && bin/kamal app exec --reuse "bin/rails runner \"$(cat <<'RUBY'
<多行ruby代码>
RUBY
)\""
```

> **注意**：kamal exec 通过本地 `bin/kamal` 转发到容器内执行，不需要手动 SSH。`--reuse` 复用已运行的 web 容器，避免启动额外容器。

## 规则

1. **自然语言 → Ruby**：若 $ARGUMENTS 是自然语言描述（如"查一下本周的汇率记录"），先将其转换为对应的 Ruby/ActiveRecord 代码再执行。
2. **只读优先**：默认用 `.pluck` / `.count` / `puts` 输出结果，不做写操作，除非明确要求。
3. **写操作确认**：涉及 `create!` / `update!` / `delete_all` / `destroy` 等写操作，执行前先向用户展示将要运行的代码并确认。
4. **多行代码**：复杂逻辑用 heredoc 传入，保持可读性。
5. **输出格式**：结果直接 `puts` 打印，复杂结构用 `pp`。

## 示例

`/线上 查一下 ec_weekly_rates 表里有哪些记录`
→ 执行：`bin/kamal app exec --reuse "bin/rails runner 'puts Ec::WeeklyRate.order(:week_start).pluck(:week_start, :rate_cny_rub, :rate_byn_rub).map { |r| r.join(\" | \") }'"`

`/线上 插入一条 2026-05-11 的汇率，CNY/RUB=11.25，BYN/RUB=26.30`
→ 展示代码，确认后执行：`Ec::WeeklyRate.find_or_create_by!(week_start: '2026-05-11') { |r| r.rate_cny_rub = 11.25; r.rate_byn_rub = 26.30 }`

`/线上 跑一下周报`
→ 执行：`bin/kamal app exec --reuse "bin/rails runner 'GoogleSheets::WeeklyProfitReportRunner.run'"`

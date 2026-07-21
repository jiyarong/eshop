#!/usr/bin/env python3
"""
校验 WB FBS 已完成订单（xlsx）与 DB raw_wb_orders（supplier_status='complete'）的订单数是否一致。

文件夹内直接放 xlsx，文件名末尾数字为月份，如 WB-FBS-МИРОВОЙ-26-3.xlsx → 2026-03。

用法：
    python3 script/verify_wb_fbs_completed.py <报告文件夹路径> <店铺account_id> <年份>

示例：
    python3 script/verify_wb_fbs_completed.py ~/Downloads/WB-FBS-МИРОВОЙ-26-345 3 2026
"""

import openpyxl
import re
import sys
import json
import subprocess
from pathlib import Path

CONTAINER_CMD = "docker ps --format '{{.Names}}' | grep eshop_manage-web | head -1"

def parse_month(filename, year):
    """从文件名末尾取月份数字，如 ...-3.xlsx → '2026-03'"""
    m = re.search(r'-(\d{1,2})\.xlsx$', filename)
    if not m:
        return None
    return f"{year}-{int(m.group(1)):02d}"

def read_order_ids(xlsx_path):
    ws = openpyxl.load_workbook(xlsx_path).active
    rows = list(ws.iter_rows(values_only=True))
    if len(rows) <= 1:
        return []
    return [int(r[0]) for r in rows[1:] if r[0] is not None]

def load_xlsx_data(folder, year):
    folder = Path(folder).expanduser()
    monthly = {}
    for f in sorted(folder.glob("*.xlsx")):
        month = parse_month(f.name, year)
        if not month:
            print(f"  ⚠️  无法解析月份：{f.name}", file=sys.stderr)
            continue
        ids = read_order_ids(f)
        monthly[month] = ids
        print(f"  {month}：xlsx 读取 {len(ids)} 条已完成订单（{f.name}）")
    return monthly

RAILS_TEMPLATE = r"""
$stdout.sync = true
Rails.logger = Logger.new(IO::NULL)

ACCOUNT_ID = ACCOUNT_ID_PLACEHOLDER
monthly    = MONTHLY_JSON_PLACEHOLDER

sep = "=" * 60
puts "\n" + sep
puts "  校验：raw_wb_orders（不过滤状态）  account_id=#{ACCOUNT_ID}"
puts sep

all_xlsx_ids = []
all_db_ids   = []

monthly.each do |month, xlsx_ids|
  year, mon = month.to_s.split("-").map(&:to_i)
  from = Time.utc(year, mon, 1)
  to   = from.end_of_month

  db_ids = RawWb::Order
    .where(account_id: ACCOUNT_ID)
    .where(created_at: from..to)
    .pluck(:wb_order_id)
    .map(&:to_i)

  all_xlsx_ids += xlsx_ids
  all_db_ids   += db_ids

  only_xlsx = xlsx_ids - db_ids
  only_db   = db_ids   - xlsx_ids
  status    = (only_xlsx.empty? && only_db.empty?) ? "OK" : "NG"

  puts "\n  [#{status}] #{month}"
  puts "    xlsx 已完成: #{xlsx_ids.size}  |  DB: #{db_ids.size}"
  puts "    仅在 xlsx（DB 缺失）: #{only_xlsx.size}  #{only_xlsx.first(5).inspect}"
  puts "    仅在 DB（xlsx 无）:   #{only_db.size}  #{only_db.first(5).inspect}"
end

all_xlsx_ids = all_xlsx_ids.uniq
all_db_ids   = all_db_ids.uniq
only_xlsx    = all_xlsx_ids - all_db_ids
only_db      = all_db_ids   - all_xlsx_ids
status       = (only_xlsx.empty? && only_db.empty?) ? "OK" : "NG"

puts "\n" + "─" * 60
puts "  [#{status}] 合计（3个月去重）"
puts "    xlsx 总计: #{all_xlsx_ids.size}  |  DB 总计: #{all_db_ids.size}"
puts "    仅在 xlsx（DB 缺失）: #{only_xlsx.size}  #{only_xlsx.inspect}"
puts "    仅在 DB（xlsx 无）:   #{only_db.size}  #{only_db.inspect}"
"""

def get_container():
    r = subprocess.run(["ssh", "root@eshop.evexport.cn", CONTAINER_CMD],
                       capture_output=True, text=True)
    return r.stdout.strip()

def run_on_server(rails_script):
    container = get_container()
    if not container:
        print("❌ 无法获取容器名", file=sys.stderr)
        sys.exit(1)
    print(f"\n容器：{container}")

    local_path = "/tmp/verify_wb_fbs_completed.rb"
    with open(local_path, "w") as f:
        f.write(rails_script)

    subprocess.run(["scp", local_path, f"root@eshop.evexport.cn:{local_path}"], check=True)
    subprocess.run(["ssh", "root@eshop.evexport.cn",
                    f"docker cp {local_path} {container}:{local_path}"], check=True)
    subprocess.run(["ssh", "root@eshop.evexport.cn",
                    f"docker exec {container} bin/rails runner {local_path}"], check=True)

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    folder, account_id, year = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])

    print(f"\n读取 xlsx 文件：{folder}")
    monthly = load_xlsx_data(folder, year)

    script = RAILS_TEMPLATE
    script = script.replace("ACCOUNT_ID_PLACEHOLDER", str(account_id))
    script = script.replace("MONTHLY_JSON_PLACEHOLDER", json.dumps(monthly))

    run_on_server(script)

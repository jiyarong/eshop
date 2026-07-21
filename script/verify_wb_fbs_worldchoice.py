#!/usr/bin/env python3
"""
校验 WB FBS 归档报告与 DB raw_wb_orders 的订单数是否一致。

用法：
    python3 script/verify_wb_fbs_worldchoice.py <报告文件夹路径> [account_id]

示例：
    python3 script/verify_wb_fbs_worldchoice.py ~/Downloads/WB-FBS-МИРОВОЙ-2025 3
    python3 script/verify_wb_fbs_worldchoice.py ~/Downloads/WB-FBS-Такси-2025 2
"""

import zipfile
import openpyxl
import re
import sys
import json
import subprocess
import tempfile
import os
from pathlib import Path
from collections import defaultdict

ACCOUNT_ID = 3  # OOO «МИРОВОЙ ВЫБОР»
CONTAINER_CMD = (
    "docker ps --format '{{.Names}}' | grep eshop_manage-web | head -1"
)

# ─── 1. 读取所有 zip，提取 wb_order_id 按月分组 ────────────────────────────

def parse_month(zip_name):
    """从文件名提取 'YYYY-MM'，如 '报告 01.03.2025-...' → '2025-03'"""
    m = re.search(r'(\d{2})\.(\d{2})\.(\d{4})', zip_name)
    if not m:
        return None
    day, month, year = m.group(1), m.group(2), m.group(3)
    return f"{year}-{month}"

def read_order_ids(zip_path):
    """从 zip 内的 report_part_0.xlsx 读取所有 工作編號（wb_order_id）"""
    with zipfile.ZipFile(zip_path) as z:
        with z.open("report_part_0.xlsx") as f:
            wb = openpyxl.load_workbook(f)
            ws = wb.active
            rows = list(ws.iter_rows(values_only=True))
    if len(rows) <= 1:
        return []
    # 工作編號 = 第1列（index 0）
    return [int(r[0]) for r in rows[1:] if r[0] is not None]

def load_xlsx_data(folder):
    folder = Path(folder).expanduser()
    monthly = {}  # { 'YYYY-MM': [order_id, ...] }
    for zf in sorted(folder.glob("*.zip")):
        month = parse_month(zf.name)
        if not month:
            print(f"  ⚠️  无法解析月份：{zf.name}", file=sys.stderr)
            continue
        ids = read_order_ids(zf)
        monthly[month] = ids
        print(f"  {month}：xlsx 读取 {len(ids)} 条订单（来自 {zf.name}）")
    return monthly

# ─── 2. 生成 Rails runner 脚本，在服务器上按月查 DB ────────────────────────

RAILS_TEMPLATE = r"""
$stdout.sync = true
Rails.logger = Logger.new(IO::NULL)

ACCOUNT_ID = ACCOUNT_ID_PLACEHOLDER
monthly = JSON.parse('MONTHLY_JSON_PLACEHOLDER')

sep = "=" * 60
puts "\n" + sep
puts "  DB 查询：raw_wb_orders  account_id=#{ACCOUNT_ID} (МИРОВОЙ ВЫБОР)"
puts sep

monthly.each do |month, xlsx_ids|
  next if xlsx_ids.empty?

  db_ids = RawWb::Order
    .where(account_id: ACCOUNT_ID, wb_order_id: xlsx_ids)
    .pluck(:wb_order_id)
    .map(&:to_i)

  only_xlsx = xlsx_ids - db_ids
  only_db   = db_ids   - xlsx_ids

  status = (only_xlsx.empty? && only_db.empty?) ? "OK" : "NG"
  puts "\n  [#{status}] #{month}"
  puts "    xlsx 订单数: #{xlsx_ids.size}  |  DB 命中: #{db_ids.size}"
  puts "    仅在 xlsx（DB 缺失）: #{only_xlsx.size}  #{only_xlsx.first(5).inspect}"
  puts "    仅在 DB（xlsx 无）:   #{only_db.size}"
end

puts "\n" + sep
puts "  DB 查询：ec_orders  platform=wb  store=WorldChoice  fbs"
puts sep

store = Ec::Store.find_by(platform: 'wb', wb_raw_account_id: ACCOUNT_ID)
if store.nil?
  puts "  ❌ 找不到 Ec::Store（platform=wb, wb_raw_account_id=#{ACCOUNT_ID}）"
else
  puts "  Store: #{store.store_name} (id=#{store.id})"

  ec_monthly = Ec::Order
    .joins(:fulfillments)
    .where(platform: 'wb', store_id: store.id)
    .where(ec_order_fulfillments: { fulfillment_type: 'fbs' })
    .where.not(ordered_at: nil)
    .group("TO_CHAR(ec_orders.ordered_at, 'YYYY-MM')")
    .count

  all_months = (monthly.keys + ec_monthly.keys).uniq.sort
  puts ""
  puts "  #{"月份".ljust(10)} #{"xlsx".rjust(6)}  #{"ec_orders".rjust(10)}"
  puts "  " + "-" * 30
  all_months.each do |m|
    xlsx_ct = monthly[m]&.size || 0
    ec_ct   = ec_monthly[m] || 0
    flag    = xlsx_ct > 0 && (ec_ct - xlsx_ct).abs > xlsx_ct * 0.05 ? " ⚠️" : ""
    puts "  #{m.ljust(10)} #{xlsx_ct.to_s.rjust(6)}  #{ec_ct.to_s.rjust(10)}#{flag}"
  end
  puts "  " + "-" * 30
  total_xlsx = monthly.values.sum(&:size)
  total_ec   = ec_monthly.values.sum
  puts "  #{"合计".ljust(10)} #{total_xlsx.to_s.rjust(6)}  #{total_ec.to_s.rjust(10)}"
end
"""

def build_rails_script(monthly, account_id):
    monthly_json = json.dumps(monthly)
    script = RAILS_TEMPLATE
    script = script.replace("ACCOUNT_ID_PLACEHOLDER", str(account_id))
    script = script.replace("MONTHLY_JSON_PLACEHOLDER", monthly_json)
    return script

# ─── 3. 上传并在服务器执行 ─────────────────────────────────────────────────

def get_container():
    result = subprocess.run(
        ["ssh", "root@eshop.evexport.cn", CONTAINER_CMD],
        capture_output=True, text=True
    )
    return result.stdout.strip()

def run_on_server(rails_script):
    container = get_container()
    if not container:
        print("❌ 无法获取容器名", file=sys.stderr)
        sys.exit(1)
    print(f"\n容器：{container}")

    local_path  = "/tmp/verify_wb_fbs.rb"
    remote_path = "/tmp/verify_wb_fbs.rb"

    with open(local_path, "w") as f:
        f.write(rails_script)

    subprocess.run(["scp", local_path, f"root@eshop.evexport.cn:{remote_path}"], check=True)
    subprocess.run(["ssh", "root@eshop.evexport.cn",
                    f"docker cp {remote_path} {container}:{remote_path}"], check=True)
    subprocess.run(["ssh", "root@eshop.evexport.cn",
                    f"docker exec {container} bin/rails runner {remote_path}"], check=True)

# ─── main ─────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    folder = sys.argv[1]
    account_id = int(sys.argv[2]) if len(sys.argv) >= 3 else ACCOUNT_ID
    print(f"\n读取 xlsx 文件：{folder}  account_id={account_id}")
    monthly = load_xlsx_data(folder)

    rails_script = build_rails_script(monthly, account_id)
    run_on_server(rails_script)

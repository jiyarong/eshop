# 用法: bin/rails runner script/import_sku_operator_assignments_from_xlsx.rb <xlsx路径> [--operators=宋慧莹,宋韩] [--apply]
# 直接读取产品分配表(表头需含 Operator、SKU 两列),把指定运营人员对应的 SKU 写入 ec_sku_operator_assignments。
# 默认运营人员为「宋慧莹」「宋韩」。默认 dry-run,加 --apply 才写库;可重复执行。
require "zip"
require "nokogiri"

path = ARGV.find { |a| !a.start_with?("--") } or abort("缺少 xlsx 路径")
abort("文件不存在: #{path}") unless File.file?(path)
apply = ARGV.include?("--apply")
operators_arg = ARGV.find { |a| a.start_with?("--operators=") }
operator_names = operators_arg ? operators_arg.dup.force_encoding("UTF-8").delete_prefix("--operators=").split(",").map(&:strip).reject(&:blank?) : %w[宋慧莹 宋韩]

def parse_xml(content) = Nokogiri::XML(content).tap(&:remove_namespaces!)

# 读取第一个工作表,返回 [{ "Operator" => ..., "SKU" => ... }, ...]
def read_sheet_rows(path)
  Zip::File.open(path) do |zip|
    shared = if (entry = zip.find_entry("xl/sharedStrings.xml"))
      parse_xml(entry.get_input_stream.read).xpath("//si").map { |si| si.xpath(".//t").map(&:text).join }
    else
      []
    end

    workbook = parse_xml(zip.read("xl/workbook.xml"))
    rels = parse_xml(zip.read("xl/_rels/workbook.xml.rels"))
    first_sheet = workbook.xpath("//sheets/sheet").first or abort("xlsx 中没有工作表")
    rel_id = first_sheet["id"] || first_sheet["r:id"]
    target = rels.xpath("//Relationship").find { |r| r["Id"] == rel_id }["Target"]
    sheet = parse_xml(zip.read("xl/#{target.sub(%r{\A/}, '').sub(%r{\Axl/}, '')}"))

    grid = sheet.xpath("//sheetData/row").map do |row|
      row.xpath("./c").each_with_object({}) do |cell, h|
        col = cell["r"][/[A-Z]+/]
        h[col] = if cell["t"] == "s"
          shared[cell.at_xpath("./v").text.to_i]
        elsif cell["t"] == "inlineStr"
          cell.xpath(".//t").map(&:text).join
        else
          cell.at_xpath("./v")&.text
        end.to_s.strip
      end
    end

    header = grid.shift or abort("工作表为空")
    cols = header.invert
    op_col = cols["Operator"] or abort("找不到 Operator 列")
    sku_col = cols["SKU"] or abort("找不到 SKU 列")
    grid.map { |h| { "operator" => h[op_col].to_s, "sku" => h[sku_col].to_s } }
  end
end

users = User.where(name: operator_names).index_by(&:name)
missing_users = operator_names - users.keys
abort("找不到用户: #{missing_users.join(', ')}") if missing_users.any?

pairs = read_sheet_rows(path).filter_map do |row|
  [row["sku"], row["operator"]] if operator_names.include?(row["operator"]) && row["sku"].present?
end
dups = pairs.group_by(&:first).select { |_, v| v.map(&:last).uniq.size > 1 }
abort("SKU 对应多个运营: #{dups.keys.join(', ')}") if dups.any?
pairs = pairs.uniq

existing_skus = Ec::Sku.where(sku_code: pairs.map(&:first)).pluck(:sku_code).to_set
not_found = pairs.map(&:first).reject { |s| existing_skus.include?(s) }
current = Ec::SkuOperatorAssignment.where(sku_code: pairs.map(&:first)).index_by(&:sku_code)

created = updated = unchanged = 0
Ec::SkuOperatorAssignment.transaction do
  pairs.each do |sku_code, name|
    next unless existing_skus.include?(sku_code)
    user = users[name]
    rec = current[sku_code]
    if rec.nil?
      created += 1
      Ec::SkuOperatorAssignment.create!(sku_code: sku_code, user: user) if apply
    elsif rec.user_id != user.id
      updated += 1
      puts "变更 #{sku_code}: user #{rec.user_id} -> #{user.id}(#{name})"
      rec.update!(user: user) if apply
    else
      unchanged += 1
    end
  end
end

puts "#{apply ? '已写入' : 'DRY-RUN'}: 运营 #{operator_names.join('/')}, 表内 #{pairs.size} 个 SKU, 新增 #{created}, 变更 #{updated}, 无变化 #{unchanged}"
puts "系统中不存在的 SKU (#{not_found.size}): #{not_found.join(', ')}" if not_found.any?

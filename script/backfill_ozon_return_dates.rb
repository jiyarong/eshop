total = RawOzon::Return.count
updated = 0
failed  = 0

RawOzon::Return.find_each(batch_size: 500) do |r|
  logistic = r.raw_json['logistic'] || {}
  visual   = r.raw_json['visual']   || {}

  return_date         = logistic['return_date'].presence&.then { Time.parse(_1) rescue nil }
  final_moment        = logistic['final_moment'].presence&.then { Time.parse(_1) rescue nil }
  visual_change_moment = visual['change_moment'].presence&.then { Time.parse(_1) rescue nil }

  r.update_columns(
    return_date:          return_date,
    final_moment:         final_moment,
    visual_change_moment: visual_change_moment
  )
  updated += 1
rescue => e
  failed += 1
  puts "id=#{r.id} error: #{e.message}"
end

puts "完成: 总计 #{total} 条，更新 #{updated} 条，失败 #{failed} 条"

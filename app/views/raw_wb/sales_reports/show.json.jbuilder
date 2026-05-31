json.success true
json.data do
  json.sales_report do
      json.id @sales_report.id
      json.wb_report_id @sales_report.wb_report_id
      json.date_from @sales_report.date_from
      json.date_to @sales_report.date_to
      json.report_created_at @sales_report.report_created_at
      json.total_sales @sales_report.total_sales
      json.total_returns @sales_report.total_returns
      json.total_commission @sales_report.total_commission
      json.total_delivery @sales_report.total_delivery
      json.total_penalty @sales_report.total_penalty
      json.net_payable @sales_report.net_payable
      json.synced_at @sales_report.synced_at
  end
end
json.message @message || 'ok'

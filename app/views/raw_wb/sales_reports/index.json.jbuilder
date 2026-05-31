json.success true
json.data do
  json.sales_reports do
    json.array! @sales_reports do |sales_report|
      json.id sales_report.id
      json.wb_report_id sales_report.wb_report_id
      json.date_from sales_report.date_from
      json.date_to sales_report.date_to
      json.net_payable sales_report.net_payable
      json.synced_at sales_report.synced_at
    end
  end
  json.meta do
    json.current_page @sales_reports.current_page
    json.total_pages @sales_reports.total_pages
    json.total_count @sales_reports.total_count
  end
end
json.message @message || 'ok'
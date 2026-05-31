json.success true
json.data do
  json.ad_campaigns do
    json.array! @ad_campaigns do |ad_campaign|
      json.id ad_campaign.id
      json.wb_advert_id ad_campaign.wb_advert_id
      json.name ad_campaign.name
      json.campaign_type ad_campaign.campaign_type
      json.status ad_campaign.status
      json.daily_budget ad_campaign.daily_budget
      json.start_time ad_campaign.start_time
      json.end_time ad_campaign.end_time
    end
  end
  json.meta do
    json.current_page @ad_campaigns.current_page
    json.total_pages @ad_campaigns.total_pages
    json.total_count @ad_campaigns.total_count
  end
end
json.message @message || 'ok'
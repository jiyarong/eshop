json.success true
json.data do
  json.ad_campaign do
      json.id @ad_campaign.id
      json.wb_advert_id @ad_campaign.wb_advert_id
      json.name @ad_campaign.name
      json.campaign_type @ad_campaign.campaign_type
      json.status @ad_campaign.status
      json.daily_budget @ad_campaign.daily_budget
      json.total_budget @ad_campaign.total_budget
      json.start_time @ad_campaign.start_time
      json.end_time @ad_campaign.end_time
      json.created_at @ad_campaign.created_at
      json.updated_at @ad_campaign.updated_at
      json.synced_at @ad_campaign.synced_at
  end
end
json.message @message || 'ok'

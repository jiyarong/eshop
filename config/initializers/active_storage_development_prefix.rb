module ActiveStorageDevelopmentPrefix
  private

  def prefix_development_qiniu_key
    return unless Rails.env.development? && service_name == "qiniu"
    return if key.start_with?("development/")

    self.key = "development/#{key}"
  end
end

Rails.application.config.to_prepare do
  ActiveStorage::Blob.include(ActiveStorageDevelopmentPrefix) unless
    ActiveStorage::Blob < ActiveStorageDevelopmentPrefix
  ActiveStorage::Blob.before_create :prefix_development_qiniu_key
end

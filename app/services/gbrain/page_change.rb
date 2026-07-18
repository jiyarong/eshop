module Gbrain
  class PageChange
    def self.save(page, attributes)
      new(page).save(attributes)
    end

    def self.request_deletion(page)
      page.update!(
        delete_requested_at: Time.current,
        sync_status: "pending_delete",
        last_error: nil
      )
      PageSyncJob.perform_later(page.id)
    end

    def self.retry(page)
      page.update!(
        sync_status: page.pending_deletion? ? "pending_delete" : "pending",
        last_error: nil
      )
      PageSyncJob.perform_later(page.id)
    end

    def initialize(page)
      @page = page
    end

    def save(attributes)
      page.assign_attributes(attributes)
      content_changed = page.new_record? || page.wiki_content_changed?
      if content_changed
        page.content_updated_at = Time.current
        page.sync_status = "pending"
        page.delete_requested_at = nil
        page.last_error = nil
      end

      return false unless page.save

      PageSyncJob.perform_later(page.id) if content_changed
      true
    end

    private

    attr_reader :page
  end
end

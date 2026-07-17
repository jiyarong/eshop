module Gbrain
  class PageSyncJob < ApplicationJob
    queue_as :gbrain
    limits_concurrency to: 1,
      key: ->(*) { "page_writes" },
      group: "Gbrain",
      duration: 30.minutes

    def perform(page_id)
      page = GbrainPage.find_by(id: page_id)
      return if page.nil?
      return unless page.sync_status.in?(%w[pending pending_delete failed])

      version = page.content_updated_at
      deletion_requested_at = page.delete_requested_at

      if deletion_requested_at.present?
        delete_page(page, deletion_requested_at)
      else
        write_page(page, version)
      end
    rescue StandardError => error
      record_failure(page_id, version, deletion_requested_at, error)
      raise
    end

    private

    def delete_page(page, deletion_requested_at)
      page.update_columns(sync_status: "deleting", last_error: nil, updated_at: Time.current)
      client.delete_page(page.slug)

      page.reload
      page.destroy! if page.delete_requested_at == deletion_requested_at
    end

    def write_page(page, version)
      page.update_columns(sync_status: "syncing", last_error: nil, updated_at: Time.current)
      client.put_page(slug: page.slug, content: page.content)

      page.reload
      attributes = { knowledge_base_written_at: Time.current, updated_at: Time.current }
      if page.content_updated_at == version && !page.pending_deletion?
        attributes[:sync_status] = "synced"
        attributes[:last_error] = nil
      end
      page.update_columns(attributes)
    end

    def record_failure(page_id, version, deletion_requested_at, error)
      page = GbrainPage.find_by(id: page_id)
      return if page.nil?
      return unless page.content_updated_at == version
      return unless page.delete_requested_at == deletion_requested_at

      page.update_columns(
        sync_status: "failed",
        last_error: error.message.truncate(2_000),
        updated_at: Time.current
      )
    end

    def client
      @client ||= Client.new
    end
  end
end

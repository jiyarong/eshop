module AttachmentsHelper
  OFFICE_ATTACHMENT_EXTENSIONS = %w[doc docx xls xlsx ppt pptx].freeze
  BROWSER_ATTACHMENT_EXTENSIONS = %w[pdf png jpg jpeg gif webp bmp txt csv json mp3 wav ogg mp4 webm].freeze

  def attachment_file_kind(attachment_or_filename)
    filename = attachment_or_filename.respond_to?(:filename) ? attachment_or_filename.filename : attachment_or_filename
    extension = File.extname(filename.to_s).delete_prefix(".").downcase

    case extension
    when "pdf" then :pdf
    when "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg" then :image
    when "xls", "xlsx", "csv" then :spreadsheet
    when "doc", "docx" then :document
    when "ppt", "pptx" then :presentation
    when "zip", "rar", "7z", "tar", "gz" then :archive
    when "mp3", "wav", "ogg" then :audio
    when "mp4", "webm", "mov" then :video
    when "txt", "json", "xml", "md" then :text
    else :unknown
    end
  end

  def attachment_file_icon(attachment_or_filename)
    {
      pdf: "bi-file-earmark-pdf",
      image: "bi-file-earmark-image",
      spreadsheet: "bi-file-earmark-spreadsheet",
      document: "bi-file-earmark-word",
      presentation: "bi-file-earmark-slides",
      archive: "bi-file-earmark-zip",
      audio: "bi-file-earmark-music",
      video: "bi-file-earmark-play",
      text: "bi-file-earmark-text",
      unknown: "bi-file-earmark"
    }.fetch(attachment_file_kind(attachment_or_filename))
  end

  def attachment_preview_kind(attachment)
    return :office if attachment_office_previewable?(attachment)
    return :browser if attachment_browser_previewable?(attachment)

    :unsupported
  end

  def attachment_office_previewable?(attachment)
    OFFICE_ATTACHMENT_EXTENSIONS.include?(attachment_extension(attachment)) &&
      attachment.file.service.is_a?(ActiveStorage::Service::QiniuService)
  end

  def attachment_browser_previewable?(attachment)
    BROWSER_ATTACHMENT_EXTENSIONS.include?(attachment_extension(attachment))
  end

  def attachment_browser_preview_content_type(attachment)
    {
      "pdf" => "application/pdf",
      "png" => "image/png",
      "jpg" => "image/jpeg",
      "jpeg" => "image/jpeg",
      "gif" => "image/gif",
      "webp" => "image/webp",
      "bmp" => "image/bmp",
      "txt" => "text/plain",
      "csv" => "text/plain",
      "json" => "application/json",
      "mp3" => "audio/mpeg",
      "wav" => "audio/wav",
      "ogg" => "audio/ogg",
      "mp4" => "video/mp4",
      "webm" => "video/webm"
    }.fetch(attachment_extension(attachment), "application/octet-stream")
  end

  def attachment_type_inline_frame_id(attachment, dom_id_prefix:)
    "#{dom_id_prefix}-attachment-#{attachment.id}-attach-type-cell"
  end

  def attachment_type_inline_cell_locals(attachment, options:, update_path:, edit_path:, dom_id_prefix:, editing: false)
    edit_query = URI.encode_www_form(inline_field: "attach_type", edit_inline: true)
    {
      record: attachment,
      field: "attach_type",
      frame_id: attachment_type_inline_frame_id(attachment, dom_id_prefix: dom_id_prefix),
      feedback_target: "global_toast",
      update_path: update_path,
      edit_url: "#{edit_path}#{edit_path.include?("?") ? "&" : "?"}#{edit_query}",
      label: t("shared.attachments.type"),
      input_kind: :select,
      value: attachment.attach_type,
      display_value: options.to_h.invert.fetch(attachment.attach_type, attachment.attach_type),
      options: options,
      editing: editing,
      error_messages: attachment.errors[:attach_type],
      align: nil
    }
  end

  private

  def attachment_extension(attachment)
    File.extname(attachment.filename.to_s).delete_prefix(".").downcase
  end
end

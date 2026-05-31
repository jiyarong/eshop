require "google/apis/drive_v3"
require "googleauth"

module GoogleSheets
  # 将 Google Sheet 整体导出为 .xlsx 并上传到指定 Drive 文件夹。
  #
  # 前提：Drive 文件夹已将 Service Account 邮箱设为编辑者。
  #
  # 用法：
  #   GoogleSheets::DriveExportService.new.export(filename: "OzonWR_W21_2026-05-24.xlsx")
  #
  # 同名文件处理：先删除文件夹内同名旧文件，再上传新文件（保持文件夹整洁）。
  class DriveExportService
    FOLDER_ID   = "1vaybDAcgHJy-n-CWrNDgZbSyf08Blq8I".freeze
    XLSX_MIME   = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze
    SCOPES      = [
      "https://www.googleapis.com/auth/drive",
    ].freeze

    def initialize
      creds = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(BaseService::CREDENTIALS_PATH),
        scope:       SCOPES
      )
      @drive = Google::Apis::DriveV3::DriveService.new
      @drive.authorization = creds
    end

    # 导出整张 Spreadsheet 为 xlsx，上传到 FOLDER_ID。
    # 返回上传后的 Google Drive File 对象（含 id / name / web_view_link）。
    def export(filename:)
      delete_existing!(filename)

      content = StringIO.new
      @drive.export_file(
        BaseService::SPREADSHEET_ID,
        XLSX_MIME,
        download_dest: content
      )
      content.rewind

      metadata = Google::Apis::DriveV3::File.new(
        name:    filename,
        parents: [FOLDER_ID]
      )
      result = @drive.create_file(
        metadata,
        fields:        "id,name,webViewLink",
        upload_source: content,
        content_type:  XLSX_MIME
      )
      puts "✓ Drive 上传完成: #{result.name} → #{result.web_view_link}"
      result
    end

    private

    def delete_existing!(filename)
      resp = @drive.list_files(
        q:      "name='#{filename}' and '#{FOLDER_ID}' in parents and trashed=false",
        fields: "files(id,name)"
      )
      resp.files.each do |f|
        @drive.delete_file(f.id)
        puts "  已删除旧文件: #{f.name} (#{f.id})"
      end
    end
  end
end

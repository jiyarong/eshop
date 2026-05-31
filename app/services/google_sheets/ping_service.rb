module GoogleSheets
  class PingService < BaseService
    def call
      write_to_sheet(
        range: "工作表1!A1:B2",
        values: [
          ["测试连通", Time.current.strftime("%Y-%m-%d %H:%M:%S")],
          ["状态", "OK"]
        ]
      )
      true
    end
  end
end

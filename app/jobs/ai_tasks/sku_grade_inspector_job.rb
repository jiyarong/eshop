module AITasks
  class SkuGradeInspectorJob < ApplicationJob
    queue_as :default

    def perform(as_of_date: nil, sku_code: nil)
      AITasks::SkuGradeInspector.run(as_of_date: as_of_date, sku_code: sku_code)
    end
  end
end

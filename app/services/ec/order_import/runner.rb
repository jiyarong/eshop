module Ec
  module OrderImport
    class Runner
      def self.run
        {
          ozon: Ozon.new.call,
          wb: Wb.new.call
        }
      end
    end
  end
end

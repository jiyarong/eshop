module Ec
  module Inventory
    class BookLedger
      # Status and reason tables of the book ledger (spec sections 4.3-4.5). Pure functions, no database access.
      module ReturnRules
        OZON_LOCATIONS = {
          "MovingToOzon" => :transit,
          "ReturnedToOzon" => :platform,
          "MovingToSeller" => :transit,
          "ReadyForSeller" => :transit,
          "ReceivedBySeller" => :own
        }.freeze

        WB_RECEIVED_STATUS = "Выдано".freeze

        OZON_UNSELLABLE_REASONS = [
          "Товар не работает / брак",
          "Товар поврежден, но упаковка цела",
          "Упаковка и товар повреждены",
          "Товар поддельный",
          "Товар сломался при эксплуатации",
          "Товар в неполной комплектации"
        ].freeze

        WB_UNSELLABLE_RETURN_TYPES = [ "Возврат брака" ].freeze

        # Where the returned goods are, or nil when the status does not reverse the sale.
        def self.location(platform, source_status)
          return nil if source_status.blank?

          case platform.to_s
          when "ozon" then OZON_LOCATIONS[source_status.to_s]
          when "wb" then source_status.to_s == WB_RECEIVED_STATUS ? :own : :transit
          end
        end

        def self.unsellable?(platform, reason:, return_type:)
          case platform.to_s
          when "ozon" then OZON_UNSELLABLE_REASONS.include?(reason.to_s)
          when "wb" then WB_UNSELLABLE_RETURN_TYPES.include?(return_type.to_s)
          else false
          end
        end
      end
    end
  end
end

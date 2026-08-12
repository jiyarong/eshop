module Ec
  class Supplier < Company
    default_scope { tagged("supplier") }

    before_validation do
      self.tags = (Array(tags) | [ "supplier" ])
    end
  end
end

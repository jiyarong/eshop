class OwnWarehouseSkuCostsController < OwnWarehouseCostsController
  def index
    params[:tab] = "allocations"
    super
  end
end

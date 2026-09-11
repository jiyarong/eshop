module ErpAI
  module V3
    class BaseController < ActionController::API
      include ErpAI::RequestAuthenticatable
    end
  end
end

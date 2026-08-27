module ErpAI
  module V2
    class BaseController < ActionController::API
      include ErpAI::RequestAuthenticatable
    end
  end
end

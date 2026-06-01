module Admin
  class BaseController < ApplicationController
    before_action -> { require_permission!(:manage_users) }
  end
end

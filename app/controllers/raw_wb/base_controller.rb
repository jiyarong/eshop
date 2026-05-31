module RawWb
  class BaseController < ApplicationController
    rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
    rescue_from ActiveRecord::RecordInvalid,  with: :record_invalid

    private

    def record_not_found(e)
      @message = e.message
      render 'raw_wb/shared/not_found', status: :not_found
    end

    def record_invalid(e)
      @errors  = e.record.errors.full_messages
      @message = @errors.first
      render 'raw_wb/shared/unprocessable', status: :unprocessable_entity
    end
  end
end

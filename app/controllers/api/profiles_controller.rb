module Api
  class ProfilesController < BaseController
    def show
      render json: {
        success: true,
        data: profile_json(current_user).merge(
          api_key: usable_api_key(current_user),
          llm_configs: llm_configs_json(current_user)
        )
      }
    end

    def usage
      api_key = current_user.sub2_user_api_key&.api_key
      unless api_key.present?
        render json: { success: false, error: "sub2_api_key_not_configured" }, status: :unprocessable_entity
        return
      end

      render json: { success: true, data: Sub2AIService.new.usage(api_key: api_key) }
    rescue Sub2AIService::Error => error
      Rails.logger.error("Sub2 usage request failed for user #{current_user.id}: #{error.message}")
      render json: { success: false, error: "sub2_usage_unavailable" }, status: :bad_gateway
    end

    def update
      current_user.assign_attributes(profile_params)

      if password_change?
        unless current_user.valid_password?(params[:current_password])
          current_user.errors.add(:current_password, :invalid)
          render_validation_errors
          return
        end

        if params[:password_confirmation].blank?
          current_user.errors.add(:password_confirmation, :blank)
          render_validation_errors
          return
        end

        current_user.assign_attributes(password_params)
      end

      current_user.avatar.attach(params[:avatar]) if params[:avatar].present?

      if current_user.save
        render json: { success: true, data: profile_json(current_user) }
      else
        render_validation_errors
      end
    end

    private

    def usable_api_key(user)
      user.api_keys.where(revoked_at: nil).order(:created_at).each do |api_key|
        raw_token = api_key.raw_token
        return raw_token if raw_token.present?
      end

      raw_token, = UserApiKey.generate_for!(user, name: next_api_key_name(user))
      raw_token
    end

    def next_api_key_name(user)
      name = "API"
      suffix = 2

      while user.api_keys.exists?(name: name)
        name = "API #{suffix}"
        suffix += 1
      end

      name
    end

    def llm_configs_json(user)
      service = Sub2AIService.new
      api_token = user.sub2_user_api_key&.api_key

      {
        entrypoint_url: service.entrypoint_url,
        api_token: api_token,
        models: api_token.present? ? service.models(api_key: api_token) : []
      }
    end

    def profile_params
      params.permit(:name, :email, :time_zone)
    end

    def password_params
      params.permit(:password, :password_confirmation)
    end

    def password_change?
      params[:password].present?
    end

    def render_validation_errors
      render json: { success: false, errors: current_user.errors.to_hash(true) }, status: :unprocessable_entity
    end
  end
end

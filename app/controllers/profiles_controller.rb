class ProfilesController < ApplicationController
  def edit
    @user = current_user
  end

  def update
    if current_user.update(profile_params)
      redirect_to edit_profile_path
    else
      @user = current_user
      render :edit, status: :unprocessable_entity
    end
  end

  def create_api_key
    raw_token, = UserApiKey.generate_for!(current_user, name: api_key_name)

    redirect_to edit_profile_path, flash: {
      api_key_token: raw_token,
      notice: t("profiles.api_keys.created")
    }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_profile_path, alert: e.record.errors.full_messages.to_sentence
  end

  def revoke_api_key
    api_key = current_user.api_keys.find(params[:api_key_id])
    api_key.update!(revoked_at: Time.current)

    redirect_to edit_profile_path, notice: t("profiles.api_keys.revoked")
  end

  private

  def profile_params
    params.require(:user).permit(:time_zone)
  end

  def api_key_name
    params.fetch(:api_key, {}).permit(:name)[:name].presence || "MCP"
  end
end

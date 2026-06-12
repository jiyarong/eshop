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

  private

  def profile_params
    params.require(:user).permit(:time_zone)
  end
end

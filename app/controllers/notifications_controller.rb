class NotificationsController < ApplicationController
  PAGE_SIZE = 20

  before_action :authenticate_user!
  before_action :load_recipient, only: %i[show mark_read mark_unread destroy]

  def index
    @filter = params[:filter].presence_in(%w[all unread read]) || "all"
    @recipients = inbox_scope
    @recipients = @recipients.unread if @filter == "unread"
    @recipients = @recipients.read if @filter == "read"
    @recipients = @recipients.page(page_param).per(PAGE_SIZE)

    respond_to do |format|
      format.html
      format.json { render json: notification_collection_json }
    end
  end

  def show
    @recipient.read! if @recipient.unread?

    respond_to do |format|
      format.html
      format.json { render json: notification_json(@recipient) }
    end
  end

  def mark_read
    @recipient.read!
    respond_to_status
  end

  def mark_unread
    @recipient.unread!
    respond_to_status
  end

  def destroy
    @recipient.delete!
    respond_to do |format|
      format.html { redirect_to notifications_path(filter: params[:filter]), notice: t("notifications.flash.deleted") }
      format.json { render json: { ok: true } }
    end
  end

  def mark_all_read
    now = Time.current
    current_user.system_notification_recipients.active.unread.update_all(read_at: now, updated_at: now)
    respond_to do |format|
      format.html { redirect_to notifications_path(filter: params[:filter]), notice: t("notifications.flash.marked_all_read") }
      format.json { render json: { ok: true, unread_count: 0 } }
    end
  end

  private

  def inbox_scope
    current_user.system_notification_recipients
      .active
      .joins(:notification)
      .includes(:notification)
      .order("ec_system_notifications.occurred_at DESC, ec_system_notifications.id DESC")
  end

  def load_recipient
    @recipient = current_user.system_notification_recipients.active.find(params[:id])
    @notification = @recipient.notification
  end

  def page_param
    value = params[:page].to_i
    value.positive? ? value : 1
  end

  def respond_to_status
    respond_to do |format|
      format.html { redirect_to notifications_path(filter: params[:filter]) }
      format.json { render json: notification_json(@recipient) }
    end
  end

  def notification_collection_json
    {
      unread_count: current_user.system_notification_recipients.active.unread.count,
      notifications: @recipients.map { |recipient| notification_json(recipient) }
    }
  end

  def notification_json(recipient)
    notification = recipient.notification
    {
      id: recipient.id,
      notification_id: notification.id,
      type: notification.notification_type,
      severity: notification.severity,
      title: notification.title,
      body: notification.body,
      sku_code: notification.sku_code,
      target_path: notification.target_path,
      occurred_at: notification.occurred_at,
      read_at: recipient.read_at,
      deleted_at: recipient.deleted_at,
      occurrence_count: notification.occurrence_count
    }
  end
end

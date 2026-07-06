module InlineEditableResponse
  extend ActiveSupport::Concern

  private

  def inline_edit_request?
    turbo_stream_request = request.format.turbo_stream? || request.headers["Accept"].to_s.include?(Mime[:turbo_stream].to_s)
    turbo_stream_request && params[:inline_field].present?
  end

  def inline_field_name(allowed_fields)
    field = params[:inline_field].to_s
    return field if allowed_fields.include?(field)

    raise ActionController::BadRequest, "Unsupported inline field"
  end

  def inline_context_param(key)
    context = params[:inline_context]
    return unless context

    if context.respond_to?(:permit)
      context.permit(:frame_id, :feedback_target)[key.to_s]
    elsif context.respond_to?(:to_h)
      context.to_h[key.to_s]
    else
      raise ActionController::BadRequest, "Invalid inline_context"
    end
  end

  def render_inline_edit_success(frame_id:, feedback_target:, cell_partial:, cell_locals:, message:)
    render turbo_stream: [
      turbo_stream.replace(frame_id, partial: cell_partial, locals: cell_locals),
      turbo_stream.update(feedback_target, global_toast_markup(tone: :success, message: message))
    ]
  end

  def render_inline_edit_failure(frame_id:, feedback_target:, cell_partial:, cell_locals:, message:)
    render status: :unprocessable_entity, turbo_stream: [
      turbo_stream.replace(frame_id, partial: cell_partial, locals: cell_locals),
      turbo_stream.update(feedback_target, global_toast_markup(tone: :error, message: message))
    ]
  end

  def global_toast_markup(tone:, message:)
    classes = ["panel", "global-toast", "global-toast--#{tone}"]
    classes << "error-box" if tone.to_sym == :error

    view_context.tag.div(
      message,
      class: classes.join(" "),
      role: "status",
      data: {
        controller: "toast",
        toast_delay_value: 2400
      },
      aria: { live: "polite" }
    )
  end
end

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
    else
      context.to_h[key.to_s]
    end
  end

  def render_inline_edit_success(frame_id:, feedback_target:, cell_partial:, cell_locals:, message:)
    render turbo_stream: [
      turbo_stream.replace(frame_id, partial: cell_partial, locals: cell_locals),
      turbo_stream.update(feedback_target, inline_feedback_markup(tone: :success, message: message))
    ]
  end

  def render_inline_edit_failure(frame_id:, feedback_target:, cell_partial:, cell_locals:, message:)
    render status: :unprocessable_entity, turbo_stream: [
      turbo_stream.replace(frame_id, partial: cell_partial, locals: cell_locals),
      turbo_stream.update(feedback_target, inline_feedback_markup(tone: :error, message: message))
    ]
  end

  def inline_feedback_markup(tone:, message:)
    classes = ["panel", "inline-edit-feedback", "inline-edit-feedback--#{tone}"]
    classes << "error-box" if tone.to_sym == :error

    view_context.tag.div(message, class: classes.join(" "), role: "status", aria: { live: "polite" })
  end
end

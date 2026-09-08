class ConversationReplyJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, user_message_id, locale: I18n.default_locale.to_s)
    conversation = Conversation.includes(:agent, :user).find(conversation_id)
    user_message = conversation.messages.find(user_message_id)
    return unless user_message.role == "user"

    I18n.with_locale(locale) do
      broadcaster = ErpAI::ConversationBroadcaster.new(conversation)
      conversation.update_response_status!("running")
      broadcaster.replace_composer

      ErpAI::AgentRunner.new(agent: conversation.agent, user: conversation.user).reply(
        conversation: conversation,
        broadcaster: broadcaster
      )

      conversation.update_response_status!("idle")
      broadcaster.replace_composer
    end
  rescue StandardError
    if conversation&.persisted?
      conversation.update_response_status!("failed")
      ErpAI::ConversationBroadcaster.new(conversation).replace_composer
    end
    raise
  end
end

# Keep this namespace stable even when a dependency registers the AI acronym.
Rails.autoloaders.main.inflector.inflect(
  "ai_eval" => "AiEval"
)

# frozen_string_literal: true

require_relative "../config/environment"

module MigrateAIDiagnosisResultRoute
  OLD_ROUTES = [
    "/ai/skus/inventory_health_result",
    "skus/inventory_health_result"
  ].freeze
  NEW_ROUTE = "/ai/diagnosis_results".freeze
  DIAGNOSIS_TYPE = "RestockingDiagnosis".freeze

  module_function

  def transform(text)
    result = text.to_s.dup
    OLD_ROUTES.each { |route| result.gsub!(route, NEW_ROUTE) }
    return result unless result.include?(NEW_ROUTE)

    result.gsub!(/(POST #{Regexp.escape(NEW_ROUTE)}`?\s*(?:```json\s*)?\{)(?!\s*["']?type["']?\s*:)/m) do
      %(#{$1}\n  "type": "#{DIAGNOSIS_TYPE}",)
    end
    result
  end

  def transform_value(value)
    case value
    when Array
      value.map { |item| transform_value(item) }
    when Hash
      value.transform_values { |item| transform_value(item) }
    when String
      transform(value)
    else
      value
    end
  end

  def run!(apply: ENV["APPLY"] == "1")
    changes = candidates.filter_map do |record, field|
      before = record.public_send(field)
      after = transform_value(before)
      next if before == after

      { record: record, field: field, before: before, after: after }
    end

    print_plan(changes, apply: apply)
    return if !apply || changes.empty?

    ApplicationRecord.transaction do
      changes.group_by { |change| change.fetch(:record) }.each do |record, record_changes|
        attributes = record_changes.to_h { |change| [change.fetch(:field), change.fetch(:after)] }
        if record.is_a?(Skill)
          raise "Skill #{record.name} has no archive" unless record.archive.attached?

          package = SkillPackage.replace_skill_md(record.archive.download, attributes.fetch(:skill_md, record.skill_md))
          attributes[:skill_md] = package.skill_md
          record.update!(attributes)
          record.archive.attach(
            io: StringIO.new(package.archive_data),
            filename: "#{package.name}.zip",
            content_type: "application/zip"
          )
        else
          record.update!(attributes)
        end
      end

      remaining = old_route_hits
      raise "old diagnosis route remains: #{remaining.join(', ')}" if remaining.any?
    end

    puts "Applied #{changes.size} field update(s); old route scan is clean."
  end

  def candidates
    Enumerator.new do |rows|
      Agent.find_each do |agent|
        %i[system_prompt description recommended_prompts].each { |field| rows << [agent, field] }
      end
      Skill.find_each do |skill|
        %i[skill_md description].each { |field| rows << [skill, field] }
      end
    end
  end

  def old_route_hits
    candidates.filter_map do |record, field|
      value = record.public_send(field).to_json
      next unless OLD_ROUTES.any? { |route| value.include?(route) }

      "#{record.class}(#{record.id}).#{field}"
    end
  end

  def print_plan(changes, apply:)
    puts "Mode: #{apply ? 'APPLY' : 'DRY RUN'}"
    if changes.empty?
      puts "No old diagnosis routes found."
      return
    end

    changes.each do |change|
      record = change.fetch(:record)
      key = record.respond_to?(:code) ? record.code : record.name
      old_count = OLD_ROUTES.sum { |route| change.fetch(:before).to_json.scan(route).size }
      puts "#{record.class}(#{record.id}, #{key}).#{change.fetch(:field)}: #{old_count} route occurrence(s)"
    end
  end
end

MigrateAIDiagnosisResultRoute.run! if $PROGRAM_NAME == __FILE__

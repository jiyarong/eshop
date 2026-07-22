# frozen_string_literal: true

require_relative "../config/environment" unless defined?(Rails)
require "stringio"
require "yaml"

# Usage:
#   DRY_RUN=1 bundle exec rails runner script/sync_erp_ai_sql_query_agent.rb
#   bundle exec rails runner script/sync_erp_ai_sql_query_agent.rb

class ErpAiSqlQueryAgentSync
  AGENT_CODE = "erp_ai_sql_query_agent"
  AGENT_NAME = "ERP 数据查询 Agent"
  AGENT_DESCRIPTION = "基于只读 SQL 查询接口和已封装业务 API 回答 ERP 经营数据问题的 Agent。"
  PROMPT_PATH = Rails.root.join("docs/erp_ai_sql_query_agent_system_prompt.md")
  SKILLS_DIR = Rails.root.join("docs/erp_ai_sql_query_agent_system_prompt")

  SKILL_DESCRIPTIONS = {
    "product_catalog" => "ERP SQL 查询：商品、SPU、SKU、店铺、类目和平台商品绑定表字段与关系。",
    "orders_sales" => "ERP SQL 查询：订单、履约、销量归属和销售统计口径。",
    "inventory_procurement" => "ERP SQL 查询：库存、批次、库存详情页计算过程和平台库存口径。",
    "costs_profit" => "ERP SQL 查询：SKU 基础成本、采购成本、体积重量和进口税参数字段与关系。",
    "ozon_localization" => "ERP SQL 查询：Ozon 发货集群、目的集群和本地化销售占比口径。",
    "raw_platform_data" => "ERP SQL 查询：WB 与 Ozon 原始平台数据表字段和关系。",
    "weekly_rates" => "ERP SQL 查询：周汇率、RUB/CNY/BYN 换算和周报汇率口径。",
    "weekly_profit_attribution" => "ERP 数据查询：通过 /ai/weekly_profit_reports 调用 WR、WSU、WSU-DEEP 周利润归集 API。"
  }.freeze

  def initialize(env: ENV, stdout: $stdout)
    @env = env
    @stdout = stdout
    @dry_run = ActiveModel::Type::Boolean.new.cast(env.fetch("DRY_RUN", false))
  end

  def call
    validate_files!

    stdout.puts "Sync ERP AI SQL query agent"
    stdout.puts "Agent code: #{AGENT_CODE}"
    stdout.puts "Prompt: #{PROMPT_PATH.relative_path_from(Rails.root)}"
    stdout.puts "Skills dir: #{SKILLS_DIR.relative_path_from(Rails.root)}"
    stdout.puts "Dry run: #{dry_run ? "yes" : "no"}"

    skill_payloads = build_skill_payloads
    stdout.puts "Skills: #{skill_payloads.map { |payload| payload.fetch(:name) }.join(", ")}"

    return dry_run_result(skill_payloads) if dry_run

    ActiveRecord::Base.transaction do
      agent = sync_agent!
      skills = skill_payloads.map { |payload| sync_skill!(payload) }
      sync_agent_skills!(agent, skills)

      stdout.puts "Synced agent ##{agent.id}: #{agent.code}"
      stdout.puts "Synced skills: #{skills.size}"
      stdout.puts "Synced agent skill links: #{skills.size}"

      { agent: agent, skills: skills }
    end
  end

  private

  attr_reader :env, :stdout, :dry_run

  def validate_files!
    raise Errno::ENOENT, PROMPT_PATH.to_s unless PROMPT_PATH.file?
    raise Errno::ENOENT, SKILLS_DIR.to_s unless SKILLS_DIR.directory?
    raise "No SKILL.md files found under #{SKILLS_DIR}" if skill_paths.empty?
  end

  def sync_agent!
    agent = Agent.find_or_initialize_by(code: AGENT_CODE)
    agent.assign_attributes(
      name: AGENT_NAME,
      description: AGENT_DESCRIPTION,
      system_prompt: PROMPT_PATH.read,
      model_id: "deepseek-v4-flash",
      temperature: BigDecimal("0.3"),
      thinking_enabled: false,
      agent_type: "client",
      tools: [],
      enabled: true,
      recommended_prompts: recommended_prompts
    )
    agent.save!
    agent
  end

  def sync_skill!(payload)
    package = SkillPackage.from_markdown(payload.fetch(:skill_md))
    skill = Skill.find_or_initialize_by(name: package.name)
    skill.assign_attributes(
      description: package.description,
      version: payload.fetch(:version),
      skill_md: package.skill_md
    )
    skill.save!
    attach_archive!(skill, package)
    skill
  end

  def attach_archive!(skill, package)
    skill.archive.attach(
      io: StringIO.new(package.archive_data),
      filename: "#{package.name}.zip",
      content_type: "application/zip"
    )
  end

  def sync_agent_skills!(agent, skills)
    skills.each do |skill|
      AgentSkill.find_or_create_by!(agent: agent, skill: skill)
    end
  end

  def build_skill_payloads
    skill_paths.map do |path|
      folder_name = path.parent.basename.to_s
      name = skill_name_for(folder_name)
      description = skill_description_for(folder_name, path.read)
      {
        name: name,
        description: description,
        version: "1",
        skill_md: skill_markdown_with_manifest(path.read, name, description)
      }
    end
  end

  def skill_paths
    @skill_paths ||= Pathname.glob(SKILLS_DIR.join("*/SKILL.md")).sort
  end

  def skill_name_for(folder_name)
    "erp-ai-sql-query-#{folder_name.tr("_", "-")}"
  end

  def skill_description_for(folder_name, body)
    SKILL_DESCRIPTIONS[folder_name] || first_description_line(body) || "ERP AI SQL query skill for #{folder_name.tr("_", " ")}."
  end

  def first_description_line(body)
    body_without_manifest(body)
      .lines
      .map(&:strip)
      .reject { |line| line.blank? || line.start_with?("#") }
      .first
  end

  def skill_markdown_with_manifest(body, name, description)
    metadata = {
      "name" => name,
      "description" => description
    }.to_yaml
    "#{metadata}---\n#{body_without_manifest(body).lstrip}"
  end

  def body_without_manifest(body)
    body.to_s.sub(/\A---[ \t]*\r?\n.*?\r?\n---[ \t]*\r?\n/m, "")
  end

  def recommended_prompts
    [
      "统计最近 30 天各 SKU 销量和净销量",
      "查询当前库存低于 10 件的 SKU",
      "分析 Ozon SKU 本地化销售占比",
      "查询某个 SKU 的成本和平台绑定"
    ]
  end

  def dry_run_result(skill_payloads)
    stdout.puts "DRY RUN, no database changes."
    stdout.puts "Would upsert agent: #{AGENT_CODE}"
    skill_payloads.each do |payload|
      stdout.puts "Would upsert skill: #{payload.fetch(:name)}"
    end
    { agent: nil, skills: [] }
  end
end

ErpAiSqlQueryAgentSync.new.call if $PROGRAM_NAME == __FILE__

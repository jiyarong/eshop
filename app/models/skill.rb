class Skill < ApplicationRecord
  has_many :agent_skills, dependent: :destroy
  has_many :agents, through: :agent_skills
  has_one_attached :archive

  validates :name, :description, :version, :skill_md, presence: true
  validates :name, uniqueness: true
  validate :skill_md_matches_fields

  private

  def skill_md_matches_fields
    manifest = SkillManifest.parse(skill_md)
    errors.add(:name, I18n.t("admin.skills.errors.name_mismatch")) if name.present? && name != manifest.name
    errors.add(:description, I18n.t("admin.skills.errors.description_mismatch")) if description.present? && description != manifest.description
  rescue SkillManifest::Error => error
    errors.add(:skill_md, error.message)
  end
end

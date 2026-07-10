module Admin
  class SkillsController < BaseController
    before_action :set_skill, only: [ :show, :edit, :update, :download ]

    def index
      @skills = Skill.with_attached_archive.order(:name)
    end

    def show
    end

    def new
      @skill = Skill.new(version: "1")
      @mode = params[:mode] == "upload" ? "upload" : "markdown"
    end

    def edit
    end

    def create
      @skill = Skill.new(version: skill_params[:version])
      @mode = params[:creation_mode] == "upload" ? "upload" : "markdown"
      package = package_for_create

      if save_with_package(package)
        redirect_to admin_skill_path(@skill), notice: t("admin.skills.notices.created")
      else
        render :new, status: :unprocessable_entity
      end
    rescue SkillManifest::Error, SkillPackage::Error => error
      @skill.errors.add(:base, error.message)
      render :new, status: :unprocessable_entity
    end

    def update
      package = SkillPackage.replace_skill_md(@skill.archive.download, skill_params[:skill_md])
      @skill.version = skill_params[:version]

      if save_with_package(package)
        redirect_to admin_skill_path(@skill), notice: t("admin.skills.notices.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    rescue SkillManifest::Error, SkillPackage::Error => error
      @skill.errors.add(:base, error.message)
      render :edit, status: :unprocessable_entity
    end

    def download
      redirect_to rails_blob_path(@skill.archive, disposition: "attachment"), allow_other_host: false
    end

    private

    def set_skill
      @skill = Skill.find(params[:id])
    end

    def skill_params
      params.require(:skill).permit(:version, :skill_md, :archive)
    end

    def package_for_create
      if @mode == "upload"
        SkillPackage.from_upload(skill_params[:archive])
      else
        SkillPackage.from_markdown(skill_params[:skill_md])
      end
    end

    def save_with_package(package)
      @skill.assign_attributes(
        name: package.name,
        description: package.description,
        skill_md: package.skill_md
      )
      return false unless @skill.save

      @skill.archive.attach(
        io: StringIO.new(package.archive_data),
        filename: "#{package.name}.zip",
        content_type: "application/zip"
      )
      true
    end
  end
end

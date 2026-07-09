module Ec
  class CategoryWbImporter
    SOURCE = "wb".freeze
    CATEGORY_SOURCE_TYPE = "RawWb::Category".freeze
    SUBJECT_SOURCE_TYPE = "RawWb::Subject".freeze
    ORIGIN_LANGUAGE = "ru".freeze

    def self.import_categories(raw_rows)
      new.import_categories(raw_rows)
    end

    def self.import_subjects(raw_rows)
      new.import_subjects(raw_rows)
    end

    def import_categories(raw_rows)
      raw_categories = RawWb::Category.where(wb_id: Array(raw_rows).filter_map { |row| row[:wb_id] })
      rows = raw_categories.filter_map do |raw_category|
        next if raw_category.name.blank?

        build_row(
          source_type: CATEGORY_SOURCE_TYPE,
          source_id: raw_category.id,
          parent_id: nil,
          origin_name: raw_category.name,
          synced_at: raw_category.synced_at
        )
      end

      upsert(rows)
      rows.size
    end

    def import_subjects(raw_rows)
      raw_subjects = RawWb::Subject.where(wb_id: Array(raw_rows).filter_map { |row| row[:wb_id] }).includes(:category)
      parent_id_by_raw_category_id = parent_id_by_raw_category_id(raw_subjects.map(&:category_id))
      rows = raw_subjects.filter_map do |raw_subject|
        next if raw_subject.name.blank?

        build_row(
          source_type: SUBJECT_SOURCE_TYPE,
          source_id: raw_subject.id,
          parent_id: parent_id_by_raw_category_id[raw_subject.category_id],
          origin_name: raw_subject.name,
          synced_at: raw_subject.synced_at
        )
      end

      upsert(rows)
      rows.size
    end

    private

    def build_row(source_type:, source_id:, parent_id:, origin_name:, synced_at:)
      now = Time.current
      {
        source: SOURCE,
        source_type: source_type,
        source_id: source_id.to_s,
        parent_id: parent_id,
        origin_name: origin_name,
        origin_language: ORIGIN_LANGUAGE,
        name_ru: origin_name,
        synced_at: synced_at,
        created_at: now,
        updated_at: now
      }
    end

    def upsert(rows)
      return if rows.empty?

      Ec::Category.upsert_all(
        rows,
        unique_by: [:source, :source_type, :source_id],
        update_only: %i[parent_id origin_name origin_language name_ru synced_at]
      )
    end

    def parent_id_by_raw_category_id(raw_category_ids)
      raw_category_ids = Array(raw_category_ids).compact.uniq
      ec_id_by_source_id = Ec::Category
        .where(source: SOURCE, source_type: CATEGORY_SOURCE_TYPE, source_id: raw_category_ids.map(&:to_s))
        .pluck(:source_id, :id)
        .to_h

      raw_category_ids.index_with { |id| ec_id_by_source_id[id.to_s] }
    end
  end
end

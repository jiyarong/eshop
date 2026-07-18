class AddWikiFieldsToGbrainPages < ActiveRecord::Migration[8.1]
  def change
    add_column :gbrain_pages, :title, :string
    add_column :gbrain_pages, :page_type, :string
    add_column :gbrain_pages, :subtype, :string
    add_column :gbrain_pages, :aliases, :jsonb, null: false, default: []
    add_column :gbrain_pages, :tags, :jsonb, null: false, default: []
    add_column :gbrain_pages, :platform, :string
    add_column :gbrain_pages, :country, :string
    add_column :gbrain_pages, :region_scope, :jsonb, null: false, default: []
    add_column :gbrain_pages, :category_scope, :jsonb, null: false, default: []
    add_column :gbrain_pages, :effective_date, :date
    add_column :gbrain_pages, :reviewed_at, :date
    add_column :gbrain_pages, :review_after, :date
    add_column :gbrain_pages, :source_tier, :string
    add_column :gbrain_pages, :confidence, :string
    add_column :gbrain_pages, :summary, :text

    add_index :gbrain_pages, :page_type
  end
end

class CreateChangesAndAnnotations < ActiveRecord::Migration[5.0]
  # These models will help to clean out some of the more messy aspects of
  # things that we've combined into pages and versions.

  def change
    db_connection = ActiveRecord::Base.connection
    uuid_type = db_connection.valid_type?(:uuid) ? :uuid : :string
    json_type = db_connection.valid_type?(:jsonb) ? :jsonb : :json

    create_table :changes, id: false do |t|
      t.primary_key :uuid, uuid_type, default: nil
      t.send uuid_type, :uuid_from, null: false
      t.send uuid_type, :uuid_to, null: false
      t.float :priority, null: false, default: 0.5
      t.send json_type, :current_annotation
      t.timestamps

      t.index :uuid_to
    end

    create_table :annotations, id: false do |t|
      t.primary_key :uuid, uuid_type, default: nil
      # There doesn't seem to be a way to use `belongs_to` or `references` to
      # get a column named `*_uuid`
      t.send uuid_type, :change_uuid, null: false
      t.string :author
      t.send json_type, :annotation, null: false
      t.timestamps

      t.index :change_uuid
    end

    Version.all.each do |version|
      this_change = Change.create(
        uuid_from: version.previous.uuid,
        uuid_to: version.uuid,
        current_annotation: version.current_annotation)

      version.annotations.each do |old_annotation|
        annotation = Annotation.create(
          uuid: old_annotation.id,
          change_uuid: this_change.uuid,
          created_at: DateTime.parse(old_annotation.created_at),
          author: old_annotation.author,
          annotation: old_annotation.annotation)
      end
    end

    # TODO: add source_type, source_metadata to version, populate from page
    # TODO: remove old columns from Version, Page

  end
end

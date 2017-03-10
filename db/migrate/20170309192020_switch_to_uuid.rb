class SwitchToUuid < ActiveRecord::Migration[5.0]
  def do_sql(*args)
    expression = ActiveRecord::Base.send :sanitize_sql, args
    ActiveRecord::Base.connection.exec_query(expression)
  end

  def up
    # Make sure Postgres UUID type support is on
    enable_extension 'uuid-ossp'

    db_connection = ActiveRecord::Base.connection
    uuid_type = db_connection.valid_type?(:uuid) ? :uuid : :string
    json_type = db_connection.valid_type?(:jsonb) ? :jsonb : :json

    change_table :versionista_pages do |t|
      t.send uuid_type, :uuid
    end

    change_table :versionista_versions do |t|
      t.send uuid_type, :uuid
      t.send uuid_type, :page_uuid
    end

    say_with_time 'Populating UUIDs' do
      VersionistaPage.all.each do |page|
        do_sql(
          'UPDATE versionista_pages SET uuid = ? WHERE id = ?',
          SecureRandom.uuid,
          page.attributes['id'])
      end

      VersionistaVersion.all.each do |version|
        page = do_sql('SELECT * FROM versionista_pages WHERE id = ?', version.page_id).first
        do_sql(
          'UPDATE versionista_versions SET uuid = ?, page_uuid = ? WHERE id = ?',
          SecureRandom.uuid,
          page['uuid'],
          version.attributes['id'])
      end
    end

    say_with_time 'Swapping primary keys' do
      remove_foreign_key :versionista_versions, :versionista_pages
      execute "ALTER TABLE versionista_pages DROP CONSTRAINT versionista_pages_pkey;"
      execute "ALTER TABLE versionista_pages ADD PRIMARY KEY (uuid);"
      execute "ALTER TABLE versionista_versions DROP CONSTRAINT versionista_versions_pkey;"
      execute "ALTER TABLE versionista_versions ADD PRIMARY KEY (uuid);"

      # Since this isn't a primary key, we need to explicitly switch it to NOT NULL now
      change_column_null :versionista_versions, :page_uuid, false
    end

    say_with_time 'Dropping old `id` columns' do
      remove_column :versionista_pages, :id
      remove_column :versionista_versions, :id
      remove_column :versionista_versions, :page_id
    end
  end

  def down
    raise "This is a one-way migration"
  end
end

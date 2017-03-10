class RemoveVersionistaModelPrefix < ActiveRecord::Migration[5.0]
  def change
    rename_table :versionista_pages, :pages
    rename_table :versionista_versions, :versions
  end
end

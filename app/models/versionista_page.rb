class VersionistaPage < ApplicationRecord
  self.primary_key = 'uuid'

  has_many :versions, -> { order(created_at: :desc) }, class_name: 'VersionistaVersion', foreign_key: 'page_uuid', inverse_of: :page

  def before_create
    self.uuid = SecureRandom.uuid
  end

  def as_json(*args)
    result = super(*args)
    if result['versions'].nil?
      result['latest'] = self.versions.first.as_json
    end
    result
  end
end

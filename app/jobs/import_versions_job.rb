class ImportVersionsJob < ApplicationJob
  queue_as :default

  # TODO: wrap in transaction?
  def perform(import)
    Rails.logger.debug "Running Import \##{import.id}"
    @import = import
    @import.update(status: :processing)

    data = FileStorage.default.get_file(@import.file)

    begin
      import_raw_data(data)
    rescue
      @import.processing_errors << 'Unknown error occurred'
      raise
    ensure
      @import.status = :complete
      @import.save
    end
  end

  def import_raw_data(raw_data)
    each_json_line(raw_data) do |record, row|
      begin
        import_record(record)
      rescue Api::NotImplementedError => error
        @import.processing_errors << "Row #{row}: #{error.message}"
      rescue Api::InputError => error
        @import.processing_errors << "Row #{row}: #{error.message}"
      rescue ActiveModel::ValidationError => error
        messages = error.model.errors.full_messages.join(', ')
        @import.processing_errors << "Row #{row}: #{messages}"
      rescue ActiveRecord::RecordInvalid => error
        messages = error.model.errors.full_messages.join(', ')
        @import.processing_errors << "Row #{row}: #{messages}"
      rescue
        # for unexpected error types, still not the job failed and complete it
        @import.processing_errors << 'Unknown error occurred'
        raise
      end
    end
  end

  def import_record(record)
    version = version_for_record(record)

    if version.uri.nil?
      if record['content']
        # TODO: upload content
        raise Api::NotImplementedError, 'Raw content uploading not implemented yet.'
      end
    elsif !Archiver.already_archived?(version.uri) || !version.version_hash
      result = Archiver.archive(version.uri)
      version.version_hash = result[:hash]
      if result[:url] != version.uri
        version.source_metadata['original_url'] = version.uri
        version.uri = result[:url]
      end
    end

    page = find_or_create_page_for_record(record)
    existing = page.versions.find_by(
      capture_time: version.capture_time,
      source_type: version.source_type
    )

    unless existing
      version.page = page
      version.validate!
      version.save
    end
  end

  def version_for_record(record)
    permitted_keys = [
      'uuid',
      'capture_time',
      'uri',
      'version_hash',
      'source_type',
      'source_metadata'
    ]
    version_record = record.select {|key| permitted_keys.include?(key)}
    Version.new(version_record)
  end

  def find_or_create_page_for_record(record)
    # TODO: there shouldn't be a special case for Versionista here -- we should
    # just match on `url`, but this requires fixing:
    # https://github.com/edgi-govdata-archiving/web-monitoring-db/issues/24
    search_options = { url: Page.normalize_url(record['page_url']) }
    if record['source_type'] == 'versionista'
      search_options[:site] = record['site_name']
    end
    Page.find_by(search_options) || Page.create(
      url: record['page_url'],
      title: record['page_title'],
      agency: record['site_agency'],
      site: record['site_name']
    )
  end

  private

  # iterate through a JSON array or series of newline-delimited JSON objects
  def each_json_line(raw_json)
    record_set = nil

    begin
      record_set = JSON.parse(raw_json)
      # If could have been a JSON stream with only a single record
      record_set = [record_set] unless record_set.is_a?(Array)
    rescue JSON::ParserError
      record_set = raw_json.split("\n")
    end

    record_set.each_with_index do |line, row|
      if line.is_a? String
        next if line.empty?
        yield JSON.parse(line), row
      else
        yield line, row
      end
    end
  end
end

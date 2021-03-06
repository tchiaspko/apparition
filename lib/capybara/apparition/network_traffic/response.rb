# frozen_string_literal: true

module Capybara::Apparition::NetworkTraffic
  class Response
    def initialize(data)
      @data = data
    end

    def url
      @data['url']
    end

    def status
      @data['status']
    end

    def status_text
      @data['statusText']
    end

    def headers
      @data['headers']
    end

    def redirect_url
      @data['redirectURL']
    end

    def body_size
      @data['bodySize']
    end

    def content_type
      @data['contentType']
    end

    def from_cache?
      @data['fromDiskCache'] == true
    end

    def time
      @data['timestamp'] && Time.parse(@data['timestamp'])
    end

    def error
      Error.new(url: url, code: status, description: status_text)
    end
  end
end

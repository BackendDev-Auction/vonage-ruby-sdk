# typed: true
# frozen_string_literal: true
require 'net/http'
require 'json'

module Vonage
  class Namespace
    def initialize(config)
      @config = config

      @host = self.class.host == :api_host ? @config.api_host : @config.rest_host

      @http = Net::HTTP.new(@host, Net::HTTP.https_default_port, p_addr = nil)
      @http.use_ssl = true

      @config.http.set(@http) unless @config.http.nil?
    end

    def self.host
      @host ||= :api_host
    end

    def self.host=(host)
      raise ArgumentError unless host == :rest_host

      @host = host
    end

    def self.authentication
      @authentication ||= KeySecretParams
    end

    def self.authentication=(authentication)
      @authentication = authentication
    end

    def self.request_body
      @request_body ||= FormData
    end

    def self.request_body=(request_body)
      @request_body = request_body
    end

    def self.request_headers
      @request_headers ||= {}
    end

    protected
    # :nocov:

    Get = Net::HTTP::Get
    Put = Net::HTTP::Put
    Post = Net::HTTP::Post
    Delete = Net::HTTP::Delete

    def request(path, params: nil, type: Get, auto_advance: false, response_class: Response, &block)
      uri = URI('https://' + @host + path)

      params ||= {}

      authentication = self.class.authentication.new(@config)
      authentication.update(params)

      unless type.const_get(:REQUEST_HAS_BODY) || params.empty?
        uri.query = Params.encode(params)
      end

      authentication.update(uri)

      message = type.new(uri)

      message['User-Agent'] = UserAgent.string(@config.app_name, @config.app_version)

      self.class.request_headers.each do |key, value|
        message[key] = value
      end

      authentication.update(message)

      self.class.request_body.update(message, params) if type.const_get(:REQUEST_HAS_BODY)

      logger.log_request_info(message)

      if auto_advance == true
        iterable_request(path, params: params, request: message, response_class: response_class, &block)
      else
        response = @http.request(message, &block)

        logger.log_response_info(response, @host)

        return if block

        logger.debug(response.body) if response.body

        parse(response, response_class)
      end
    end
    
    def iterable_request(path, params: nil, request: nil, auto_advance: true, response_class: nil, &block)
      first_response = @http.request(request, &block)
      response_to_json = ::JSON.parse(first_response.body)
      response = parse(first_response, response_class)
      remainder = remaining_count(response_to_json)

      while remainder > 0
        uri = URI('https://' + @host + path)

        params ||= {}
  
        if response_to_json['record_index'] && response_to_json['record_index'] == 0
          params[:record_index] = response_to_json['page_size']
        elsif response_to_json['record_index'] && response_to_json['record_index'] != 0
          params[:record_index] = (response_to_json['record_index'] + response_to_json['page_size']) 
        end

        if response_to_json['total_pages']
          params[:page] = response_to_json['page'] + 1
        end

        authentication = self.class.authentication.new(@config)
        authentication.update(params)
  
        uri.query = Params.encode(params)
  
        authentication.update(uri)
  
        request = Get.new(uri)
  
        request['User-Agent'] = UserAgent.string(@config.app_name, @config.app_version)
  
        self.class.request_headers.each do |key, value|
          request[key] = value
        end
  
        authentication.update(request)
  
        logger.log_request_info(request)


        request.uri.query = Params.encode(params)
        http_response = @http.request(request, &block)
        next_response = parse(http_response, response_class)
        response_to_json = ::JSON.parse(http_response.body)
        remainder = remaining_count(response_to_json)

        if response.respond_to?('_embedded')
          response['_embedded'][collection_name(response['_embedded'])].push(*next_response['_embedded'][collection_name(next_response['_embedded'])])
        end

        if !response.respond_to?('_embedded')
          response[collection_name(response)].push(*next_response[collection_name(next_response)])
        end
                  
        logger.log_response_info(http_response, @host)

        return if block
        
        logger.debug(http_response.body) if http_response.body

      end

      response
    end

    def remaining_count(params)
      if params.key?('total_pages')
        remaining_count = params['total_pages'] - params['page']
        
        return remaining_count
      end

      if params.key?('count')
        remaining_count = params['count'] - (params['record_index'] == 0 ? params['page_size'] : (params['record_index'] + params['page_size']))

        return remaining_count
      end

      0
    end

    def collection_name(params)
      @collection_name ||= begin
        if params.respond_to?('calls')
          return 'calls'
        end

        if params.respond_to?('users')
          return 'users'
        end

        if params.respond_to?('legs')
          return 'legs'
        end

        if params.respond_to?('data')
          return 'data'
        end

        if params.respond_to?('conversations')
          return 'conversations'
        end

        if params.respond_to?('applications')
          return 'applications'
        end

        if params.respond_to?('records')
          return 'records'
        end

        if params.respond_to?('reports')
          return 'reports'
        end

        if params.respond_to?('networks')
          return 'networks'
        end

        if params.respond_to?('countries')
          return 'countries'
        end

        if params.respond_to?('media')
          return 'media'
        end

        if params.respond_to?('numbers')
          return 'numbers'
        end

        if params.respond_to?('events')
          return 'events'
        end

        params.entity.attributes.keys[0].to_s
      end
    end

    def parse(response, response_class)
      case response
      when Net::HTTPNoContent
        response_class.new(nil, response)
      when Net::HTTPSuccess
        if response['Content-Type'].split(';').first == 'application/json'
          entity = ::JSON.parse(response.body, object_class: Vonage::Entity)

          response_class.new(entity, response)
        else
          response_class.new(nil, response)
        end
      else
        raise Errors.parse(response)
      end
    end

    def logger
      @config.logger
    end
  end

  private_constant :Namespace
  # :nocov:
end

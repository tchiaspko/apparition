# frozen_string_literal: true

require 'chrome_remote'
require 'capybara/apparition/errors'
require 'capybara/apparition/command'
require 'capybara/apparition/dev_tools_protocol/target'
require 'capybara/apparition/page'
require 'json'
require 'time'

module Capybara::Apparition
  class Browser
    ERROR_MAPPINGS = {
      'Apparition.JavascriptError' => JavascriptError,
      'Apparition.FrameNotFound'   => FrameNotFound,
      'Apparition.InvalidSelector' => InvalidSelector,
      'Apparition.StatusFailError' => StatusFailError,
      'Apparition.NoSuchWindowError' => NoSuchWindowError,
      'Apparition.ScriptTimeoutError' => ScriptTimeoutError,
      'Apparition.UnsupportedFeature' => UnsupportedFeature,
      'Apparition.KeyError' => KeyError
    }.freeze

    attr_reader :client, :logger

    def initialize(client, logger = nil)
      @client = client
      @logger = logger
      # @current_page = Page.create(self, true, nil)
      # @pages = [@current_page]
      @current_page_handle = nil
      @targets = {}
      @context_id = nil

      # @client.on 'Runtime.executionContextCreated' do |params|
      #   puts "executionContextCreated: #{params}"
      #   context = params['context']
      #   if context && context['auxData']['isDefault']
      #     current_page.context_id = context['id']
      #   end
      # end

      @client.on 'Target.targetCreated' do |info|
        puts "Target Created Info: #{info}" if ENV['DEBUG']
        target_info = info['targetInfo']
        if !@targets.key?(target_info['targetId'])
          @targets[target_info['targetId']] = DevToolsProtocol::Target.new(self, target_info)
          puts "**** Target Added #{info}" if ENV['DEBUG']
        elsif ENV['DEBUG']
          puts "Target already existed #{info}"
        end
        @current_page_handle ||= target_info['targetId'] if target_info['type'] == 'page'
      end

      @client.on 'Target.targetDestroyed' do |info|
        puts "**** Target Destroyed Info: #{info}" if ENV['DEBUG']
        @targets.delete(info['targetId'])
      end

      @client.on 'Target.targetInfoChanged' do |info|
        puts "**** Target Info Changed: #{info}" if ENV['DEBUG']
        target_info = info['targetInfo']
        target = @targets[target_info['targetId']]
        target.info = target_info if target
      end

      command('Target.setDiscoverTargets', discover: true)
      # puts "discovering targets"
    end

    def restart
      puts 'handle client restart'
      # client.restart

      self.debug = @debug if defined?(@debug)
      self.js_errors = @js_errors if defined?(@js_errors)
      self.extensions = @extensions if @extensions
    end

    def visit(url)
      current_page.visit url
    end

    def current_url
      current_page.current_url
    end

    def status_code
      current_page.status_code
    end

    def body
      current_page.content
    end

    def source
      # command 'source'
    end

    def title
      # Updated info doesn't have correct title when changed programmatically
      # current_target.title
      current_page.title
    end

    def frame_title
      current_page.frame_title
    end

    def frame_url
      current_page.frame_url
    end

    def parents(page_id, id)
      # command 'parents', page_id, id
    end

    def find(method, selector)
      current_page.find(method, selector)
    end

    def find_within(page_id, id, method, selector)
      # command 'find_within', page_id, id, method, selector
    end

    def all_text(page_id, id)
      # command 'all_text', page_id, id
    end

    def visible_text(page_id, id)
      # command 'visible_text', page_id, id
    end

    def delete_text(page_id, id)
      # command 'delete_text', page_id, id
    end

    def property(page_id, id, name)
      # command 'property', page_id, id, name.to_s
    end

    def attributes(page_id, id)
      # command 'attributes', page_id, id
    end

    def attribute(page_id, id, name)
      # command 'attribute', page_id, id, name.to_s
    end

    def value(page_id, id)
      # command 'value', page_id, id
    end

    def set(page_id, id, value)
      # command 'set', page_id, id, value
    end

    def select_file(page_id, id, value)
      # command 'select_file', page_id, id, Array(value)
    end

    def tag_name(page_id, id)
      # command('tag_name', page_id, id).downcase
    end

    def visible?(page_id, id)
      # command 'visible', page_id, id
    end

    def disabled?(page_id, id)
      # command 'disabled', page_id, id
    end

    def click_coordinates(x, y)
      current_page.click_at(x, y)
    end

    def evaluate(script, *args)
      current_page.evaluate(script, *args)
    end

    def evaluate_async(script, wait_time, *args)
      current_page.evaluate_async(script, wait_time, *args)
    end

    def execute(script, *args)
      current_page.execute(script, *args)
    end

    def switch_to_frame(frame)
      case frame
      when Capybara::Node::Base
        current_page.push_frame(frame)
      when :parent
        current_page.pop_frame
      when :top
        current_page.pop_frame(top: true)
      end
    end

    def window_handle
      # sleep 1
      @current_page_handle
    end

    def window_handles
      @targets.map { |_id, target| (target.info['type'] == 'page' && target.id) || nil }.compact
    end

    def switch_to_window(handle)
      target = @targets[handle]
      raise NoSuchWindowError unless target&.page

      @current_page_handle = handle
    end

    def open_new_window
      info = command('Target.createTarget', url: 'about:blank', browserContextId: @context_id)
      # info = command('Target.createTarget', url: 'about:blank')
      @targets[info['targetId']] = ::Capybara::Apparition::DevToolsProtocol::Target.new(self, info.merge('type' => 'page'))
      info['targetId']
    end

    def close_window(handle)
      @targets.delete(handle)
      @current_page_handle = nil if @current_page_handle == handle
      res = command('Target.closeTarget', targetId: handle)
      res
    end

    def within_window(locator)
      original = window_handle
      handle = find_window_handle(locator)
      switch_to_window(handle)
      yield
    ensure
      switch_to_window(original)
    end

    def reset
      # def reset
      #   if @page
      #     @page.close
      #     @browser.command("Target.disposeBrowserContext", browserContextId: @_context_id)
      #   end
      #
      #   @page = nil
      #   @targets = {}
      #   @_context_id = nil
      #

      #   @_context_id = @browser.command("Target.createBrowserContext")["browserContextId"]
      #   target_id = @browser.command("Target.createTarget", url: "about:blank", browserContextId: @_context_id)["targetId"]
      #   @page = Page.new(target_id, @browser, @logger)
      #   push(target_id, @page)
      # end

      # Close and open new window each time
      # @targets.each do |k,v|
      #   if v.page
      #     v.close
      #   end
      # end
      # command("Target.disposeBrowserContext", browserContextId: @context_id) if @context_id
      # @context_id = command('Target.createBrowserContext')['browserContextId']
      # open_new_window

      # command("Target.disposeBrowserContext", browserContextId: @context_id) if @context_id
      # @context_id = command("Target.createBrowserContext")['browserContextId']
      # open_new_window

      current_page.command('Storage.clearDataForOrigin', origin: current_page.current_url, storageTypes: 'all' )
      current_page.visit('about:blank')
      current_page.command('Network.clearBrowserCache')
      current_page.command('Network.clearBrowserCookies')
      current_page.reset

      true
    end

    def scroll_to(left, top)
      current_page.scroll_to(left, top)
    end

    def render(path, options = {})
      check_render_options!(options)
      options[:full] = !!options[:full]
      img_data = current_page.render(options)
      File.open(path, 'wb') { |f| f.write(Base64.decode64(img_data)) }
    end

    def render_base64(_format, options = {})
      check_render_options!(options)
      options[:full] = !!options[:full]
      current_page.render(options)
    end

    # def set_zoom_factor(zoom_factor)
    #   command 'set_zoom_factor', zoom_factor
    # end

    def set_paper_size(size)
      # command 'set_paper_size', size
    end

    def resize(width, height)
      current_page.set_viewport width: width, height: height
    end

    def fullscreen
      current_page.fullscreen
    end

    def maximize
      current_page.maximize
    end

    def network_traffic(type = nil)
      case type
      when :blocked
        current_page.network_traffic.select(&:blocked?)
      else
        current_page.network_traffic
      end

      # command('network_traffic', type).map do |event|
      #   NetworkTraffic::Request.new(
      #     event['request'],
      #     (event['responseParts'] || []).map do |response|
      #       NetworkTraffic::Response.new(response)
      #     end,
      #     event['error'] ? NetworkTraffic::Error.new(event['error']) : nil
      #   )
      # end
    end

    def clear_network_traffic
      current_page.clear_network_traffic
    end

    def set_proxy(ip, port, type, user, password)
      args = [ip, port, type]
      args << user if user
      args << password if password
      # command('set_proxy', *args)
    end

    def equals(page_id, id, other_id)
      # command('equals', page_id, id, other_id)
    end

    def get_headers
      current_page.extra_headers
    end

    def set_headers(headers)
      current_page.extra_headers = headers
      update_headers
    end

    def add_headers(headers)
      current_page.extra_headers.merge! headers
      update_headers
    end

    def add_header(header, _options = {})
      # TODO: handle the options
      current_page.extra_headers.merge! header
      update_headers
    end

    def response_headers
      current_page.response_headers
    end

    def cookies
      current_page.command('Network.getCookies')['cookies'].each_with_object({}) do |c, h|
        h[c['name']] = Cookie.new(c)
      end
    end

    def set_cookie(cookie)
      if cookie[:expires]
        # cookie[:expires] = cookie[:expires].to_i * 1000
        cookie[:expires] = cookie[:expires].to_i
      end

      current_page.command('Network.setCookie', cookie)
    end

    def remove_cookie(name)
      current_page.command('Network.deleteCookies', name: name, url: current_url)
    end

    def clear_cookies
      current_page.command('Network.clearBrowserCookies')
    end

    def cookies_enabled=(flag)
      # command 'cookies_enabled', !!flag
    end

    def set_http_auth(user = nil, password = nil)
      current_page.credentials = if user.nil? && password.nil?
        nil
      else
        { username: user, password: password }
      end
    end

    attr_writer :js_errors

    def extensions=(filenames)
      @extensions = filenames
      Array(filenames).each do |name|
        begin
          current_page.command('Page.addScriptToEvaluateOnNewDocument', source: File.read(name))
        rescue Errno::ENOENT
          raise ::Capybara::Apparition::BrowserError.new('name' => "Unable to load extension: #{name}", 'args' => nil)
        end
      end
    end

    def url_whitelist=(whitelist)
      current_page.url_whitelist = whitelist
    end

    def url_blacklist=(blacklist)
      current_page.url_blacklist = blacklist
    end

    attr_writer :debug

    def clear_memory_cache
      # command 'clear_memory_cache'
    end

    def command(name, params = {})
      cmd = Command.new(name, params)
      log cmd.message

      response = client.send_cmd(name, params)
      log response

      raise Capybara::Apparition::ObsoleteNode.new(nil, nil) unless response

      if response['error']
        klass = ERROR_MAPPINGS[response['error']['name']] || BrowserError
        raise klass.new, response['error']
      else
        response
      end
    rescue DeadClient
      restart
      raise
    end

    def command_for_session(session_id, name, params = {})
      cmd = Command.new(name, params)
      log cmd.message

      # response = client.send(cmd)
      response = client.send_cmd_to_session(session_id, name, params)
      log response

      # raise Capybara::Apparition::ObsoleteNode.new(nil, nil) unless response

      if response&.fetch('error', nil)
        klass = ERROR_MAPPINGS[response['error']['name']] || BrowserError
        raise klass.new, response['error']
      else
        response
      end
    rescue DeadClient
      restart
      raise
    end

    def go_back
      current_page.go_back
    end

    def go_forward
      current_page.go_forward
    end

    def refresh
      current_page.refresh
    end

    def accept_alert
      current_page.add_modal(alert: true)
    end

    def accept_confirm
      current_page.add_modal(confirm: true)
    end

    def dismiss_confirm
      current_page.add_modal(confirm: false)
    end

    #
    # press "OK" with text (response) or default value
    #
    def accept_prompt(response)
      current_page.add_modal(prompt: response)
    end

    #
    # press "Cancel"
    #
    def dismiss_prompt
      current_page.add_modal(prompt: false)
    end

    def modal_message
      current_page.modal_messages.shift
    end

    def current_page
      current_target.page
    end

  private

    def update_headers
      if current_page.extra_headers['User-Agent']
        current_page.command('Network.setUserAgentOverride', userAgent: current_page.extra_headers['User-Agent'])
      end
      current_page.command('Network.setExtraHTTPHeaders', headers: current_page.extra_headers)
    end

    def current_target
      if @targets.key?(@current_page_handle)
        @targets[@current_page_handle]
      else
        @current_page_handle = nil
        raise NoSuchWindowError
      end
    end

    def log(message)
      logger&.puts message
    end

    def check_render_options!(options)
      return unless options[:full] && options.key?(:selector)

      warn "Ignoring :selector in #render since :full => true was given at #{caller(1..1)}"
      options.delete(:selector)
    end

    def find_window_handle(locator)
      return locator if window_handles.include? locator

      window_handles.each do |handle|
        switch_to_window(handle)
        return handle if evaluate('window.name') == locator
      end
      raise NoSuchWindowError
    end

    KEY_ALIASES = {
      command:   :Meta,
      equals:    :Equal,
      control:   :Control,
      ctrl:      :Control,
      multiply:  'numpad*',
      add:       'numpad+',
      divide:    'numpad/',
      subtract:  'numpad-',
      decimal:   'numpad.',
      left:      'ArrowLeft',
      right:     'ArrowRight',
      down:      'ArrowDown',
      up:        'ArrowUp'
    }.freeze

    def normalize_keys(keys)
      keys.map do |key_desc|
        case key_desc
        when Array
          # [:Shift, "s"] => { modifier: "shift", keys: "S" }
          # [:Shift, "string"] => { modifier: "shift", keys: "STRING" }
          # [:Ctrl, :Left] => { modifier: "ctrl", key: 'Left' }
          # [:Ctrl, :Shift, :Left] => { modifier: "ctrl,shift", key: 'Left' }
          # [:Ctrl, :Left, :Left] => { modifier: "ctrl", key: [:Left, :Left] }
          keys_chunks = key_desc.chunk { |k| k.is_a?(Symbol) && %w[shift ctrl control alt meta command].include?(k.to_s.downcase) }
          modifiers = if keys_chunks.peek[0]
            keys_chunks.next[1].map do |k|
              k = k.to_s.downcase
              k = 'control' if k == 'ctrl'
              k = 'meta' if k == 'command'
              k
            end.join(',')
          else
            ''
          end
          letters = normalize_keys(_keys.next[1].map { |k| k.is_a?(String) ? k.upcase : k })
          { modifier: modifiers, keys: letters }
        when Symbol
          if key_desc == :space
            res = ' '
          else
            key = KEY_ALIASES.fetch(key_desc.downcase, key_desc)
            if (match = key.to_s.match(/numpad(.)/))
              res = { keys: match[1], modifier: 'keypad' }
            elsif key !~ /^[A-Z]/
              key = key.to_s.split('_').map(&:capitalize).join
            end
          end
          res || { key: key }
        when String
          key_desc # Plain string, nothing to do
        end
      end
    end
  end
end
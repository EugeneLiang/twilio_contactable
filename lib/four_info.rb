gem 'haml'
require 'haml'
require 'net/http'

module FourInfo
  def self.mode;     @@mode ||= :live; end
  def self.mode=(m); @@mode = m;      end

  def self.numerize(numberish)
    numberish.to_s.scan(/\d+/).join
  end

  def self.internationalize(given_number)
    number = numerize(given_number)
    case number.size
    when 10
      "+1#{number}"
    when 11
      "+#{number}"
    when 12
      number =~ /\+\d(11)/ ? number : nil
    else
      nil
    end
  end

  Gateway = URI.parse 'http://gateway.4info.net/msg'

  module Contactable

    Attributes = [  :sms_phone_number,
                    :sms_confirmation_code,
                    :sms_confirmation_attempted,
                    :sms_confirmed ]

    def self.included(model)
      Attributes.each do |attribute|
        # add a method for setting or retrieving
        # which column should be used for which attribute
        # 
        # :sms_phone_number_column defaults to :sms_phone_number, etc.
        model.instance_eval "
          def #{attribute}_column(value = nil)
            @#{attribute}_column ||= :#{attribute}
            @#{attribute}_column = value if value
            @#{attribute}_column
          end
        "
        # provide a helper method to access the right value
        # no matter which column it's stored in
        #
        # e.g.: @user.four_info_sms_confirmed
        #       => @user.send(User.sms_confirmed_column)
        model.class_eval "
          def four_info_#{attribute}
            send self.class.#{attribute}_column
          end
          alias_method :four_info_#{attribute}?, :four_info_#{attribute}
        "
      end
    end

    def confirm_sms!
      Confirmation.new(four_info_sms_phone_number, self).try
    end
  end

  class Confirmation
    def initialize(number, contactable_record)
      @number = FourInfo.numerize(number)
      @contactable_record = contactable_record
    end

    def try
      return true  if @contactable_record.four_info_sms_confirmed?
      return false if @number.blank?

      response = Request.new.confirm(@number)
      if response.success?
        @contactable_record.sms_confirmation_code = response.confirmation_code
        @contactable_record.sms_confirmation_attempted = Time.now
        @contactable_record.save
      else
        raise "Confirmation Failed: #{response.inspect}"
      end
    end
  end

  class Request

    @@templates = Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), 'templates', '*.haml')))
    @@test_mode_config_file = File.join(File.dirname(__FILE__), '..', 'test', 'sms.yml')
    @@likely_config_files = [
        File.join(File.dirname(__FILE__), '..', 'sms.yml'),
        defined?(Rails) ? File.join(Rails.root, 'config', 'sms.yml') : '',
        File.join('config', 'sms.yml'),
        'sms.yml'
    ]

    attr_accessor :config
    attr_accessor :number

    def initialize
      config_file = :test == FourInfo.mode ?
                      @@test_mode_config_file :
                      @@likely_config_files.detect {|f| File.exist?(f) }

      raise "Missing config File! Please add sms.yml to ./config or the 4info directory" unless config_file

      @config = YAML.load(File.read(config_file))['4info'].with_indifferent_access
    end

    def confirm(number)
      self.number = FourInfo.internationalize(number)

      xml = template(:confirm).render(self)
      response = perform_confirm(xml)
      STDOUT.puts response.inspect
      response
    end

    def template(name)
      file = @@templates.detect {|t| File.basename(t).chomp('.haml').to_sym == name.to_sym }
      raise ArgumentError, "Missing 4Info template: #{name}" unless file
      Haml::Engine.new(File.read(file))
    end

    protected

      def perform_confirm(body)
        net = config[:proxy].blank? ?
                Net::HTTP :
                Net::HTTP::Proxy(*config[:proxy].split(":"))
        net.start(Gateway.host) do |http|
          http.post(body)
        end
      end
  end
end
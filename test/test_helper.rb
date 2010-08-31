require 'rubygems'
gem 'test-unit'
require 'test/unit'
require 'mocha'
require 'active_support'
require 'action_pack'
require 'active_record'
require 'active_support/test_case'
require 'shoulda'
require File.join(File.dirname(__FILE__), "..", 'lib', 'twilio_contactable')

# default test configuration
TwilioContactable.configure do |config|
  config.client_id  = '1'
  config.client_key = 'ABCDEF'
  config.default_from_phone_number = '1 (206) 867-5309'
end

TwilioContactable.mode = :test
config = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
require 'logger'
ActiveRecord::Base.logger = Logger.new(File.dirname(__FILE__) + "/debug.log")
ActiveRecord::Base.establish_connection(config[ENV['DB'] || 'sqlite3'])

ActiveRecord::Schema.define(:version => 1) do
  create_table :users do |t|
    t.column :phone_number,                 :string
    t.column :formatted_phone_number,       :string
    t.column :sms_blocked,                  :boolean
    t.column :sms_confirmation_code,        :string
    t.column :sms_confirmation_attempted,   :datetime
    t.column :sms_confirmed_phone_number,   :string
    t.column :voice_blocked,                :boolean
    t.column :voice_confirmation_code,      :string
    t.column :voice_confirmation_attempted, :datetime
    t.column :voice_confirmed_phone_number, :string

    t.column :custom_column,                :string

    t.column :type, :string
  end
end

class User < ActiveRecord::Base
  include TwilioContactable::Contactable
end

# kill all network access
module TwilioContactable
  module Gateway
    def post
      raise "You forgot to stub out your net requests!"
    end
  end
end

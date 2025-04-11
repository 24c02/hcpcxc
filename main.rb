require 'sinatra'
require 'faraday'
require 'faker'
require 'active_support/inflector'
require 'active_support/core_ext/string'

def hit_ip_dot(ip)
    @ip_conn ||= Faraday.new(url: "https://ip.hackclub.com/ip") do |c|
        c.response :raise_error
        c.response :json, parser_options: { symbolize_names: true }
        c.adapter Faraday.default_adapter
        c.options.timeout = 2
    end

    @ip_conn.get(ip).body
end

def ipfo(field, default)
    @ip&.[](field) || default
end

get '/' do
    @count = 0 # TODO: make this an actual number
    @ip = begin
        hit_ip_dot(request.ip)
    rescue
        {}
    end

    @street = Faker::Address.street_address
    erb :index
end
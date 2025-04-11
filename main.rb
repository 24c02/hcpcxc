require 'sinatra'
require 'faraday'
require 'faker'
require 'active_support/inflector'
require 'active_support/core_ext/string'
require 'securerandom'
require 'json'
require 'norairrecord'

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

before do
    @count = 0 # TODO: make this an actual number
end

get '/' do
    @ip = begin
        hit_ip_dot(request.ip)
    rescue
        {}
    end

    @street = Faker::Address.street_address
    erb :index
end

def slack_authorize_url(redirect_uri)
  params = {
    client_id: ENV["SLACK_CLIENT_ID"],
    redirect_uri: redirect_uri,
    state: SecureRandom.hex(24),
    user_scope: "users.profile:read,users:read,users:read.email"
  }

  URI.parse("https://slack.com/oauth/v2/authorize?#{params.to_query}")
end

def handle_slack_token(code, redirect_uri)
  response = Faraday.post("https://slack.com/api/oauth.v2.access") do |req|
    req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
    req.body = {
      client_id: ENV["SLACK_CLIENT_ID"],
      client_secret: ENV["SLACK_CLIENT_SECRET"],
      code: code,
      redirect_uri: redirect_uri
    }.to_query
  end

  data = JSON.parse(response.body)
  return nil unless data["ok"]

  user_response = Faraday.get("https://slack.com/api/users.info") do |req|
    req.headers['Authorization'] = "Bearer #{data['authed_user']['access_token']}"
    req.params = { user: data['authed_user']['id'] }
  end

  user_data = JSON.parse(user_response.body)
  return nil unless user_data["ok"]

  Norairrecord.table(ENV["AIRTABLE_PAT"], "appshKVhuW5Wcurir", "tblPSdTvQWOSva7dQ").upsert({"slack_id" => user_data["authed_user"]["id"]}, %w(slack_id))
  
end

get '/optout' do
  redirect_uri = "https://hcpcxc.hackclub.com/optout/callback"
  redirect slack_authorize_url(redirect_uri).to_s
end

get '/optout/callback' do
  if params[:error]
    @error = params[:error]
    erb :optout_error
  else
    email = handle_slack_token(params[:code], "https://hcpcxc.hackclub.com/optout/callback")
    if email
      @email = email
      erb :optout_success
    else
      @error = "slack auth failed"
      erb :optout_error
    end
  end
end


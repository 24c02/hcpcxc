require 'sinatra'
require 'sinatra/contrib'

require 'faraday'
require 'faker'
require 'active_support/inflector'
require 'active_support/core_ext/string'
require 'securerandom'
require 'json'
require_relative './models'

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
    MasterRollup.refresh
    @count = MasterRollup["mailed_postcards_count"] + MasterRollup["hand_delivered_count"]
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

def slack_authorize_url(redirect_uri, state)
  params = {
    client_id: ENV["SLACK_CLIENT_ID"],
    redirect_uri: redirect_uri,
    state: state,
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

  user_data["user"]
end

# get '/optout' do
#   erb :optout
# end

# post '/optout' do
#   redirect slack_authorize_url(ENV["SLACK_REDIRECT_URL"], "optout").to_s
# end

get '/login' do
  redirect slack_authorize_url(ENV["SLACK_REDIRECT_URL"], "me").to_s
end

get '/slack/callback' do
    case params[:state]
    # when "optout"
    #   user_data = handle_slack_token(params[:code], ENV["SLACK_REDIRECT_URL"])

    #   if user_data
    #     OptOut.upsert({"slack_id" => user_data["id"]}, %w(slack_id))
    #     erb :optout_success
    #   else
    #     @error = "slack auth failed"
    #     erb :optout_error
    #   end
    when "me"
      user_data = handle_slack_token(params[:code], ENV["SLACK_REDIRECT_URL"])

      if user_data
        person = Person.find_or_create_by_slack_id(user_data["id"])
        redirect "/me/#{person["rndK"]}"
      else
        @error = "couldn't sign you in..?"
        erb :error
      end
        else
      @error = "what are you trying to do?"
      erb :error
    end
end

helpers do
  def set_person
    raise "seems like you're missing something..." unless params[:rndK]
    @person = Person.by_rndK(params[:rndK])
    raise "just what are you trying to pull, buster?" unless @person
  end
end

before '/me/:rndK*' do
  set_person
end

get '/me/:rndK' do
  erb :me
end

post '/me/:rndK' do
  if params[:opt]
  case params[:opt]
    when "in"
      @person["status"] = "opted_in"
      @flash = "you're in!"
      @person.refresh_loops_address
      @person.save
    when "out"
      @flash = "....okay, then"
      @person["status"] = "opted_out"
      @person.save
    else
      raise "what are you trying to do?"
    end
  end
  erb :me
end
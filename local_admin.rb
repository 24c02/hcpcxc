require 'sinatra'
require 'dotenv/load'

require_relative './models'

get '/' do
    erb :admin, layout: :layout_admin
end

get '/create_postcard' do
    erb :admin_new_postcard, layout: :layout_admin
end

post '/create_postcard' do
    person = Person.find_or_create_by_slack_id(params[:slack_id])

    if person.opted_out?
        @flash = "<a href='#{person.airtable_url}'>recipient</a> is opted out"
        return erb :admin_new_postcard, layout: :layout_admin
    end

    hit_user_up(person) if person.first_time?

    postcard = Postcard.new(
        "recipient" => [person.id],
        "master_rollup" => %w(reccyROQ0Cv8hZeUO),
        "private_sender_info" => params[:sender_info]
    )
    postcard.save
    @flash = "postcard created"
    erb :admin_new_postcard, layout: :layout_admin
end

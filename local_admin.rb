require "sinatra"
require "dotenv/load"
require "active_support"
require "active_support/core_ext/enumerable"
require "csv"
require_relative "./models"
require "faraday"

get "/" do
  erb :admin, layout: :layout_admin
end

get "/create_postcard" do
  erb :admin_new_postcard, layout: :layout_admin
end

post "/create_postcard" do
  person = Person.find_or_create_by_slack_id(params[:slack_id].upcase)

  if person.opted_out?
    @flash = "<a href='#{person.airtable_url}'>recipient</a> is opted out"
    return erb :admin_new_postcard, layout: :layout_admin
  end

  hit_user_up(person) if person.first_time?

  postcard = Postcard.new(
    "recipient" => [person.id],
    "master_rollup" => %w(reccyROQ0Cv8hZeUO),
    "private_sender_info" => params[:sender_info],
    "status" => person.first_time? ? "pending_opt_in" : "awaiting_mailout",
  )
  postcard.save
  @flash = "<a href='#{postcard.airtable_url}'>postcard</a> (##{postcard["id"]}) created"
  erb :admin_new_postcard, layout: :layout_admin
end

def create_card_in_theseus(**details)
  conn = Faraday.new(url: "https://mail.hackclub.com") do |f|
    f.request :json
    f.response :json
    f.response :raise_error
    f.response :logger
  end

  response = conn.post("/api/v1/letter_queues/hcpcxc") do |req|
    req.headers["Authorization"] = "Bearer #{ENV["THESEUS_API_KEY"]}"
    req.body = details
  end

  response.success?
end

post "/queue-postcards" do
  pending = Postcard.where("status = 'awaiting_mailout'", sort: { created_at: :asc })
  recipient_ids = pending.map { |card| card["recipient"]&.first }.compact
  recipients = Person.find_many(recipient_ids).index_by(&:id)

  pending.each do |card|
    recipient = recipients[card["recipient"]&.first]

    addy = JSON.parse(recipient["address_json"])
    create_card_in_theseus(
      recipient_email: recipient["email"],
      address: {
        first_name: addy["first_name"],
        last_name: addy["last_name"],
        line_1: addy["line_1"],
        line_2: addy["line_2"],
        city: addy["city"],
        state: addy["state"],
        postal_code: addy["postal_code"],
        country: addy["country"],
      }.compact,
      rubber_stamps: "hcpcxc ##{card["id"]}",
      idempotency_key: "hcpcxc_airtable_record_#{card.id}",
    )
  end

  @flash = "all pending letters queued!"
  redirect "/"
end

get "/generate-csv" do
  pending = Postcard.where("status = 'awaiting_mailout'", sort: { created_at: :asc })
  # the things we do to avoid n+1s
  recipient_ids = pending.map { |card| card["recipient"]&.first }.compact
  recipients = Person.find_many(recipient_ids).index_by(&:id)
  csv = CSV.generate do |csv|
    csv << ["email", "firstName", "lastName", "addressLine1", "addressLine2", "addressCity", "addressState", "addressZip", "addressCountry", "rubber_stamps"]

    pending.each do |card|
      recipient = recipients[card["recipient"]&.first]

      addy = JSON.parse(recipient["address_json"])
      csv << [
        recipient["email"],
        addy["first_name"],
        addy["last_name"],
        addy["line_1"],
        addy["line_2"],
        addy["city"],
        addy["state"],
        addy["postal_code"],
        addy["country"],
        "hcpcxc ##{card["id"]}",
      ]
    end
  end
  content_type "text/csv"
  attachment "postcards.csv"
  csv
end

post "/mark-mailed" do
  pending = Postcard.where("status = 'awaiting_mailout'")
  pending.each { |p| p["status"] = "mailed" }
  Postcard.batch_save(pending)
  @flash = "all pending letters marked as mailed!"
  redirect "/"
end

require 'faraday'

def send_slack_message(channel, msg)
  response = Faraday.post("https://slack.com/api/chat.postMessage") do |req|
    req.headers['Authorization'] = "Bearer #{ENV['SLACK_BOT_TOKEN']}"
    req.headers['Content-Type'] = 'application/json'
    req.body = {
      channel: channel,
      text: msg
    }.to_json
  end

  JSON.parse(response.body)
end

def tell_nora(msg)
  send_slack_message("U06QK6AG3RD", msg)
end

def hit_user_up(person)
    msg = <<~MSG
    hey! someone's trying to send you a postcard!
    the address we have on file for you is:
    #{person.formatted_address}
    if that's wrong, before you do anything else, please update your address here:
    https://forms.hackclub.com/update-address
    (plz use #{person["email"]} as the email)
    if you're cool with getting a postcard, click the link below to confirm:
    https://hcpcxc.hackclub.com#{person.build_rndk_url}
    if you're not cool with that, still click the link and opt out (or just ignore this message, i guess)
    MSG
    
    send_slack_message(person["slack_id"], msg)
end
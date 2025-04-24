require_relative "./models"

class FakeSlackModel
    attr_accessor :slack_response

    def self.find_by_slack_id(slack_id)
        response = Faraday.get("https://slack.com/api/users.info") do |req|
            req.headers['Authorization'] = "Bearer #{ENV['SLACK_BOT_TOKEN']}"
            req.params = { user: slack_id }
        end

        data = JSON.parse(response.body)

        raise "no slack??" unless data["ok"]

        new.tap { |instance| instance.slack_response = data["user"] }
    end

    def email
        slack_response["profile"]["email"]
    end
end

def find_plausible_emails(slack_id)
    [HighSeasPerson, YSWSVerfUser, FakeSlackModel].map do |model|
        model.find_by_slack_id(slack_id)&.email
    end.compact.uniq
end

def pull_loops_record(email)
    response = Faraday.get("https://app.loops.so/api/v1/contacts/find") do |req|
        req.headers['Authorization'] = "Bearer #{ENV['LOOPS_API_KEY']}"
        req.params = { email: email }
    end

    raise response.body unless response.success?

    data = JSON.parse(response.body)
    return nil if data.empty?

    data.first
end

def find_first_loops_record(emails)
    emails.each do |email|
        record = pull_loops_record(email)
        return record if record
    end
    nil
end

def loops_address_json(loops_record)
    {
        first_name: loops_record["firstName"],
        last_name: loops_record["lastName"],
        line_1: loops_record["addressLine1"],
        line_2: loops_record["addressLine2"],
        city: loops_record["addressCity"],
        state: loops_record["addressState"],
        postal_code: loops_record["addressZipCode"],
        country: loops_record["addressCountry"]
    }.compact.to_json
end
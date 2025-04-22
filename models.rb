require 'norairrecord'
require 'securerandom'
require 'json'

require_relative './slack'
require_relative './databroker'

Norairrecord.api_key = ENV["AIRTABLE_PAT"]

# fields: ["slack_id"]
class OptOut < Norairrecord::Table
    self.base_key = "appshKVhuW5Wcurir"
    self.table_name = "tblPSdTvQWOSva7dQ"
end

# fields: slackid name opted_in? 
class Person < Norairrecord::Table
    self.base_key = "appshKVhuW5Wcurir"
    self.table_name = "tbl4XtI921GIQfXY7"

    has_many :fk_postcards, class: "Postcard", column: "postcards"

    def postcards
        @postcards ||= fk_postcards
    end

    def build_rndk_url
        "/me/#{fields["rndK"]}"
    end

    def opted_out?
        fields["status"] == "opted_out"
    end

    def first_time?
        fields["status"] == "dunno_yet"
    end

    def refresh_loops_address
        adu = AddressUpdate.find_by_email(fields["email"])
        self["address_json"] = if adu
            adu.address_json
        else
            loops_record = pull_loops_record(fields["email"])
            loops_record ? loops_address_json(loops_record) : nil
        end
    end

    def refresh_loops_address!
        refresh_loops_address
        save
    end

    def formatted_address
        a = JSON.parse(fields["address_json"])
        <<~EOT
        #{a["line_1"]}
        #{a["line_2"]}
        #{a["city"]}, #{a["state"]} #{a["postal_code"]}
        #{a["country"]}
        EOT
    end

    class << self

        def by_rndK(rndK)
            first_where("rndK='#{rndK}'")
        end

        def find_or_create_by_slack_id(slack_id)
            person = first_where("slack_id='#{slack_id}'")
            return person if person

            plausible_emails = find_plausible_emails(slack_id)
            loops_record = find_first_loops_record(plausible_emails)

            person = new(
                {
                    "slack_id" => slack_id,
                    "email" => loops_record ? loops_record["email"] : plausible_emails.first,
                    "rndK" => "key_#{SecureRandom.urlsafe_base64(16)}",
                    "loops_id" => loops_record ? loops_record["id"] : nil,
                    "address_json" => loops_record ? loops_address_json(loops_record) : nil,
                    status: "dunno_yet"
                }.compact
            )

            person.save
            
            unless loops_record
                tell_nora <<~EOM
                hey! i think you gotta track this person down by hand:
                #{person.fields["slack_id"]}
                #{plausible_emails.join(", ")}
                #{person.airtable_url}
                EOM
            end

            person
        end
    end
end

class Postcard < Norairrecord::Table
    self.base_key = "appshKVhuW5Wcurir"
    self.table_name = "tblEMdJqt1dGbql4x"

    has_one :person, class: "Person", column: "person"
end
    

class MasterRollup < Norairrecord::Table
    self.base_key = "appshKVhuW5Wcurir"
    self.table_name = "tblvC2aZViClxupDM"

    class << self
        def record
            @rec ||= find "reccyROQ0Cv8hZeUO" 
        end

        def refresh
            @rec = find "reccyROQ0Cv8hZeUO" 
        end

        def [](field)
            record[field]
        end
    end
end

# ---- these are just for slack ID -> possible loops email, dw ----

class HighSeasPerson < Norairrecord::Table
    self.base_key = "appTeNFYcUiYfGcR6"
    self.table_name = "tblfTzYVqvDJlIYUB"
    
    
    def self.find_by_slack_id(slack_id)
        first_where("slack_id='#{slack_id}'")
    end

    def email
        fields["email"]
    end
end

class YSWSVerfUser < Norairrecord::Table
    self.base_key = "appre1xwKlj49p0d4"
    self.table_name = "tbl2Q2aCWqyBGi9mj"

    def self.find_by_slack_id(slack_id)
        first_where("{Hack Club Slack ID}='#{slack_id}'")
    end

    def email
        fields["Email"]
    end
end

class AddressUpdate < Norairrecord::Table
    self.base_key = "app33qYiJZBIJXQKk"
    self.table_name = "tblv0x97vPm0in8fD"

    def self.find_by_email(email)
        first_where("AND(Email='#{email}', DATETIME_DIFF({Update Submitted At}, NOW(), 'hours') < 3)", sort: {"Update Submitted At" => "desc"})
    end

    def address_json
        {
            first_name: fields["First Name"],
            last_name: fields["Last Name"],
            line_1: fields["Address (Line 1)"],
            line_2: fields["Address (Line 2)"],
            city: fields["City"],
            state: fields["State"],
            postal_code: fields["ZIP"],
            country: fields["Country"]
        }.compact.to_json
    end
end
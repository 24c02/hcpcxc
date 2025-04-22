require_relative '../models'

OptOut.all.each do |optout|
    person = Person.find_or_create_by_slack_id(optout.fields["slack_id"])
    person["status"] = "opted_out"
    person.save
end
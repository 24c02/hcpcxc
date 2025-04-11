FROM ruby:3.3.6

WORKDIR /sidequests
COPY Gemfile Gemfile.lock /sidequests/
RUN bundle install

COPY . /sidequests

CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "-p", "4567"]

EXPOSE 4567
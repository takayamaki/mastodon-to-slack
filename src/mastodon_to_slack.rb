# frozen_string_literal: true

require 'bundler/setup'
require 'net/https'

Bundler.require
Dotenv.load

MASTODON_API_VERSION = 'v1'
MASTODON_TIMELINE    = 'user'
MASTODON_ENDPOINT    = "wss://#{ENV['MASTODON_INSTANCE_HOST']}"        \
                       "/api/#{MASTODON_API_VERSION}/streaming"        \
                       "?access_token=#{ENV['MASTODON_ACCESS_TOKEN']}" \
                       "&stream=#{MASTODON_TIMELINE}"
SLACK_WEBHOOK_URI    = URI.parse(ENV['SLACK_WEBHOOK_URI'])

request      = Net::HTTP::Post.new(SLACK_WEBHOOK_URI.request_uri)
http         = Net::HTTP.new(SLACK_WEBHOOK_URI.host, SLACK_WEBHOOK_URI.port)
http.use_ssl = true

def build_slack_text(payload)
  mastodon_status_uri = payload.dig('url')
  if payload.dig('reblogged')
    "#{payload.dig('account', 'acct')} boosted: #{mastodon_status_uri}"
  else
    mastodon_status_uri
  end
end

def post_to_slack(payload)
  request.body = {
    text: build_slack_text(payload),
    unfurl_links: true
  }.to_json

  http.start do |h|
    h.request(request)
  end
end

EM.run do
  ws = Faye::WebSocket::Client.new(MASTODON_ENDPOINT)

  ws.on :open do |_|
    puts 'Connection starts'
  end

  ws.on :error do |_|
    puts 'Error occured'
  end

  ws.on :close do |_|
    puts 'Connection closed'
  end

  ws.on :message do |message|
    response = JSON.parse(message.data)

    if response.dig('event') == 'update'
      payload = JSON.parse(response.dig('payload'))

      if payload.dig('account', 'acct') == ENV['MASTODON_USERNAME']
        post_to_slack(payload) if payload.dig('visibility') == 'public'
      end
    end
  end
end

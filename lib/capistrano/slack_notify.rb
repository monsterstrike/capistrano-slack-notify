require 'capistrano'
require 'json'
require 'net/http'

module Capistrano
  module SlackNotify
    HEX_COLORS = {
      :grey  => '#CCCCCC',
      :red   => '#BB0000',
      :green => '#7CD197',
      :blue  => '#103FFB'
    }

    def post_to_channel(color, message)
      if use_color?
        call_slack_api(attachment_payload(color, message))
      else
        call_slack_api(regular_payload(message))
      end
    end

    def call_slack_api(payload)
      uri = URI.parse(slack_webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      request = Net::HTTP::Post.new(uri.request_uri)
      request.set_form_data(:payload => payload)
      http.request(request)
    rescue SocketError => e
       puts "#{e.message} or slack may be down"
    end

    def regular_payload(announcement)
      {
        'channel'    => slack_channel,
        'username'   => slack_username,
        'text'       => announcement,
        'icon_emoji' => slack_emoji,
        'mrkdwn'     => true
      }.to_json
    end

    def attachment_payload(color, announcement)
      {
        'channel'     => slack_channel,
        'username'    => slack_username,
        'icon_emoji'  => slack_emoji,
        'attachments' => [{
          'fallback'  => announcement,
          'text'      => announcement,
          'color'     => HEX_COLORS[color],
          'mrkdwn_in' => %w{text}
        }]
      }.to_json
    end

    def use_color?
      fetch(:slack_color, true)
    end

    def slack_webhook_url
      fetch(:slack_webhook_url)
    end

    def slack_channel
      fetch(:slack_room, '#platform')
    end

    def slack_username
      fetch(:slack_username, 'capistrano')
    end

    def slack_emoji
      fetch(:slack_emoji, ':rocket:')
    end

    def slack_app_name
      fetch(:slack_app_name, fetch(:application))
    end

    def slack_deployer
      fetch(:deployer)
    end

    def slack_stage
      fetch(:stage, 'development')
    end

    def slack_destination
      fetch(:slack_destination, slack_stage)
    end

    def slack_repository
      fetch(:repository, 'origin')
    end

    def slack_deploy_target
      [slack_app_name, branch].join('/')
    end

    def self.extended(configuration)
      configuration.load do
        # Add the default hooks by default.
        set :deployer do
          ENV['USER']
        end

        namespace :slack do
          desc "Notify Slack that the deploy has started."
          task :starting do
            revision = if real_revision
                         " (revision #{real_revision[0..7]})"
                       else
                         ""
                       end
            post_to_channel(:grey, "#{slack_deployer} is deploying #{slack_deploy_target} #{revision} to #{slack_destination}")
            set(:start_time, Time.now)
          end

          desc "Notify Slack that the deploy has completed successfully."
          task :finished do
            msg = "#{slack_deployer} deployed #{slack_deploy_target} to #{slack_destination} *successfully*"

            if start_time = fetch(:start_time, nil)
              msg << " in #{Time.now.to_i - start_time.to_i} seconds."
            else
              msg << "."
            end

            post_to_channel(:green, msg)
          end

          desc "Notify Slack that the deploy failed."
          task :failed do
            post_to_channel(:red, "#{slack_deployer} *failed* to deploy #{slack_deploy_target} to #{slack_destination}")
          end
        end # end namespace :slack
      end
    end # end self.extended

  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::SlackNotify)
end

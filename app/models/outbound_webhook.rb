# frozen_string_literal: true

require 'faraday'

class OutboundWebhook < ActiveRecord::Base
  has_soft_deletion default_scope: true

  belongs_to :project
  belongs_to :stage

  validates :url, uniqueness: {
    scope: :stage_id,
    conditions: -> { where("deleted_at IS NULL") },
    message: "one webhook per (stage, url) combination."
  }
  validate :url_is_not_relative
  validates_presence_of :username, if: proc { |outbound_webhook| outbound_webhook.password.present? }
  validates_presence_of :password, if: proc { |outbound_webhook| outbound_webhook.username.present? }

  def deliver(deploy)
    Rails.logger.info "Sending webhook notification to #{url}. Deploy: #{deploy.id}"

    response = connection.post do |req|
      req.headers['Content-Type'] = 'application/json'
      req.body = DeploySerializer.new(deploy).to_json
    end

    if response.success?
      Rails.logger.info "Webhook notification sent. Deploy: #{deploy.id}"
    else
      Rails.logger.error "Failed to send webhook notification. Deploy: #{deploy.id} Response: #{response.inspect}"
    end

    response.success?
  end

  private

  def connection
    Faraday.new(url: url) do |faraday|
      faraday.request  :url_encoded
      faraday.response :logger
      faraday.adapter  Faraday.default_adapter
      faraday.basic_auth(username, password) if username.present?
    end
  end

  def url_is_not_relative
    errors.add(:url, "must begin with http:// or https://") unless url.start_with?("http://", "https://")
  end
end

class DiscordController < ApplicationController
  DISCORD_API_BASE = "https://discord.com/api/v10"

  def create_forum_post
    channel_id = params.require(:channel_id)
    title = params.require(:title)
    content = params.require(:content)
    tag_names = params[:tags] || []

    body = { name: title, message: { content: content } }
    body[:applied_tags] = resolve_tag_ids(channel_id, tag_names) if tag_names.any?

    response = discord_request(:post, "channels/#{channel_id}/threads", body)
    data = JSON.parse(response.body)

    if response.status == 201
      render json: { ok: true, thread_id: data["id"] }
    else
      render json: { ok: false, error: data }, status: response.status
    end
  end

  def delete_forum_post
    thread_id = params.require(:thread_id)

    response = discord_request(:delete, "channels/#{thread_id}")

    if response.status == 200
      render json: { ok: true }
    else
      render json: { ok: false, error: JSON.parse(response.body) }, status: response.status
    end
  rescue ActionController::ParameterMissing => e
    render json: { ok: false, error: e.message }, status: :bad_request
  end

  def update_forum_post
    channel_id = params.require(:channel_id)
    thread_id = params.require(:thread_id)
    tag_names = params[:tags] || []
    comment = params[:content]

    if tag_names.any?
      applied_tags = resolve_tag_ids(channel_id, tag_names)
      discord_request(:patch, "channels/#{thread_id}", { applied_tags: applied_tags })
    end

    if comment.present?
      discord_request(:post, "channels/#{thread_id}/messages", { content: comment })
    end

    render json: { ok: true }
  rescue ActionController::ParameterMissing => e
    render json: { ok: false, error: e.message }, status: :bad_request
  rescue => e
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  private

  def resolve_tag_ids(channel_id, tag_names)
    response = discord_request(:get, "channels/#{channel_id}")
    available_tags = JSON.parse(response.body)["available_tags"] || []

    tag_names.filter_map do |name|
      available_tags.find { |t| t["name"].casecmp?(name) }&.dig("id")
    end
  end

  def discord_request(method, path, body = nil)
    conn = Faraday.new(DISCORD_API_BASE) do |f|
      f.headers["Authorization"] = "Bot #{ENV["DISCORD_BOT_TOKEN"]}"
      f.headers["Content-Type"] = "application/json"
    end

    body ? conn.send(method, path, body.to_json) : conn.send(method, path)
  end
end

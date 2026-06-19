require "zlib"

class DiscordController < ApplicationController
  DISCORD_API_BASE = "https://discord.com/api/v10"

  def create_forum_post
    channel_id = params.require(:channel_id)
    title = params.require(:title)
    content = params[:content].presence || title
    tag_names = params[:tags] || []

    # Advisory lock serializes concurrent requests for the same (channel_id, title)
    # so the find_by check and Discord POST are atomic from the perspective of other requests.
    lock_key = Zlib.crc32("#{channel_id}:#{title}")
    db = ActiveRecord::Base.connection
    db.execute("SELECT pg_advisory_lock(#{lock_key})")

    begin
      existing = ForumThread.find_by(channel_id: channel_id, title: title)
      return render json: { ok: true, thread_id: existing.thread_id } if existing

      body = { name: title, message: { content: content } }
      body[:applied_tags] = resolve_tag_ids(channel_id, tag_names) if tag_names.any?

      response = discord_request(:post, "channels/#{channel_id}/threads", body)
      data = JSON.parse(response.body)

      if response.success?
        ForumThread.create!(channel_id: channel_id, title: title, thread_id: data["id"])
        render json: { ok: true, thread_id: data["id"] }
      else
        render json: { ok: false, error: data }, status: response.status
      end
    ensure
      db.execute("SELECT pg_advisory_unlock(#{lock_key})")
    end
  end

  def delete_forum_post
    thread_id = params.require(:thread_id)

    response = discord_request(:delete, "channels/#{thread_id}")

    if response.success?
      ForumThread.find_by(thread_id: thread_id)&.destroy
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
    title = params[:title]

    patch_body = {}
    patch_body[:name] = title if title.present?
    patch_body[:applied_tags] = resolve_tag_ids(channel_id, tag_names) if tag_names.any?
    discord_request(:patch, "channels/#{thread_id}", patch_body) if patch_body.any?

    if comment.present?
      discord_request(:post, "channels/#{thread_id}/messages", { content: comment })
    end

    ForumThread.find_by(thread_id: thread_id)&.update(title: title) if title.present?

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
    body ? conn.send(method, path, body.to_json) : conn.send(method, path)
  end

  def conn
    @conn ||= Faraday.new(DISCORD_API_BASE) do |f|
      f.headers["Authorization"] = "Bot #{ENV["DISCORD_BOT_TOKEN"]}"
      f.headers["Content-Type"] = "application/json"
    end
  end
end

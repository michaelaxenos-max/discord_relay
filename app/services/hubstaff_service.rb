class HubstaffService
  class RateLimitError < StandardError; end
  BASE_URL  = "https://api.hubstaff.com/v2".freeze
  TOKEN_URL = "https://account.hubstaff.com/access_tokens".freeze

  FIXED_TASKS = [
    "Adset Launch (Scaling)",
    "Campaign Launch (Testing)",
    "Deep Research GPT",
    "Dispute Resolution",
    "Image (AI regen)",
    "Image (from scratch)",
    "Meta Asset Warmup",
    "Sourcing & Margin Calculation",
    "Video - 2min",
    "Video – 3 min",
    "Video – 4 min",
    "Video – 5 min",
    "Video – 6 min",
    "Video – 7 min",
    "Video – Script change",
    "Video – Scrollstopper",
    "Video – under 1 min"
  ].freeze

  DYNAMIC_TASKS = [
    "Advertorial",
    "Advertorial - reproduced",
    "Sales Page",
    "Sales Page - reproduced"
  ].freeze

  # Maps each task name to the team name responsible for it
  TASK_TEAM_MAP = {
    "Adset Launch (Scaling)"      => "Facebook Launcher",
    "Campaign Launch (Testing)"   => "Facebook Launcher",
    "Meta Asset Warmup"           => "Facebook Launcher",
    "Deep Research GPT"           => "Editor",
    "Image (AI regen)"            => "Editor",
    "Image (from scratch)"        => "Editor",
    "Video - 2min"                => "Editor",
    "Video – 3 min"               => "Editor",
    "Video – 4 min"               => "Editor",
    "Video – 5 min"               => "Editor",
    "Video – 6 min"               => "Editor",
    "Video – 7 min"               => "Editor",
    "Video – Script change"       => "Editor",
    "Video – Scrollstopper"       => "Editor",
    "Video – under 1 min"         => "Editor",
    "Dispute Resolution"          => "Customer Support",
    "Sourcing & Margin Calculation" => "Customer Support",
    "Advertorial"                 => "Funnel Builders",
    "Advertorial - reproduced"    => "Funnel Builders",
    "Sales Page"                  => "Funnel Builders",
    "Sales Page - reproduced"     => "Funnel Builders"
  }.freeze

  def initialize
    @refresh_token = ENV.fetch("HUBSTAFF_REFRESH_TOKEN")
    @org_id        = ENV.fetch("HUBSTAFF_ORG_ID")
  end

  def delete_project(project_id)
    response = conn.put("#{BASE_URL}/projects/#{project_id}") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
      req.headers["Content-Type"]  = "application/json"
      req.body = { status: "archived" }.to_json
    end
    unless response.success?
      raise "Hubstaff API error #{response.status}: #{response.body}"
    end
    true
  end

  def create_project_with_tasks(project_name:, dynamic_task: nil, hours: nil)
    if dynamic_task.present? && !DYNAMIC_TASKS.include?(dynamic_task)
      raise ArgumentError, "Invalid dynamic task: #{dynamic_task}. Must be one of: #{DYNAMIC_TASKS.join(', ')}"
    end

    all_member_ids = org_member_ids
    project_id     = create_project(project_name, all_member_ids)
    create_tasks(project_id, dynamic_task, hours)
    project_id
  end

  private

  def access_token
    Rails.cache.fetch("hubstaff_access_token", expires_in: 23.hours) do
      exchange_token
    end
  end

  def exchange_token
    response = Faraday.post(TOKEN_URL,
      "grant_type=refresh_token&refresh_token=#{@refresh_token}",
      "Content-Type" => "application/x-www-form-urlencoded"
    )
    unless response.success?
      raise "Hubstaff token exchange failed #{response.status}: #{response.body}"
    end
    JSON.parse(response.body).fetch("access_token")
  end

  def org_member_ids
    Rails.cache.fetch("hubstaff_org_members", expires_in: 1.hour) do
      resp = get("/organizations/#{@org_id}/members")
      resp.fetch("members", []).map { |m| m["user_id"] }
    end
  end

  def team_user_ids(team_name)
    Rails.cache.fetch("hubstaff_team_#{team_name}", expires_in: 1.hour) do
      teams = get("/organizations/#{@org_id}/teams").fetch("teams", [])
      team  = teams.find { |t| t["name"] == team_name }
      return [] unless team

      get("/teams/#{team['id']}/members").fetch("team_members", []).map { |m| m["user_id"] }
    end
  end

  MANAGER_USER_ID = 3517608 # Michael Xenos

  def create_project(name, member_ids)
    members = member_ids.map { |uid| { user_id: uid, role: uid == MANAGER_USER_ID ? "manager" : "member" } }
    response = post("/organizations/#{@org_id}/projects", { name: name, members: members })
    response.dig("project", "id") || raise("Failed to create project: #{response}")
  end

  def create_tasks(project_id, dynamic_task, hours)
    tasks = dynamic_task.present? ? FIXED_TASKS + [ dynamic_task ] : FIXED_TASKS + DYNAMIC_TASKS
    tasks.each do |task_name|
      payload = build_task_payload(task_name, dynamic_task, hours)
      post("/projects/#{project_id}/tasks", payload)
    end
  end

  def build_task_payload(task_name, dynamic_task, hours)
    team_name = TASK_TEAM_MAP[task_name]
    assignees = team_name ? team_user_ids(team_name) : []
    assignees = org_member_ids if assignees.empty?

    payload = { summary: task_name, assignee_ids: assignees }

    # Hours budget wired up for future use — only applied to the dynamic task
    if task_name == dynamic_task && hours.present?
      payload[:budget] = { hours: hours.to_f }
    end

    payload
  end

  def get(path)
    response = conn.get("#{BASE_URL}#{path}") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
    end
    handle_error!(response)
    response.body
  end

  def post(path, body)
    response = conn.post("#{BASE_URL}#{path}") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
      req.headers["Content-Type"]  = "application/json"
      req.body = body.to_json
    end
    handle_error!(response)
    response.body
  end

  def handle_error!(response)
    return if response.success?
    body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s) rescue {}
    raise RateLimitError, "Rate limit exceeded" if response.status == 429 || body["error_code"] == 13000
    raise "Hubstaff API error #{response.status}: #{response.body}"
  end

  def conn
    @conn ||= Faraday.new do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end
end

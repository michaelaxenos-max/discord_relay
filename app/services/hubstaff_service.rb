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
    "Adset Launch (Scaling)"        => "Facebook Launcher",
    "Campaign Launch (Testing)"     => "Facebook Launcher",
    "Meta Asset Warmup"             => "Facebook Launcher",
    "Deep Research GPT"             => "Editor",
    "Image (AI regen)"              => "Editor",
    "Image (from scratch)"          => "Editor",
    "Video - 2min"                  => "Editor",
    "Video – 3 min"                 => "Editor",
    "Video – 4 min"                 => "Editor",
    "Video – 5 min"                 => "Editor",
    "Video – 6 min"                 => "Editor",
    "Video – 7 min"                 => "Editor",
    "Video – Script change"         => "Editor",
    "Video – Scrollstopper"         => "Editor",
    "Video – under 1 min"           => "Editor",
    "Dispute Resolution"            => "Customer Support",
    "Sourcing & Margin Calculation" => "Customer Support",
    "Advertorial"                   => "Funnel Builders",
    "Advertorial - reproduced"      => "Funnel Builders",
    "Sales Page"                    => "Funnel Builders",
    "Sales Page - reproduced"       => "Funnel Builders"
  }.freeze

  MANAGER_USER_ID = 3517608 # Michael Xenos

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
    if dynamic_task.present? && !valid_dynamic_task?(dynamic_task)
      raise ArgumentError, "Invalid dynamic task: #{dynamic_task}. Must be one of: #{dynamic_task_names.join(', ')}"
    end

    all_member_ids = org_member_ids
    project_id     = create_project(project_name, all_member_ids)
    create_tasks(project_id, dynamic_task, hours)
    project_id
  end

  # --- Public methods for admin panel ---

  def org_members_with_users
    response = get_raw("/organizations/#{@org_id}/members?include=users")
    members  = response.fetch("members", [])
    users    = response.fetch("users", [])
    users_by_id = users.index_by { |u| u["id"] }
    members.map do |m|
      user = users_by_id[m["user_id"]] || {}
      {
        hubstaff_user_id: m["user_id"],
        name:             user["name"],
        email:            user["email"],
        membership_role:  m["membership_role"]
      }
    end
  end

  def org_teams
    get("/organizations/#{@org_id}/teams").fetch("teams", [])
  end

  def user_team_names(user_id)
    teams = org_teams
    teams.select { |t| team_member_ids(t["id"]).include?(user_id) }.map { |t| t["name"] }
  end

  def team_member_ids(team_id)
    get("/teams/#{team_id}/members").fetch("team_members", []).map { |m| m["user_id"] }
  end

  def add_member_to_project(project_id, user_id, role: "user")
    role = "manager" if user_id == MANAGER_USER_ID
    post("/projects/#{project_id}/members", { user_id: user_id, role: role })
  rescue => e
    Rails.logger.error "Failed to add user #{user_id} to project #{project_id}: #{e.message}"
  end

  def get_project_tasks(project_id)
    get("/projects/#{project_id}/tasks").fetch("tasks", [])
  rescue => e
    Rails.logger.error "Failed to get tasks for project #{project_id}: #{e.message}"
    []
  end

  def add_assignee_to_task(task_id, user_id)
    current = get("/tasks/#{task_id}").dig("task", "assignee_ids") || []
    return if current.include?(user_id)
    put("/tasks/#{task_id}", { assignee_ids: current + [user_id] })
  rescue => e
    Rails.logger.error "Failed to add assignee #{user_id} to task #{task_id}: #{e.message}"
  end

  def org_projects(status: "active")
    all_projects = []
    page_start_id = nil

    loop do
      path = "/organizations/#{@org_id}/projects?status=#{status}&page_limit=100"
      path += "&page_start_id=#{page_start_id}" if page_start_id
      projects = get(path).fetch("projects", [])
      all_projects.concat(projects)
      break if projects.size < 100
      page_start_id = projects.last["id"]
    end

    all_projects
  end

  def find_project_by_name(name)
    org_projects(status: "active").find { |p| p["name"].to_s.strip.downcase == name.to_s.strip.downcase }
  end

  def sync_tasks_to_project(project_id)
    existing_names = get_project_tasks(project_id).map { |t| t["summary"] }
    all_tasks      = build_task_list(nil)

    all_tasks.each do |task_name|
      next if existing_names.include?(task_name)
      payload = build_task_payload(task_name, nil, nil)
      post("/projects/#{project_id}/tasks", payload)
    end
  end

  def sync_task_assignees(project_id)
    tasks = get_project_tasks(project_id)
    tasks.each do |task|
      task_name = task["summary"]
      team_name = task_team_name_from_db(task_name) || TASK_TEAM_MAP[task_name]
      next unless team_name

      current_assignees = task["assignee_ids"] || []
      team_user_ids(team_name).each do |uid|
        next if current_assignees.include?(uid)
        add_assignee_to_task(task["id"], uid)
      end
    end
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

  def create_project(name, member_ids)
    members = member_ids.map { |uid| { user_id: uid, role: uid == MANAGER_USER_ID ? "manager" : "user" } }
    response = post("/organizations/#{@org_id}/projects", { name: name, members: members })
    response.dig("project", "id") || raise("Failed to create project: #{response}")
  end

  def create_tasks(project_id, dynamic_task, hours)
    tasks = build_task_list(dynamic_task)
    tasks.each do |task_name|
      payload = build_task_payload(task_name, dynamic_task, hours)
      post("/projects/#{project_id}/tasks", payload)
    end
  end

  # Returns task list from DB if populated, falls back to constants
  def build_task_list(dynamic_task)
    db_fixed   = TaskTemplate.joins(:team).where(dynamic: false).pluck(:name)
    db_dynamic = TaskTemplate.joins(:team).where(dynamic: true).pluck(:name)

    if db_fixed.any? || db_dynamic.any?
      fixed   = db_fixed
      dynamic = db_dynamic
    else
      fixed   = FIXED_TASKS
      dynamic = DYNAMIC_TASKS
    end

    dynamic_task.present? ? fixed + [dynamic_task] : fixed + dynamic
  end

  def valid_dynamic_task?(task_name)
    db_dynamic = TaskTemplate.where(dynamic: true).pluck(:name)
    list = db_dynamic.any? ? db_dynamic : DYNAMIC_TASKS
    list.include?(task_name)
  end

  def dynamic_task_names
    db_dynamic = TaskTemplate.where(dynamic: true).pluck(:name)
    db_dynamic.any? ? db_dynamic : DYNAMIC_TASKS
  end

  def build_task_payload(task_name, dynamic_task, hours)
    # Try DB first for team mapping
    team_name = task_team_name_from_db(task_name) || TASK_TEAM_MAP[task_name]
    assignees = team_name ? team_user_ids(team_name) : []
    assignees = org_member_ids if assignees.empty?

    payload = { summary: task_name, assignee_ids: assignees }

    if task_name == dynamic_task && hours.present?
      payload[:budget] = { hours: hours.to_f }
    end

    payload
  end

  def task_team_name_from_db(task_name)
    TaskTemplate.joins(:team).find_by(name: task_name)&.team&.name
  rescue => e
    Rails.logger.warn "DB lookup for task team failed: #{e.message}"
    nil
  end

  def get(path)
    response = conn.get("#{BASE_URL}#{path}") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
    end
    handle_error!(response)
    response.body
  end

  def get_raw(path)
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

  def put(path, body)
    response = conn.put("#{BASE_URL}#{path}") do |req|
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

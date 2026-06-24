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
  EXCLUDED_TEAMS  = ["Customer Support"].freeze

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

    project_id = create_project(project_name, non_excluded_member_ids)
    create_tasks(project_id, dynamic_task, hours)
    project_id
  end

  # --- Public methods for admin panel ---

  def sync_members_to_db
    members = org_members_with_users
    teams   = org_teams

    team_by_user = {}
    teams.each do |team|
      team_member_ids(team["id"]).each do |uid|
        team_by_user[uid] ||= team["name"]
      end
    end

    active_ids = []
    members.each do |m|
      next unless m[:name].present?
      HubstaffMember.find_or_initialize_by(hubstaff_user_id: m[:hubstaff_user_id]).tap do |rec|
        rec.name             = m[:name]
        rec.email            = m[:email]
        rec.team_name        = team_by_user[m[:hubstaff_user_id]]
        rec.membership_role  = m[:membership_role]
        rec.save!
      end
      active_ids << m[:hubstaff_user_id]
    end

    HubstaffMember.where.not(hubstaff_user_id: active_ids).destroy_all
  end

  def create_user_tasks_for_project(project_id, user_id, team_name)
    members = get("/projects/#{project_id}/members").fetch("project_members", [])
    unless members.any? { |m| m["user_id"] == user_id }
      return 0 unless add_member_to_project(project_id, user_id)
    end

    task_names = task_names_for_team(team_name)
    existing   = get_project_tasks(project_id)
    added      = 0

    task_names.each do |task_name|
      task = existing.find { |t| t["summary"] == task_name }
      next unless task
      next if (task["assignee_ids"] || []).include?(user_id)

      task_detail = get("/tasks/#{task["id"]}").fetch("task", {})
      put("/tasks/#{task["id"]}", {
        assignee_ids: (task_detail["assignee_ids"] || []) + [user_id],
        lock_version: task_detail["lock_version"],
        summary:      task_detail["summary"],
        status:       task_detail["status"] || "active"
      })
      added += 1
    end

    added
  end

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
    task_data = get("/tasks/#{task_id}").fetch("task", {})
    current   = task_data["assignee_ids"] || []
    return if current.include?(user_id)
    put("/tasks/#{task_id}", { assignee_ids: current + [user_id], lock_version: task_data["lock_version"] })
  rescue => e
    Rails.logger.error "Failed to add assignee #{user_id} to task #{task_id}: #{e.message}"
  end

  def remove_assignee_from_task(task_id, user_id)
    task_data = get("/tasks/#{task_id}").fetch("task", {})
    current   = task_data["assignee_ids"] || []
    return unless current.include?(user_id)
    put("/tasks/#{task_id}", { assignee_ids: current - [user_id], lock_version: task_data["lock_version"] })
  rescue => e
    Rails.logger.error "Failed to remove assignee #{user_id} from task #{task_id}: #{e.message}"
  end

  def remove_member_from_project(project_id, user_id)
    members = get("/projects/#{project_id}/members").fetch("project_members", [])
    membership = members.find { |m| m["user_id"] == user_id }
    return unless membership
    conn.delete("#{BASE_URL}/projects/#{project_id}/members/#{membership["id"]}") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
    end
  rescue => e
    Rails.logger.error "Failed to remove member #{user_id} from project #{project_id}: #{e.message}"
  end

  def add_task_to_project(project_id, task_name, assignee_ids: nil)
    if assignee_ids.nil?
      team_name = task_team_name_from_db(task_name) || TASK_TEAM_MAP[task_name]
      assignee_ids = if EXCLUDED_TEAMS.include?(team_name)
        []
      elsif team_name
        ids = team_user_ids(team_name)
        ids.empty? ? non_excluded_member_ids : ids
      else
        non_excluded_member_ids
      end
    end
    return if Array(assignee_ids).empty? # don't create tasks with no assignee (Hubstaff rejects them)
    response = post("/projects/#{project_id}/tasks", { summary: task_name, assignee_ids: assignee_ids })
    response.dig("task", "id") || raise("Failed to create task: #{response}")
  end

  def archive_task(task_id)
    put("/tasks/#{task_id}", { status: "archived" })
  rescue => e
    Rails.logger.error "Failed to archive task #{task_id}: #{e.message}"
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
    project_member_ids = project_member_id_set(project_id)
    existing_names     = get_project_tasks(project_id).map { |t| t["summary"] }
    all_tasks          = build_task_list(nil)

    all_tasks.each do |task_name|
      next if existing_names.include?(task_name)
      payload                  = build_task_payload(task_name, nil, nil)
      payload[:assignee_ids]   = Array(payload[:assignee_ids]) & project_member_ids.to_a
      next if payload[:assignee_ids].empty? # Hubstaff rejects tasks with no assignee
      response = post("/projects/#{project_id}/tasks", payload)
      task_id  = response.dig("task", "id")
      persist_task_to_db(project_id, task_name, task_id) if task_id
    end
  end

  def sync_task_assignees(project_id)
    project_member_ids = project_member_id_set(project_id)
    tasks = get_project_tasks(project_id)
    tasks.each do |task|
      task_name = task["summary"]
      team_name = task_team_name_from_db(task_name) || TASK_TEAM_MAP[task_name]
      next unless team_name
      next if EXCLUDED_TEAMS.include?(team_name)

      expected     = team_user_ids(team_name) & project_member_ids.to_a
      current      = task["assignee_ids"] || []
      missing      = expected - current
      next if missing.empty?

      task_detail  = get("/tasks/#{task["id"]}").fetch("task", {})
      updated_ids  = (current + missing).uniq
      put("/tasks/#{task["id"]}", {
        assignee_ids: updated_ids,
        lock_version: task_detail["lock_version"],
        summary:      task_detail["summary"],
        status:       task_detail["status"] || "active"
      })
    rescue => e
      Rails.logger.error "sync_task_assignees: failed for task #{task["id"]} (#{task["summary"]}): #{e.message}"
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

  def excluded_member_ids
    @excluded_member_ids ||= EXCLUDED_TEAMS.flat_map { |t| team_user_ids(t) }.to_set
  end

  def non_excluded_member_ids
    org_member_ids.reject { |id| excluded_member_ids.include?(id) }
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
    project_member_ids = non_excluded_member_ids.to_set
    tasks = build_task_list(dynamic_task)
    tasks.each do |task_name|
      payload                = build_task_payload(task_name, dynamic_task, hours)
      payload[:assignee_ids] = Array(payload[:assignee_ids]) & project_member_ids.to_a
      next if payload[:assignee_ids].empty? # skip excluded-team/general tasks (Hubstaff rejects empty assignee_ids)
      response = post("/projects/#{project_id}/tasks", payload)
      task_id  = response.dig("task", "id")
      persist_task_to_db(project_id, task_name, task_id) if task_id
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
    team_name = task_team_name_from_db(task_name) || TASK_TEAM_MAP[task_name]
    assignees = if EXCLUDED_TEAMS.include?(team_name)
      [] # general/excluded-team tasks aren't created in funnel projects (skipped by caller)
    elsif team_name
      ids = team_user_ids(team_name)
      ids.empty? ? non_excluded_member_ids : ids
    else
      non_excluded_member_ids
    end

    payload = { summary: task_name, assignee_ids: assignees }

    if task_name == dynamic_task && hours.present?
      payload[:budget] = { hours: hours.to_f }
    end

    payload
  end

  def persist_task_to_db(hubstaff_project_id, task_name, hubstaff_task_id)
    project = Project.find_by(hubstaff_project_id: hubstaff_project_id.to_s)
    return unless project

    dynamic_names = TaskTemplate.where(dynamic: true).pluck(:name).to_set
    ProjectTask.find_or_initialize_by(project: project, hubstaff_task_id: hubstaff_task_id.to_s).tap do |pt|
      pt.name    = task_name
      pt.dynamic = dynamic_names.include?(task_name)
      pt.save!
    end
  rescue => e
    Rails.logger.warn "persist_task_to_db failed for project #{hubstaff_project_id} / task #{task_name}: #{e.message}"
  end

  def project_member_id_set(project_id)
    get("/projects/#{project_id}/members").fetch("project_members", []).map { |m| m["user_id"] }.to_set
  end

  def task_names_for_team(team_name)
    db = TaskTemplate.joins(:team).where(teams: { name: team_name }).pluck(:name)
    return db if db.any?
    TASK_TEAM_MAP.select { |_, t| t == team_name }.keys
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

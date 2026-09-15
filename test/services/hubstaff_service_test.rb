require "test_helper"

class HubstaffServiceTest < ActiveSupport::TestCase
  ORG_ID     = "697101"
  PROJECT_ID = 4209728
  TASK_ID    = 9001
  TEAM_ID    = 246887
  TASK_NAME  = "Campaign Launch (Testing)"
  TEAM_NAME  = "Facebook Launcher"

  EDITOR    = 4262496
  LAUNCHER  = 4463766
  NEW_USER  = 4547489
  EX_MEMBER = 2555338 # left the org but still listed on old tasks

  setup do
    @env = ENV.to_h.slice("HUBSTAFF_REFRESH_TOKEN", "HUBSTAFF_ORG_ID")
    ENV["HUBSTAFF_REFRESH_TOKEN"] = "test-refresh-token"
    ENV["HUBSTAFF_ORG_ID"]        = ORG_ID

    @stubs   = Faraday::Adapter::Test::Stubs.new
    @service = HubstaffService.new
    @service.instance_variable_set(:@conn, Faraday.new { |f|
      f.request :json
      f.response :json
      f.adapter :test, @stubs
    })
    @service.define_singleton_method(:access_token) { "test-access-token" }

    Team.create!(name: TEAM_NAME).task_templates.create!(name: TASK_NAME)

    @roster      = [ member(EDITOR, "user"), member(LAUNCHER, "manager") ]
    @roster_puts = []
    @task_puts   = {}
  end

  teardown do
    ENV.delete("HUBSTAFF_REFRESH_TOKEN")
    ENV.delete("HUBSTAFF_ORG_ID")
    ENV.update(@env)
  end

  # --- add_member_to_project ---

  test "add_member_to_project sends the full roster with existing roles plus the new user" do
    stub_roster

    assert @service.add_member_to_project(PROJECT_ID, NEW_USER)
    assert_equal [ { "members" => [
      { "user_id" => EDITOR,   "role" => "user" },
      { "user_id" => LAUNCHER, "role" => "manager" },
      { "user_id" => NEW_USER, "role" => "user" }
    ] } ], @roster_puts
  end

  test "add_member_to_project gives the manager user the manager role" do
    stub_roster

    assert @service.add_member_to_project(PROJECT_ID, HubstaffService::MANAGER_USER_ID)
    assert_equal({ "user_id" => HubstaffService::MANAGER_USER_ID, "role" => "manager" }, @roster_puts.last["members"].last)
  end

  test "add_member_to_project does nothing for an existing member" do
    @roster << member(NEW_USER, "user")
    stub_roster

    assert @service.add_member_to_project(PROJECT_ID, NEW_USER)
    assert_empty @roster_puts
  end

  test "add_member_to_project returns false when update_members fails" do
    stub_roster(update_status: 405)

    assert_equal false, @service.add_member_to_project(PROJECT_ID, NEW_USER)
  end

  test "add_member_to_project returns false when Hubstaff accepts the call but the user is still missing" do
    stub_roster(apply_update: false)

    assert_equal false, @service.add_member_to_project(PROJECT_ID, NEW_USER)
    assert_equal 1, @roster_puts.size
  end

  test "add_member_to_project returns false and sends nothing when the roster can't be read" do
    @stubs.get(url("/projects/#{PROJECT_ID}/members")) { json({ "error" => "boom" }, status: 500) }
    stub_roster

    assert_equal false, @service.add_member_to_project(PROJECT_ID, NEW_USER)
    assert_empty @roster_puts
  end

  test "roster reads follow pagination" do
    @stubs.get(url("/projects/#{PROJECT_ID}/members?page_start_id=99")) { json("members" => [ member(LAUNCHER, "manager") ]) }
    @stubs.get(url("/projects/#{PROJECT_ID}/members")) do
      json("members" => [ member(EDITOR, "user") ], "pagination" => { "next_page_start_id" => 99 })
    end

    assert_equal [ EDITOR, LAUNCHER ], @service.send(:project_members, PROJECT_ID).map { |m| m["user_id"] }
  end

  # --- Member Sync (create_user_tasks_for_project) ---

  test "create_user_tasks_for_project bails without touching tasks when the member can't be added" do
    stub_roster(update_status: 405)
    stub_org([ EDITOR, LAUNCHER, NEW_USER ])
    stub_task([ LAUNCHER ])

    assert_equal 0, @service.create_user_tasks_for_project(PROJECT_ID, NEW_USER, TEAM_NAME)
    assert_empty @task_puts
  end

  test "create_user_tasks_for_project drops ex-members from assignee_ids before the PUT" do
    @roster << member(NEW_USER, "user")
    stub_roster
    stub_org([ EDITOR, LAUNCHER, NEW_USER ])
    stub_task([ EX_MEMBER, LAUNCHER ], lock_version: 7)

    assert_equal 1, @service.create_user_tasks_for_project(PROJECT_ID, NEW_USER, TEAM_NAME)
    assert_equal [ LAUNCHER, NEW_USER ], @task_puts[TASK_ID]["assignee_ids"]
    assert_equal 7, @task_puts[TASK_ID]["lock_version"]
    assert_empty @roster_puts
  end

  # --- sync_task_assignees ---

  test "sync_task_assignees drops ex-members and adds missing team members" do
    @roster << member(NEW_USER, "user")
    stub_roster
    stub_org([ EDITOR, LAUNCHER, NEW_USER ])
    stub_team([ LAUNCHER, NEW_USER ])
    stub_task([ EX_MEMBER, LAUNCHER ])

    @service.sync_task_assignees(PROJECT_ID)

    assert_equal [ LAUNCHER, NEW_USER ], @task_puts[TASK_ID]["assignee_ids"]
  end

  test "sync_task_assignees leaves a task alone when no team member is missing" do
    @roster << member(NEW_USER, "user")
    stub_roster
    stub_org([ EDITOR, LAUNCHER, NEW_USER ])
    stub_team([ LAUNCHER, NEW_USER ])
    stub_task([ EX_MEMBER, LAUNCHER, NEW_USER ])

    @service.sync_task_assignees(PROJECT_ID)

    assert_empty @task_puts
  end

  test "ex-member filtering is skipped if the org member list comes back empty" do
    stub_org([])
    stub_task([ EX_MEMBER, LAUNCHER ])

    @service.add_assignee_to_task(TASK_ID, NEW_USER)

    assert_equal [ EX_MEMBER, LAUNCHER, NEW_USER ], @task_puts[TASK_ID]["assignee_ids"]
  end

  private

  def url(path)
    "#{HubstaffService::BASE_URL}#{path}"
  end

  def json(body, status: 200)
    [ status, { "Content-Type" => "application/json" }, body.to_json ]
  end

  def member(user_id, role)
    { "user_id" => user_id, "membership_role" => role, "membership_status" => "active" }
  end

  # Roster backed by @roster. update_members records each payload in @roster_puts and, if it
  # succeeds and apply_update is set, replaces @roster with what was sent (the stricter of the two semantics).
  def stub_roster(update_status: 200, apply_update: true)
    @stubs.get(url("/projects/#{PROJECT_ID}/members")) { json("members" => @roster) }
    @stubs.put(url("/projects/#{PROJECT_ID}/update_members")) do |env|
      sent = JSON.parse(env.request_body)
      @roster_puts << sent
      @roster = sent["members"].map { |m| member(m["user_id"], m["role"]) } if apply_update && update_status == 200
      json({ "success" => update_status == 200 }, status: update_status)
    end
  end

  def stub_org(user_ids)
    @stubs.get(url("/organizations/#{ORG_ID}/members")) { json("members" => user_ids.map { |id| { "user_id" => id } }) }
  end

  def stub_team(user_ids)
    @stubs.get(url("/organizations/#{ORG_ID}/teams")) { json("teams" => [ { "id" => TEAM_ID, "name" => TEAM_NAME } ]) }
    @stubs.get(url("/teams/#{TEAM_ID}/members")) { json("team_members" => user_ids.map { |id| { "user_id" => id } }) }
  end

  # One task in the project; PUTs to it are recorded in @task_puts.
  def stub_task(assignee_ids, lock_version: 1)
    task = { "id" => TASK_ID, "summary" => TASK_NAME, "assignee_ids" => assignee_ids, "lock_version" => lock_version, "status" => "active" }
    @stubs.get(url("/projects/#{PROJECT_ID}/tasks")) { json("tasks" => [ task ]) }
    @stubs.get(url("/tasks/#{TASK_ID}")) { json("task" => task) }
    @stubs.put(url("/tasks/#{TASK_ID}")) do |env|
      @task_puts[TASK_ID] = JSON.parse(env.request_body)
      json("task" => task)
    end
  end
end

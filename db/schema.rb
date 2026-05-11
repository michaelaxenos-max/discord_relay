# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_11_000003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "admin_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
  end

  create_table "project_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event", null: false
    t.text "message"
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "created_at"], name: "index_project_logs_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_project_logs_on_project_id"
  end

  create_table "project_tasks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "dynamic", default: false, null: false
    t.string "hubstaff_task_id", null: false
    t.string "name", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "hubstaff_task_id"], name: "index_project_tasks_on_project_id_and_hubstaff_task_id", unique: true
    t.index ["project_id"], name: "index_project_tasks_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hubstaff_project_id"
    t.string "name", null: false
    t.integer "row_number"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["hubstaff_project_id"], name: "index_projects_on_hubstaff_project_id"
    t.index ["row_number"], name: "index_projects_on_row_number"
    t.index ["status"], name: "index_projects_on_status"
  end

  create_table "task_templates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "dynamic", default: false, null: false
    t.string "name", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_task_templates_on_team_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_teams_on_name", unique: true
  end

  add_foreign_key "project_logs", "projects"
  add_foreign_key "project_tasks", "projects"
end

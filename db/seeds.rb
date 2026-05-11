# Seeds for teams and task templates
# Safe to run multiple times — uses find_or_create_by

TEAM_TASKS = {
  "Facebook Launcher" => [
    { name: "Adset Launch (Scaling)",    dynamic: false },
    { name: "Campaign Launch (Testing)", dynamic: false },
    { name: "Meta Asset Warmup",         dynamic: false }
  ],
  "Editor" => [
    { name: "Deep Research GPT",    dynamic: false },
    { name: "Image (AI regen)",     dynamic: false },
    { name: "Image (from scratch)", dynamic: false },
    { name: "Video - 2min",         dynamic: false },
    { name: "Video – 3 min",   dynamic: false },
    { name: "Video – 4 min",   dynamic: false },
    { name: "Video – 5 min",   dynamic: false },
    { name: "Video – 6 min",   dynamic: false },
    { name: "Video – 7 min",   dynamic: false },
    { name: "Video – Script change",  dynamic: false },
    { name: "Video – Scrollstopper",  dynamic: false },
    { name: "Video – under 1 min",    dynamic: false }
  ],
  "Customer Support" => [
    { name: "Dispute Resolution",           dynamic: false },
    { name: "Sourcing & Margin Calculation", dynamic: false }
  ],
  "Funnel Builders" => [
    { name: "Advertorial",                dynamic: true },
    { name: "Advertorial - reproduced",   dynamic: true },
    { name: "Sales Page",                 dynamic: true },
    { name: "Sales Page - reproduced",    dynamic: true }
  ]
}.freeze

TEAM_TASKS.each do |team_name, tasks|
  team = Team.find_or_create_by!(name: team_name)
  tasks.each do |attrs|
    TaskTemplate.find_or_create_by!(name: attrs[:name], team: team) do |t|
      t.dynamic = attrs[:dynamic]
    end
  end
end

puts "Seeded #{Team.count} teams and #{TaskTemplate.count} task templates."

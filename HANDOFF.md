# Discord Relay + KPI Dashboard — Session Handoff

_Last updated: 2026-06-24_

## TL;DR
The Google Sheet → Hubstaff/Discord automation was broken. Root cause was **not** the
deployment or URL — it was that the Google Apps Script triggers had been auto-disabled
(owned by a former Google account). Fixed by recreating the triggers under the current
account, then fixed a second bug (empty `assignee_ids` crash on Customer Support tasks).
Everything is now working end-to-end and verified on real data.

---

## Systems & infrastructure

### Apps (Fly.io, org `personal`, account michaelaxenos@gmail.com)
| App | Role | Status |
|-----|------|--------|
| `mellowed-snowfall-236` | **The relay** (this repo). URL: https://mellowed-snowfall-236.fly.dev | deployed, healthy |
| `discord-relay-db` | Postgres (single node, region `gru`) attached to the relay | deployed |
| `kpi-dashboard-lumin` | KPI dashboard (separate repo, see below) | pending (not investigated this session) |
| `discord-relay-m5ozaw` | **Previous** relay app | suspended (was likely the old prod target) |
| `html-stripper` | unrelated | suspended |

> The README's old URL `discord-relay-lucid-dew-846` no longer exists.

### Tooling notes
- `flyctl` is installed at `~/.fly/bin/flyctl` (Homebrew is NOT installed on this machine).
  Add to PATH: `export PATH="$HOME/.fly/bin:$PATH"`.
- Logged into Fly as michaelaxenos@gmail.com.

### Relay admin panel
- URL: https://mellowed-snowfall-236.fly.dev/admin/login
- User: `michael.xenos@lumin-brands.com` / `Lumin2026!` (AdminUser id=1, created this session)
- Mission Control jobs UI: `/admin/jobs`

### Relay secrets (set on the Fly app)
`DISCORD_BOT_TOKEN`, `HUBSTAFF_REFRESH_TOKEN`, `HUBSTAFF_ORG_ID` (=697101),
`GOOGLE_SERVICE_ACCOUNT_JSON` (base64), `KPI_DASHBOARD_API_KEY`, `SECRET_KEY_BASE`
(generated — repo `master.key` was missing/gitignored), `DATABASE_URL` (auto from pg attach).

### Google Apps Script (the trigger layer)
- Bound to spreadsheet **"Products & Funnels (Lumin Brands Tracker)"**
  (ID `1Mczh0xJgnXxN3n36hx6hzxxLBjtIM83YD3tXzEJ4hno`), tab **"Testing"`.
- Script project ID: `1MBqFI-7gLQAduOJlZdTBRvtLGZDV8BU6JMMEX6IUXTj8R0vEm9KvLGmG`
- Script Property `RELAY_URL` = `https://mellowed-snowfall-236.fly.dev` (already correct).
- Also has `SHEETS_PROXY_URL` / `SHEETS_PROXY_SECRET` (a Cloudflare worker) — unrelated to
  the Hubstaff path; `SHEETS_PROXY_SECRET` is still a placeholder (`set-this-via-wrangler-secret`).

---

## What was done this session
1. **Deployed the relay** to a fresh Fly app `mellowed-snowfall-236` + Postgres; set all secrets.
   Granted `CREATEDB` to the app's pg role so `db:prepare` could create the Solid
   Queue/Cache/Cable databases.
2. **Created the admin user** (above).
3. **Diagnosed the real bug:** new sheet rows weren't creating Hubstaff projects. Backend was
   healthy and `RELAY_URL` was already correct. The cause: **6 of 7 "on edit" triggers were
   Disabled, owned by "Other user"** (the previous developer's Google account — Google disables
   a trigger when its owner loses access). Only the auto-folder trigger ran.
4. **Recreated all 6 triggers** under michaelaxenos@gmail.com (event: From spreadsheet / On edit):
   `onProjectRowAdded`, `onHubstaffProjectIdCleared`, `handleEdit`,
   `trackFunnelAssignment`, `trackWinnersAssignment`, `trackEditingAssignment`.
5. **Fixed a second bug** (surfaced once the pipeline ran again): Hubstaff returns
   `400 assignee_ids is empty`, which crashed project creation. The standard task set includes
   two **general Customer Support tasks** ("Dispute Resolution", "Sourcing & Margin Calculation")
   that are intentionally **not** tied to a funnel, so they resolved to empty assignees.
   Fix = skip any task that resolves to zero assignees (they're never created in funnel projects).
   - File: `app/services/hubstaff_service.rb`
   - Branch: `fix/cs-task-assignees` (commit `d5a7d3f`), pushed to GitHub. **PR not yet merged.**
   - Deployed to Fly. Verified: a funnel project now creates **19 tasks**, skipping exactly the
     2 general CS tasks.
6. **Fixed job-queue reliability** (rows stuck on `pending`, columns AR not updating): the
   separate `worker` machine had **no auto-start** and silently stopped, stalling the queue
   (`SolidQueue::Processes::ProcessPrunedError`). Switched to running **Solid Queue inside Puma**
   on the always-on `app` machines (`SOLID_QUEUE_IN_PUMA=true` in `fly.toml [env]`) and **removed
   the `worker` process**. Verified both app machines now run Supervisor/Dispatcher/Worker/Scheduler.
   Cleaned up duplicate `pending` Project records (rows already had IDs from sibling jobs).

---

## Current state — all working ✅
- Adding a properly-filled row (Market, Code, Product Name, Date Added, Funnel Name) creates the
  Hubstaff project + tasks and writes the Hubstaff Project ID back to column AR.
- Verified on real data: rows 629 (`NLBE565` → 4091966) and 630 (`DEAT565` → 4091967) succeeded
  with distinct IDs.

### How the data model holds together (confirmed)
- **Funnel Name is unique per market** — it includes the market-code prefix, e.g.
  `NLBE565 Bee Venom Mouthwash` vs `DEAT565 Bee Venom Mouthwash`. So **1 funnel = 1 Hubstaff
  project = 1 market**.
- **Relay dedup is by funnel name** (3 layers: sheet duplicate check → DB name match → Hubstaff
  active-project name match). Because funnel names carry the market code, NLBE/DEAT never merge.
  ⚠️ Dependency: this only holds while funnel names keep the market-code prefix. A bare
  product-name funnel could collide.
- **KPI dashboard keys on Hubstaff Project ID**, not names, and syncs **directly from the Hubstaff
  API** (it does NOT read the Google Sheet). So per-market metrics stay separate as long as the
  Hubstaff projects are separate.

---

## Open follow-ups / TODO
- [ ] **Rotate the leaked credentials** — Discord bot token, Hubstaff refresh token, Google
      service-account key, and `KPI_DASHBOARD_API_KEY` were pasted in chat. Regenerate each and
      `flyctl secrets set KEY=newvalue -a mellowed-snowfall-236`.
- [ ] **Merge the PR**: https://github.com/michaelaxenos-max/discord_relay/pull/new/fix/cs-task-assignees
      (`gh` is not installed locally, so merge via GitHub UI).
- [ ] **Orphaned Hubstaff projects**: the pre-fix failed attempts (projects 266/267) may have
      created Hubstaff projects that then crashed mid-setup → possible duplicates. Cleanup:
      `flyctl ssh console -a mellowed-snowfall-236 -C "bin/rails hubstaff:dedup_projects"`
      (archives all but the oldest per name). Review before running.
- [ ] **`fly.toml`** in this repo still has the app-name change staged locally (not committed):
      `app = 'mellowed-snowfall-236'`. Commit it if you want a fresh clone's `fly deploy` to
      target the right app.
- [ ] **`kpi-dashboard-lumin`** shows status `pending` on Fly — not investigated this session.
- [ ] Optional: change the admin password (it was set in chat).

---

## Gotchas / things to remember
- **Trigger ownership**: Apps Script triggers created by a user who later loses access get
  silently Disabled. If automations stop firing, check Triggers page ownership first.
- **Hubstaff requires ≥1 assignee per task** (error_code 11000). Never post a task with empty
  `assignee_ids` — the code now skips them.
- **The relay only exposes `/api/task_templates`** to the KPI dashboard (task catalog, protected
  by `KPI_DASHBOARD_API_KEY`). It does NOT broker the funnel↔project mapping.
- **The Apps Script `RELAY_URL` and `SHEETS_PROXY_URL` are different paths** — Hubstaff/Discord
  relay calls go straight to `RELAY_URL`; the proxy is a separate Cloudflare worker.

## Useful commands
```bash
export PATH="$HOME/.fly/bin:$PATH"
flyctl status  -a mellowed-snowfall-236
flyctl logs    -a mellowed-snowfall-236
flyctl ssh console -a mellowed-snowfall-236 -C "bin/rails runner '...'"
cd ~/discord_relay && flyctl deploy -a mellowed-snowfall-236   # redeploy after code changes
```

## Repos (cloned locally)
- Relay: `~/discord_relay` (GitHub: michaelaxenos-max/discord_relay)
- Dashboard: `~/kpi_dashboard` (GitHub: michaelaxenos-max/kpi_dashboard) — Rails 8, uses the
  vendored `corepulse` gem (`vendor/corepulse`) for Hubstaff sync; keys everything on Hubstaff IDs.

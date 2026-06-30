# Funnel Automation System — Session Handoff

_Last updated: 2026-06-30_

## TL;DR
The Google Sheet → Hubstaff/Discord automation was broken; root cause was that the Apps Script
triggers had been auto-disabled (owned by a former Google account). After recreating them, a
series of follow-on issues were fixed: an empty-`assignee_ids` crash, a stalled job queue, the
"one thread per funnel" behaviour, and bad data in the sheet. Everything is working end-to-end
and verified on real data. `clasp` is now set up so the Apps Script can be edited from the
terminal. Main things still open: **rotate the leaked credentials**, **merge the PR**, and
optionally **ship the thread self-heal**.

---

## Systems & infrastructure

### Apps (Fly.io, org `personal`, account michaelaxenos@gmail.com)
| App | Role | Status |
|-----|------|--------|
| `mellowed-snowfall-236` | **The relay** (this repo). https://mellowed-snowfall-236.fly.dev | deployed, healthy |
| `discord-relay-db` | Postgres (single node, region `gru`) attached to the relay | deployed |
| `kpi-dashboard-lumin` | KPI dashboard (separate repo) | `pending` on Fly — not investigated |
| `discord-relay-m5ozaw` | Previous relay app | suspended |

> The README's old URL `discord-relay-lucid-dew-846` no longer exists.

### Tooling on this machine
- `flyctl` → `~/.fly/bin/flyctl` (no Homebrew). `export PATH="$HOME/.fly/bin:$PATH"`. Logged in as michaelaxenos@gmail.com.
- `clasp` (Apps Script CLI) → installed globally via npm, logged in as michaelaxenos@gmail.com
  (`~/.clasprc.json`). Node at `~/.nvm/versions/node/v24.15.0/bin`.
- `node`/`npm` present; `gws` CLI present but only Drive-scoped (no Apps Script scope).

### Relay admin panel
- https://mellowed-snowfall-236.fly.dev/admin/login
- `michael.xenos@lumin-brands.com` / `Lumin2026!` (AdminUser id=1) — change the password.
- Background-jobs UI: `/admin/jobs`

### Relay secrets (on the Fly app)
`DISCORD_BOT_TOKEN`, `HUBSTAFF_REFRESH_TOKEN`, `HUBSTAFF_ORG_ID` (=697101),
`GOOGLE_SERVICE_ACCOUNT_JSON` (base64), `KPI_DASHBOARD_API_KEY`, `SECRET_KEY_BASE`
(generated — repo `master.key` was missing), `DATABASE_URL`, `SOLID_QUEUE_IN_PUMA=true`.

### Google Apps Script (the trigger layer)
- Bound to spreadsheet **"Products & Funnels (Lumin Brands Tracker)"**
  (`1Mczh0xJgnXxN3n36hx6hzxxLBjtIM83YD3tXzEJ4hno`), tab **"Testing"**.
- Script project ID: `1MBqFI-7gLQAduOJlZdTBRvtLGZDV8BU6JMMEX6IUXTj8R0vEm9KvLGmG`
- Script property `RELAY_URL` = `https://mellowed-snowfall-236.fly.dev`.
- Funnel forum channel `DISCORD_FUNNEL_CHANNEL_ID = 1495131357746171994`.

### Editing the Apps Script (now possible from terminal)
```bash
export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"
mkdir -p /tmp/funnel_as && cd /tmp/funnel_as
clasp clone 1MBqFI-7gLQAduOJlZdTBRvtLGZDV8BU6JMMEX6IUXTj8R0vEm9KvLGmG   # pull
# edit the .js file(s), then:
clasp push --force                                                      # push live
```
⚠️ The deployed project splits functions across files (`funnel-assignment.js`, `editing-assignment.js`,
`google-sheets-trigger.js`, `hubStaff.js`, `discord.js`, `Code.js`, `colNameNumbers.js`, …).
The repo's `track_funnel.js` is a **combined reference copy** and is NOT a 1:1 of any single
deployed file — never paste it over a live file wholesale (it would duplicate functions). Patch the
specific function in place.

---

## What was done

1. **Deployed the relay** to `mellowed-snowfall-236` + Postgres; set all secrets; granted `CREATEDB`
   so `db:prepare` could create the Solid Queue/Cache/Cable databases. Created the admin user.
2. **Root-cause fix — disabled triggers:** 6 of 7 on-edit triggers were Disabled (owned by a former
   Google account). Recreated all 6 under the current account (From spreadsheet / On edit):
   `onProjectRowAdded`, `onHubstaffProjectIdCleared`, `handleEdit`, `trackFunnelAssignment`,
   `trackWinnersAssignment`, `trackEditingAssignment`.
3. **Empty-assignee crash:** Hubstaff rejects tasks with no assignee (error 11000), which crashed
   project creation when the standard set included the two general Customer Support tasks
   (Dispute Resolution, Sourcing & Margin Calculation). Fix = skip zero-assignee tasks; those general
   tasks are simply not created in funnel projects. (`app/services/hubstaff_service.rb`.) Verified: a
   project now creates 19 tasks.
4. **Job-queue reliability:** the separate `worker` machine had no auto-start and silently stopped,
   leaving rows on `pending`. Switched to running Solid Queue **inside Puma** on the always-on app
   machines (`SOLID_QUEUE_IN_PUMA=true`) and removed the worker process. Cleaned up duplicate
   `pending` records.
5. **Backfilled** missing Discord funnel posts for rows 614–634 that had a builder but no Funnel Post Id.
6. **One thread per funnel (LIVE):** changed `trackFunnelAssignment` so a builder reassignment
   **renames the existing thread + posts a note** instead of creating a duplicate. Applied to the live
   Apps Script via `clasp` and committed to the repo (`track_funnel.js`).
7. **Data-hygiene fixes:**
   - Row 626's `Funnel Post Id` held stray text (`"No, don't backfill all rows, …"`) → cleared it
     (it was crashing `trackFunnelAssignment` with a "bad URI" error → failure emails).
   - Row 628's thread had been deleted in Discord (404) so status updates silently no-op'd → recreated
     the thread (`1520405798218498181`) with the current status tag and updated the sheet.

---

## Current state — working ✅
- A properly-filled new row creates the Hubstaff project + tasks and writes the Project ID back to
  column AR (verified, e.g. NLBE565→4091966, DEAT565→4091967).
- Funnel builder assignment opens/updates a single Discord thread per funnel; status changes re-tag it.
- **1 funnel = 1 Hubstaff project = 1 market.** Funnel Name carries the market code (`NLBE565…` vs
  `DEAT565…`) so markets never merge. Relay dedups by name (sheet → DB → Hubstaff). KPI dashboard
  keys on Hubstaff IDs, syncing directly from Hubstaff (not the sheet).

---

## Known issue & the proposed self-heal (NOT yet implemented)
The sheet's `Funnel Post Id` can go bad two ways, and the automation doesn't currently cope:
- **Garbage text in the cell** → relay does `PATCH channels/<text>` → bad URI → 500 → Apps Script
  failure email. (Seen on row 626.)
- **Deleted-thread ID** → `update_forum_post` never checks whether the PATCH succeeded, so it returns
  "ok" and the tag silently never updates. (Seen on row 628.)

Proposed 3-part self-heal:
1. Relay `update_forum_post` — validate the thread ID is numeric and check the Discord response;
   signal "thread missing" instead of crashing / faking success.
2. Relay `create_forum_post` — when reusing an existing thread record, verify it still exists in
   Discord; if not, drop the stale record and create fresh (so recreation actually works).
3. Apps Script `trackFunnelAssignment` — on a missing thread, recreate it and write the new ID back.

Net effect: a deleted thread or fat-fingered cell auto-repairs on the next edit.

---

## Open follow-ups / TODO
- [ ] 🔴 **Rotate the leaked credentials** (Discord, Hubstaff refresh token, Google service-account
      key, KPI key) shared in chat; then `flyctl secrets set KEY=newvalue -a mellowed-snowfall-236`.
- [ ] **Merge the PR** — branch `fix/cs-task-assignees` (github.com/michaelaxenos-max/discord_relay).
      `gh` not installed locally → merge via GitHub UI. Contains all relay + Apps Script + docs changes.
- [ ] **Ship the thread self-heal** (above) — relay + Apps Script change; can be done via flyctl + clasp.
- [ ] **Orphaned Hubstaff projects** from pre-fix failures: review then
      `flyctl ssh console -a mellowed-snowfall-236 -C "bin/rails hubstaff:dedup_projects"`.
- [ ] Change the admin password (set in chat).
- [ ] `kpi-dashboard-lumin` shows `pending` on Fly — investigate.

---

## Gotchas
- **Trigger ownership:** triggers created by a user who loses access get auto-disabled. If automations
  stop firing, check Triggers-page ownership first.
- **Repo `track_funnel.js` ≠ deployed files** — it's a combined reference; patch live files in place
  via `clasp`, don't overwrite (see "Editing the Apps Script").
- **Hubstaff requires ≥1 assignee per task** (error 11000) — never post a task with empty `assignee_ids`.
- **Discord thread identity** = (channel_id, title); funnel titles are `"{Funnel Name} - {Builder}"`.
  Deleting a thread in Discord without clearing the sheet cell breaks status updates until recreated.
- **The relay only exposes `/api/task_templates`** to the KPI dashboard; it does NOT broker the
  funnel↔project mapping.

---

## Docs & artifacts produced
- **Drive "Documents" folder** (`1-1K1HU5m6Nunv1xUskPUW1jJerO9qRZQ`): Editor SOP (PDF),
  "Funnel System — Overview" (Doc), "Funnel System — Technical Handoff" (Doc).
- **Editor SOP** — `EDITOR_SOP.md` (repo) + the PDF.
- **Visual overview** — `funnel-system-visual.html` (repo). Live link via
  https://raw.githack.com/michaelaxenos-max/discord_relay/fix/cs-task-assignees/funnel-system-visual.html
- **This handoff** — `HANDOFF.md` (repo).

## Useful commands
```bash
export PATH="$HOME/.fly/bin:$PATH"
flyctl status -a mellowed-snowfall-236
flyctl logs   -a mellowed-snowfall-236
flyctl ssh console -a mellowed-snowfall-236 -C "bin/rails runner '...'"
cd ~/discord_relay && flyctl deploy -a mellowed-snowfall-236
# Apps Script: see "Editing the Apps Script" above (clasp clone / push)
```

## Repos (cloned locally)
- Relay: `~/discord_relay` (github.com/michaelaxenos-max/discord_relay)
- Dashboard: `~/kpi_dashboard` (github.com/michaelaxenos-max/kpi_dashboard) — Rails 8; vendored
  `corepulse` gem does the Hubstaff sync, keyed entirely on Hubstaff IDs.

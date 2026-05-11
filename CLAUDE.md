# Discord Relay

A Rails API that proxies requests from Google Sheets scripts to Discord's API. Built because Discord's Cloudflare protection blocks requests originating from Google's IP ranges.

## How it works

```
Google Sheets Script → POST to this Rails API → Discord API
```

The relay lives on Fly.io, whose IPs are not blocked by Discord. Google Sheets calls this API instead of Discord directly.

## Endpoints

### Create a forum post
`POST /discord/forum/post`

```json
{
  "channel_id": "1495131357746171994",
  "title": "Post title",
  "content": "Post content",
  "tags": ["Ready"]
}
```
`tags` is optional — omit it to create a post with no tags.

Returns:
```json
{ "ok": true, "thread_id": "..." }
```

### Update a forum post
`POST /discord/forum/update`

```json
{
  "channel_id": "1495131357746171994",
  "thread_id": "...",
  "tags": ["In progress"],
  "content": "Optional comment to add"
}
```
Both `tags` and `content` are optional.

Returns:
```json
{ "ok": true }
```

### Health check
`GET /up` — returns 200 if the app is running.

## Google Sheets setup

The script is in `test.js`. Copy-paste it into your Google Apps Script editor.

In your Apps Script project go to **Extensions > Apps Script > Project Settings > Script Properties** and add:

| Key | Value |
|-----|-------|
| `RELAY_URL` | `https://discord-relay-lucid-dew-846.fly.dev` |

Usage in your sheet:
```javascript
// With tag
createForumPost("CHANNEL_ID", "Title", "Content", "Ready");

// Without tag
createForumPost("CHANNEL_ID", "Title", "Content");

// Update with new tag and comment
updateForumPost("CHANNEL_ID", "THREAD_ID", "In progress", "Here is my comment");

// Update tags only
updateForumPost("CHANNEL_ID", "THREAD_ID", "Fixed");
```

## Deployment

**App URL:** https://discord-relay-lucid-dew-846.fly.dev
**Fly.io app name:** `discord-relay-lucid-dew-846`
**Region:** São Paulo, Brazil (gru)
**Database:** Postgres on Fly.io (auto-attached)

### First-time deploy
```bash
brew install flyctl
fly auth login
fly launch       # already done — skip this if app exists
fly deploy
```

### Redeploy after changes
```bash
fly deploy
```

### Environment secrets

The Discord bot token is stored as a Fly.io secret — never put it in this file or in code.

To set or reset the bot token (get it from Discord Developer Portal > Your App > Bot > Reset Token):
```bash
fly secrets set DISCORD_BOT_TOKEN=your_token_here
fly deploy
```

To list all secrets (values are hidden):
```bash
fly secrets list
```

### Logs
```bash
fly logs
```

### Rails console on production
```bash
fly ssh console -C "/rails/bin/rails console"
```

## Key files

- `app/controllers/discord_controller.rb` — handles forum post creation and updates
- `config/routes.rb` — API routes
- `config/initializers/cors.rb` — allows requests from any origin (needed for Google Sheets)
- `test.js` — Google Sheets script to copy-paste into Apps Script
- `fly.toml` — Fly.io configuration (auto_stop disabled so the app never sleeps)

## Stack

- Ruby 3.4.8
- Rails 8.1.2 (API mode)
- PostgreSQL (via Fly.io managed Postgres)
- Faraday (HTTP client for Discord API calls)
- Hosted on Fly.io (~$2-4/month, never idles)

# Issue tracking

**Status:** PLANNED

I want to setup issue tracking between GitHub and Discord. New bug reports and feature requests in the #bug-reports and #feature-requests channel should be synced bidirectionally between Discord and GitHub Issues on the https://github.com/jsvana/carrier_wave repo.

## Solution

Create a standalone Rust Discord bot in a separate repository (`discord-github-sync` or similar) that can be reused across projects.

## Architecture

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│     Discord     │◄───►│  discord-github-sync │◄───►│     GitHub      │
│                 │     │                      │     │                 │
│ #bug-reports    │     │  - Discord bot       │     │ Issues API      │
│ #feature-reqs   │     │  - Webhook server    │     │ Webhooks        │
└─────────────────┘     │  - SQLite DB         │     └─────────────────┘
                        └──────────────────────┘
```

### Components

1. **Discord Bot** (serenity)
   - Monitors configured channels for new messages
   - Creates threads for each issue
   - Posts GitHub updates as thread replies

2. **Webhook Server** (axum)
   - Receives GitHub issue/comment webhooks
   - Receives GitHub release webhooks for auto-closing

3. **Database** (SQLite via sqlx)
   - Maps Discord message ID ↔ GitHub issue number
   - Stores project configurations

4. **Configuration** (TOML/YAML)
   ```toml
   [[projects]]
   discord_guild_id = "123456789"
   github_repo = "jsvana/carrier_wave"

   [projects.channels]
   bug_reports = "channel_id_1"
   feature_requests = "channel_id_2"

   [projects.labels]
   bug_reports = ["bug", "from-discord"]
   feature_requests = ["enhancement", "from-discord"]
   ```

## Sync Behavior

### Discord → GitHub

| Discord Event | GitHub Action |
|---------------|---------------|
| New message in monitored channel | Create issue (title from first line, body from rest) |
| Reply in issue thread | Add comment to issue |
| Reaction (e.g., ✅) by maintainer | Close issue |

### GitHub → Discord

| GitHub Event | Discord Action |
|--------------|----------------|
| New comment on synced issue | Post in Discord thread |
| Issue closed | Post closure notice in thread, add ✅ reaction |
| Issue reopened | Post reopen notice in thread |
| Release published | Close issues mentioned in release body |

### Release Auto-Close

When a GitHub release is published:
1. Parse release body for issue references (`#123`, `fixes #123`, etc.)
2. For each referenced issue that's synced:
   - Close the GitHub issue (if not already closed)
   - Post in Discord thread: "Resolved in release vX.Y.Z"
   - Add ✅ reaction to original message

## Tech Stack

- **Runtime:** Rust (async with tokio)
- **Discord:** serenity
- **HTTP server:** axum
- **Database:** SQLite with sqlx
- **GitHub API:** octocrab
- **Config:** toml or figment

## Deployment

- Runs on home server
- Needs public endpoint for GitHub webhooks (Cloudflare Tunnel, ngrok, or port forward)
- Systemd service for process management

## Implementation Phases

### Phase 1: Core Bot
- [ ] Project setup (Cargo workspace, CI)
- [ ] Discord bot connects and monitors channels
- [ ] Create GitHub issues from Discord messages
- [ ] SQLite storage for message-issue mapping

### Phase 2: GitHub → Discord
- [ ] Webhook server for GitHub events
- [ ] Post issue comments to Discord threads
- [ ] Sync issue status changes

### Phase 3: Release Integration
- [ ] Parse release notes for issue references
- [ ] Auto-close referenced issues
- [ ] Post resolution notices to Discord

### Phase 4: Polish
- [ ] Error handling and retry logic
- [ ] Rate limiting
- [ ] Admin commands (list synced issues, force sync, etc.)
- [ ] Documentation

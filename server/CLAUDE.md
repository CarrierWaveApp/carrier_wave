# Activities Server

Self-hostable Rust backend for Carrier Wave. Manages challenges, clubs, events, activity feeds, park boundaries, POTA stats, RBN proxy, equipment catalog, and contest definitions.

## Architecture

Axum web framework + PostgreSQL via sqlx. Deployed to Hetzner via Ansible.

```
server/
├── src/
│   ├── handlers/      # HTTP route handlers (one file per resource)
│   ├── db/            # Database queries (one file per table/resource)
│   ├── models/        # Request/response types
│   ├── aggregators/   # Background data fetchers (POTA, SOTA, park boundaries, trails)
│   ├── auth/          # Token middleware and generation
│   ├── contest/       # Contest engine (Cabrillo, scoring, validation)
│   └── rbn/           # Reverse Beacon Network WebSocket ingester + store
├── migrations/        # PostgreSQL migrations (run automatically on startup)
├── ios-admin/         # ChallengesAdmin iOS app (xcodegen)
├── web/               # Admin web UI (React/TypeScript/Vite)
├── docs/              # API reference, CI/CD docs, feature specs
└── scripts/           # Data import tools
```

## Building and Testing

```bash
cargo build              # Build
cargo test               # Run tests
cargo run                # Run locally (needs .env with DATABASE_URL)
```

Requires PostgreSQL. Copy `.env.example` to `.env` and set `DATABASE_URL`. Migrations run automatically on startup.

## Deployment

Deployed via Ansible role `activities_server` in `infra/ansible/` (private infra repository).

### Releasing a new version

1. Bump `version` in `server/Cargo.toml` (e.g., `0.4.59`)
2. Commit and push to `main`
3. Tag and push: `git tag server-v0.4.59 && git push origin server-v0.4.59`
4. `.github/workflows/release-server.yml` will automatically:
   - Build the frontend (`npm ci && npm run build` in `server/web/`)
   - Cross-compile the Rust binary for `x86_64-unknown-linux-musl`
   - Package tarball (binary + `web/dist/` + `migrations/`)
   - Create a GitHub Release at `server-v0.4.59`
5. Deployment is handled from the private infra repository, which picks up
   the new release and rolls it to staging, then prod.

Tag format is `server-v{version}` (not `v{version}`) to avoid collision with iOS release tags.

### Local release build (bypassing GitHub Actions)

The release artifact can be produced entirely on a Mac. One-time setup:

```bash
brew install zig cargo-zigbuild      # musl cross-linker (homebrew's musl-cross is gone)
rustup target add x86_64-unknown-linux-musl
```

Build (mirrors `.github/workflows/release-server.yml`):

```bash
cd server
(cd web && npm ci && npm run build)
(cd logbook-web && npm ci && npm run build)
cargo zigbuild --release --target x86_64-unknown-linux-musl

VERSION=$(grep '^version' Cargo.toml | head -1 | sed 's/.*"\(.*\)".*/\1/')
ARCHIVE="activities-server-v${VERSION}-x86_64-linux.tar.gz"
rm -rf staging && mkdir -p staging/web staging/logbook-web
cp target/x86_64-unknown-linux-musl/release/activities-server staging/
cp -r web/dist staging/web/
cp -r logbook-web/dist staging/logbook-web/
cp -r migrations static staging/
tar -czf "$ARCHIVE" -C staging .
shasum -a 256 "$ARCHIVE"
```

To deploy a local tarball, skip Ansible's GitHub download: copy it to the
host's `/tmp/{{ activities_server_filename }}` yourself, then extract to the
install dir and restart —

```bash
scp "$ARCHIVE" <host>:/tmp/
ssh <host> 'tar -xzf /tmp/'"$ARCHIVE"' -C /opt/activities-server \
  && chown -R activities-server:activities-server /opt/activities-server \
  && systemctl restart activities-server'
```

(Staging uses its own install dir/service via the `activities_server_staging`
role.) Note the staging-first invariant and the Ansible version/checksum vars
still point at the last GitHub release — a locally deployed build will be
overwritten by the next Ansible run, so follow up with a real tagged release.

### Web-only deploy (no Rust rebuild)

The binary serves `web/dist` and `logbook-web/dist` straight off disk from
`/opt/activities-server`, so asset-only changes don't need a release or a
service restart:

```bash
cd server/logbook-web && npm run build   # or server/web
rsync -av --delete dist/ <host>:/opt/activities-server/logbook-web/dist/
```

New assets are served on the next request. Same caveats as above: keep the
assets API-compatible with the running binary, and the next full deploy
overwrites them.

## Key Docs

| Area | Details |
|------|---------|
| API Reference | [docs/api.md](docs/api.md) |
| CI/CD | [docs/cicd.md](docs/cicd.md) |
| Logging & request ids | [docs/logging.md](docs/logging.md) |
| Auth | [docs/features/auth.md](docs/features/auth.md) |
| Third-party OAuth/OIDC API | [docs/features/oauth-api.md](docs/features/oauth-api.md) |
| Challenges | [docs/features/challenges.md](docs/features/challenges.md) |
| Contest Definitions | [docs/features/contest-definitions.md](docs/features/contest-definitions.md) |
| Events | [docs/features/events.md](docs/features/events.md) |
| Leaderboards | [docs/features/leaderboards.md](docs/features/leaderboards.md) |

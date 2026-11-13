---
title: "Developers"
description: "Build on the Carrier Wave platform: the activities server API, OAuth sign-in, and the encrypted sync journal"
weight: 6
---

Carrier Wave's apps talk to a single backend, the **activities server** at
`https://activities.carrierwave.app`. It hosts the public amateur-radio data the
apps display (spots, POTA statistics, park boundaries, contest definitions,
radio macros), the social features (challenges, friends, clubs, events), and
the end-to-end encrypted log sync.

The same API is open to you. Anonymous callers can read the public datasets.
Apps written by other developers can ask a Carrier Wave user for permission
through standard OAuth 2.0 / OpenID Connect and then read or update that
user's log through the sync journal.

Two pages, one source:

- **[Activities Server API Reference](/developers/api/)** is the complete
  wire-level reference, written for people.
- **[Using the API from agents and tools](/developers/agents/)** is the short
  version for coding agents, scripts and CLIs: machine-readable URLs, the
  device flow, and ready-to-run requests.

Both are also served as plain Markdown (append `index.md` to the page URL),
and <https://carrierwave.app/llms.txt> indexes them for tools.

## Ground rules

- **Be a good citizen.** The public endpoints exist to serve the apps. Cache
  responses, honour `ETag`/`If-None-Match` where offered, and stay well under
  the published rate limits.
- **Identify yourself.** Send a descriptive `User-Agent` so we can reach you
  if a client misbehaves.
- **No scraping of the social surface.** Friends, feeds, clubs and challenge
  progress are first-party only; third-party OAuth tokens are refused there
  by design.
- **Questions or a client to register?** Email hello@carrierwave.app.

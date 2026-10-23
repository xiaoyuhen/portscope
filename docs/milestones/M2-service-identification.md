# Milestone 2 — What is this port for?

## Goal

Turn `port → pid → "node"` into `port → "Express API for the redis-node
project, 85% confident, here is why"`.

## How identification works

Three tiers of evidence, strongest first. The tiers are *merged*, not
replaced — a lower tier that agrees raises confidence, a lower tier that is
merely present does not.

### 1. Process (`evidence.process`)

The executable, its argv and its working directory. This tier carries the most
weight because it names the actual tool: `manage.py runserver` is Django,
`node_modules/vite/bin/vite.js` is Vite, `redis-server` is Redis.

Patterns are explicit about how they combine:

- `any:` — the listed patterns are alternative spellings of one service
  (`postgres` or `postmaster`).
- `all:` — the patterns narrow a common binary down (`serve` *and* being the
  `serve` binary, so `manage.py runserver` is not misread).

### 2. HTTP (`evidence.httpHeader`, `evidence.httpStatus`)

A `GET /` against **127.0.0.1 only** — never the LAN address, even when the
service is bound to one — with a 1.5 s timeout and a fixed User-Agent. Headers
are the signal: `Server: AirTunes` identifies the AirPlay receiver even though
the process is `ControlCenter`.

Ports known not to speak HTTP (22, 3306, 5432, 6379, 9092, 11211, 27017) and
anything already classified as a database or cache are skipped, so probing
never costs a timeout it cannot use.

A port that answers HTTP but matches no fingerprint is reported as **"HTTP
API"** or **"HTTP server"** at 35% — not "unknown". "Something is serving HTTP
here" is already useful information.

### 3. Well-known port (`evidence.wellKnownPort`)

Only consulted when tiers 1 and 2 found nothing, and capped at 50% confidence.
A Vite server on 3000 is not called "Ruby on Rails" because 3000 is Rails'
default; it is called "a dev server on the conventional Node.js port".

## Confidence

Confidence is the strongest match's score, plus 5% when a *different*
candidate agrees. It is capped at 99%: every signal here is inference, and
presenting any of it as certainty would be dishonest.

| Signal | Confidence |
|---|---|
| `manage.py runserver` | 95% |
| Process + corroborating HTTP header | 99% |
| `X-Powered-By: Express` on a Node process | 85% |
| A bare `node` process | 55% |
| Unrecognised but answering HTTP | 35% |
| A well-known port with no other evidence | ≤ 50% |

## Project attribution

The working directory is walked up to the nearest manifest (`package.json`,
`pyproject.toml`, `go.mod`, `Cargo.toml`, …). A server running from
`…/acme-web/src/server` is attributed to `acme-web`, not `server`. Paths under
system container roots (`~/Library/Containers/…/Data`) are explicitly *not*
reported as projects — "Data" is noise, not a project name.

## Verification

25 self-checks, including the ones that caught real bugs during development:

- `serve` matching `manage.py runserver` → led to the `all:` combinator.
- `node_modules/.bin/vite` resolving to a different argv path → led to
  `argumentPathSuffix`.
- Corroboration raising "Node.js" above "HTTP API" for an unidentified port →
  led to the different-candidate rule.

Live output on this machine:

```
PORT   PROCESS             SERVICE                     PROJECT
3000   node                Express (85%)               redis-node
3425   magpie              HTTP API (35%)              -
5000   ControlCenter       AirPlay Receiver (99%)      -
18789  node                Node.js (55%)               .openclaw
63247  redis-server        Redis (95%)                 redis-node
```

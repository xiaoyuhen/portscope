# Compatibility matrix

A port monitor is only as good as its answers on real servers. These suites
start real servers, check what PortScope reports, then stop each one *through
PortScope* and confirm the port is free.

There are two, and they answer different questions.

## Portable suite — runs anywhere, including CI

```bash
scripts/compat/fixtures.sh          # all cases
scripts/compat/fixtures.sh express  # cases whose name matches
```

Writes its own fixtures into a temp directory and runs them with the Python and
Node already on macOS. Nothing is installed, nothing is downloaded, and nothing
outside this repository is needed — which is what makes it runnable in CI.

| Case | What it is | Signal it tests |
|---|---|---|
| `express-header` | Node server sending `X-Powered-By: Express` | HTTP tier identifies from a header alone |
| `plain-node` | Framework-less Node HTTP server | no framework is invented; honest generic label |
| `python-http-server` | Python's built-in static server, loopback-bound | process tier from argv, plus exposure |
| `project-directory` | Node server started inside a `package.json` directory | project attribution |

Results on a clean run:

```
PASS  express-header      {"title": "Express", "kind": "api", "exposure": "loopback"}
PASS  plain-node          {"title": "Node.js", "kind": "web", "process": "node"}
PASS  python-http-server  {"title": "Python http.server", "kind": "web", "exposure": "loopback"}
PASS  project-directory   {"title": "Node.js", "kind": "web", "project": "project"}
```

Each case also asserts that `PortScope --stop` actually frees the port.

## Local suite — real projects on a developer machine

```bash
scripts/compat/run.sh            # all cases
scripts/compat/run.sh vite       # cases whose name matches
```

This one is not in CI because it depends on projects that exist only on a
particular machine (`$CODE_DIR`, default `~/Documents/code`). It is the more
demanding check: real Vite, real monorepo, real dependency trees.

| Case | What it is | Started with | Port |
|---|---|---|---|
| `rate-limiter` | Express API with an ephemeral Redis child | `npm run dev` | 3101 |
| `vite-dev-server` | Vite dev server with HMR websocket | `npx vite` | 3102 |
| `python-http-server` | Python's built-in static server | `python3 -m http.server` | 3103 |
| `interview-sandbox` | Framework-less Node HTTP server | `node server.js` | 3104 |
| `monorepo-api` | Express BFF in a monorepo with a Vite app | `npx tsx src/index.ts` | 3001 |

## What the local suite found

Recorded because each of these was a real defect, not a hypothetical:

| Case | Reported as | Kind | Confidence | Exposure |
|---|---|---|---|---|
| rate-limiter | Express | API | 85% | all interfaces |
| vite-dev-server | Vite | dev server | 95% | loopback |
| python-http-server | Python http.server | web | 95% | loopback |
| interview-sandbox | Node.js | web | 55% | loopback |
| monorepo-api | Express | API | 85% | all interfaces |

Defects it caught during development:

- **Vite not recognised** because `node_modules/.bin/vite` resolves to a
  different argv path than the one the fingerprint expected. Fixed by matching
  an argument path *suffix* rather than an exact path.
- **`serve` fingerprint matched `manage.py runserver`**, mislabelling Django
  projects. Fixed by splitting fingerprints into `all:` (every signal must
  match) and `any:` (one is enough) combinators.
- **Corroboration inflated vague answers**, letting a generic "Node.js" outrank
  a specific "HTTP API". Fixed so only a *different* agreeing candidate raises
  confidence.

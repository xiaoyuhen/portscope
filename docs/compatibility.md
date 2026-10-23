# Compatibility matrix

A port monitor is only as good as its answers on real servers. This matrix
starts real projects from this machine, checks what PortScope reports, then
stops each one through PortScope and confirms the port is free.

Run it with:

```bash
scripts/compat/run.sh            # all cases
scripts/compat/run.sh vite       # cases whose name matches
```

## Cases

| Case | What it is | Started with | Port |
|---|---|---|---|
| `rate-limiter` | Express API with an ephemeral Redis child | `npm run dev` | 3101 |
| `vite-dev-server` | Vite dev server with HMR websocket | `npx vite` | 3102 |
| `python-http-server` | Python's built-in static server | `python3 -m http.server` | 3103 |
| `interview-sandbox` | Framework-less Node HTTP server | `node server.js` | 3104 |
| `monorepo-api` | Express BFF in a monorepo with a Vite app | `npx tsx src/index.ts` | 3001 |

## Results

| Case | Reported as | Kind | Confidence | Exposure |
|---|---|---|---|---|
| rate-limiter | Express | API | 85% | all interfaces |
| vite-dev-server | Vite | dev server | 95% | loopback |
| python-http-server | Python http.server | web | 95% | loopback |
| interview-sandbox | Node.js | web | 55% | loopback |
| monorepo-api | Express | API | 85% | all interfaces |

Every case also passes the action half: `--stop <port>` succeeds and the port
is no longer listening afterwards.

## What each case proves

- **rate-limiter** — the project this app was built against. Exercises an API
  behind a framework whose argv says only `scripts/dev.js`, plus a child process
  (the ephemeral Redis) that must not be left behind.
- **vite-dev-server** — the classic case. The process is `node`, the framework
  is only visible as a resolved script path in argv
  (`…/node_modules/vite/bin/vite.js`), and the port is a well-known one, so a
  port-only guess would also have "worked" — the argv match is what makes it
  95% rather than 40%.
- **python-http-server** — confirms the exposure model: bound to loopback, so it
  is reported as `loopback`, not flagged as network-reachable.
- **interview-sandbox** — no framework anywhere. PortScope says "Node.js, 55%"
  rather than inventing an answer, which is the intended behaviour.
- **monorepo-api** — two services in one repo, started separately, identified
  separately. A naive scanner reports both as "node" and cannot tell them apart.

## Adding a case

Add a `run_case` line. Expectations are `field=value` or `field~substring` over
the service description (`title`, `kind`, `confidence`, `project`, `exposure`,
`process`). Keep the port unusual so the well-known-port tier cannot mask a
process-tier failure.

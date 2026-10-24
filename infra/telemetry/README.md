# Telemetry receiver

A Cloudflare Worker that counts app launches. The app side is
[`Telemetry.swift`](../../Sources/PortScope/App/Telemetry.swift); the privacy
promise is [docs/privacy.md](../../docs/privacy.md).

## Why this exists

A macOS app distributed as a GitHub release has no download counter you can
trust as usage: someone can clone the repo, build it themselves, or copy the
`.app` from a friend. Release download counts get you part of the way (and need
no infrastructure at all — see "If you skip this" below), but they cannot tell
you whether the app is actually *opened*.

So the app sends one event, at most once per version per day.

## What is stored

One KV key per day, `day:YYYY-MM-DD`, holding:

```json
{
  "day": "2026-10-24",
  "launches": 12,
  "installs": { "<random uuid>": 1, ... },
  "versions": { "0.2.0": 11, "0.1.0": 1 },
  "platforms": { "14.5/arm64": 12 }
}
```

No IP address is read or written. `request.headers.get("CF-Connecting-IP")` is
never called. The `installs` map exists only so `/v1/stats` can report distinct
installs; it holds random per-install UUIDs and nothing else.

## Deploying

Requires a Cloudflare account and `wrangler`.

```bash
npm install -g wrangler
wrangler login

cd infra/telemetry
wrangler kv namespace create PORTSCOPE_TELEMETRY
# Copy the printed id into wrangler.toml, replacing __KV_NAMESPACE_ID__.

wrangler deploy
```

`wrangler deploy` prints the worker's URL. Point the app at it:

```bash
PORTSCOPE_TELEMETRY_URL=https://portscope-telemetry.<account>.workers.dev/v1/launch \
  ./scripts/build.sh --release
```

The URL is baked into `Info.plist` at build time by `scripts/build.sh`; leaving
`PORTSCOPE_TELEMETRY_URL` unset produces a build that never sends anything.

## Reading the numbers

```bash
curl https://portscope-telemetry.<account>.workers.dev/v1/stats?days=30
```

```json
{
  "window": { "days": 30 },
  "launches": 128,
  "installs": 41,
  "versions": { "0.2.0": 120, "0.1.0": 8 },
  "platforms": { "14.5/arm64": 128 }
}
```

## If you skip this

Two options, both fine:

1. **Release download counts.** Every download of a release asset is counted by
   GitHub and readable through the API — no infrastructure, no code:

   ```bash
   gh api repos/xiaoyuhen/portscope/releases/latest \
     --jq '.assets[] | "\(.name): \(.download_count)"'
   ```

   This is what `.github/workflows/usage-report.yml` posts monthly.

2. **Do nothing.** Build without `PORTSCOPE_TELEMETRY_URL` and the app has no
   endpoint to call. `Telemetry.isEnabled` also honours
   `PORTSCOPE_NO_TELEMETRY=1` at runtime.

## Cost

Workers free tier: 100,000 requests/day. KV free tier: 100,000 reads and 1,000
writes/day. At one event per install per day, this is far outside the range
where it costs anything.

## Testing locally

```bash
cd infra/telemetry
wrangler dev --local
curl -X POST http://localhost:8787/v1/launch \
  -H 'content-type: application/json' \
  -d '{"event":"launch","app":"PortScope","version":"0.2.0","os":"14.5","arch":"arm64","id":"test-1"}'
curl http://localhost:8787/v1/stats?days=1
```

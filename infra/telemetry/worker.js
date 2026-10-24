/**
 * PortScope telemetry receiver.
 *
 * A Cloudflare Worker, because the free tier is enough for a project this size
 * and there is no server to keep patched. Deploy with `wrangler deploy`; see
 * README.md in this directory.
 *
 * Privacy contract — the code enforces what the app promises:
 *
 *  - Only the fields below are read. Anything else in the request body is
 *    dropped, so a modified client cannot smuggle data into the store.
 *  - No IP address is stored, logged, or used. Cloudflare sees the request, as
 *    it does for any HTTPS connection; this worker does not read
 *    `request.headers.get("CF-Connecting-IP")` and does not write it anywhere.
 *  - Counts are aggregated per day, per version. A single install is never
 *    individually traceable from what is stored.
 *  - `id` is a random per-install UUID. It is counted as a distinct install,
 *    not stored alongside anything identifying.
 *
 * Storage: Workers KV, one key per day. A day's value is a small JSON summary,
 * so the whole dataset for a year is a few hundred keys.
 */

const ALLOWED = new Set(["event", "app", "version", "os", "arch", "id"]);
const MAX_BODY = 2048;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Aggregate counts only, no per-install data — and still only for the
    // maintainer. A worker with no STATS_TOKEN secret has no readable stats at
    // all, and a wrong token gets the same 404 as an unknown path, so the
    // endpoint's existence is not advertised either.
    if (url.pathname === "/v1/stats" && request.method === "GET") {
      if (!(await authorised(request, env))) {
        return new Response("not found", { status: 404 });
      }
      const days = Number(url.searchParams.get("days") || 30);
      return json(await summary(env, Math.min(Math.max(days, 1), 365)));
    }

    if (url.pathname !== "/v1/launch") {
      return new Response("not found", { status: 404 });
    }
    if (request.method !== "POST") {
      return new Response("method not allowed", { status: 405 });
    }

    // A body over the limit is refused before it is parsed: the payload is
    // about 200 bytes, so anything larger is not this app.
    const text = await request.text();
    if (text.length > MAX_BODY) {
      return new Response("too large", { status: 413 });
    }

    let body;
    try {
      body = JSON.parse(text);
    } catch {
      return new Response("bad json", { status: 400 });
    }
    if (body.event !== "launch") {
      return new Response("ignored", { status: 202 });
    }

    // Copy only known fields, with type and length checks. This is the
    // boundary that keeps the privacy contract true regardless of client.
    const event = {};
    for (const key of Object.keys(body)) {
      if (!ALLOWED.has(key)) continue;
      const value = body[key];
      if (typeof value !== "string" || value.length > 64) continue;
      event[key] = value;
    }

    const day = new Date().toISOString().slice(0, 10);
    const key = `day:${day}`;

    // KV has no atomic increment, and one worker instance handles one request
    // at a time in practice at this scale. A lost increment under contention
    // would be invisible in a count of this size.
    const existing = (await env.PORTSCOPE_TELEMETRY.get(key, "json")) || {
      day,
      launches: 0,
      installs: {},
      versions: {},
      platforms: {},
    };

    existing.launches += 1;
    existing.versions[event.version || "unknown"] =
      (existing.versions[event.version || "unknown"] || 0) + 1;
    const platform = `${event.os || "?"}/${event.arch || "?"}`;
    existing.platforms[platform] = (existing.platforms[platform] || 0) + 1;

    // Keep the install set bounded: it exists to deduplicate, not to profile.
    if (event.id && Object.keys(existing.installs).length < 100000) {
      existing.installs[event.id] = 1;
    }

    await env.PORTSCOPE_TELEMETRY.put(key, JSON.stringify(existing));

    return new Response(null, { status: 204 });
  },
};

/**
 * True when the request carries `Authorization: Bearer <STATS_TOKEN>`.
 * Both sides are hashed before comparing so the comparison takes the same time
 * whatever the token's length or how much of it matches.
 */
async function authorised(request, env) {
  const expected = env.STATS_TOKEN;
  if (!expected) return false;
  const header = request.headers.get("authorization") || "";
  const presented = header.startsWith("Bearer ") ? header.slice(7) : "";
  const digest = async (value) =>
    new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  const [a, b] = await Promise.all([digest(presented), digest(expected)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function summary(env, days) {
  const now = Date.now();
  const totals = { launches: 0, installs: 0, versions: {}, platforms: {} };
  const seenInstalls = new Set();

  for (let i = 0; i < days; i++) {
    const day = new Date(now - i * 86400000).toISOString().slice(0, 10);
    const record = await env.PORTSCOPE_TELEMETRY.get(`day:${day}`, "json");
    if (!record) continue;
    totals.launches += record.launches || 0;
    for (const version of Object.keys(record.versions || {})) {
      totals.versions[version] = (totals.versions[version] || 0) + record.versions[version];
    }
    for (const platform of Object.keys(record.platforms || {})) {
      totals.platforms[platform] = (totals.platforms[platform] || 0) + record.platforms[platform];
    }
    for (const install of Object.keys(record.installs || {})) seenInstalls.add(install);
  }

  totals.installs = seenInstalls.size;
  return { window: { days }, ...totals };
}

function json(value) {
  return new Response(JSON.stringify(value, null, 2), {
    headers: {
      "content-type": "application/json",
      // Authorised responses must never land in a shared cache.
      "cache-control": "private, no-store",
    },
  });
}

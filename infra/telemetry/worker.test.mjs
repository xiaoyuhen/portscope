// Tests for the telemetry worker, run with plain Node — no test framework, no
// dependencies, so CI needs nothing beyond the Node that ships with macOS.
//
//   node infra/telemetry/worker.test.mjs
//
// What is actually being checked is the privacy contract: the worker must drop
// every field it does not recognise, so a modified client cannot store local
// data (a port, a path) on the receiver.

import worker from "./worker.js";

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`${ok ? "  ok  " : " FAIL "} ${label}` +
    (ok ? "" : ` — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`));
}

// A Workers KV stub. The "json" type argument parses, as the real binding does.
function makeEnv() {
  const store = new Map();
  return {
    store,
    env: {
      PORTSCOPE_TELEMETRY: {
        async get(key, type) {
          const value = store.get(key);
          if (value == null) return null;
          return type === "json" ? JSON.parse(value) : value;
        },
        async put(key, value) { store.set(key, value); },
      },
      STATS_TOKEN: "test-token",
    },
  };
}

const { store, env } = makeEnv();

const launch = (overrides = {}) => ({
  event: "launch", app: "PortScope", version: "0.2.0",
  os: "14.5", arch: "arm64", id: "install-a", ...overrides,
});

const post = (body, path = "/v1/launch") =>
  worker.fetch(new Request(`https://x${path}`, {
    method: "POST",
    body: typeof body === "string" ? body : JSON.stringify(body),
  }), env);

const get = (path, token = "test-token") => worker.fetch(new Request(`https://x${path}`, {
  headers: token ? { authorization: `Bearer ${token}` } : {},
}), env);
const dayKey = () => [...store.keys()].find((k) => k.startsWith("day:"));

// 1. A launch is accepted and counted.
check("a launch returns 204", (await post(launch())).status, 204);

// 2. The privacy contract: unrecognised fields never reach storage.
await post(launch({ id: "install-b", port: "3000", cwd: "/secret", process: "node" }));
const record = JSON.parse(store.get(dayKey()));
check("only documented fields are stored",
  Object.keys(record).sort(), ["day", "installs", "launches", "platforms", "versions"]);
check("a port does not reach storage", JSON.stringify(record).includes("3000"), false);
check("a path does not reach storage", JSON.stringify(record).includes("/secret"), false);
check("a process name does not reach storage", JSON.stringify(record).includes("node"), false);
check("both launches counted", record.launches, 2);
check("both installs recorded", Object.keys(record.installs).length, 2);

// 3. An event this worker does not handle is acknowledged but not counted.
const beforeOther = JSON.parse(store.get(dayKey())).launches;
check("an unknown event returns 202", (await post({ event: "other" })).status, 202);
check("an unknown event is not counted",
  JSON.parse(store.get(dayKey())).launches, beforeOther);

// 4. An oversized body is refused before parsing.
check("an oversized body returns 413", (await post("x".repeat(3000))).status, 413);

// 5. Malformed JSON is refused.
check("malformed JSON returns 400", (await post("{not json")).status, 400);

// 6. Stats aggregate without exposing installs.
const stats = await (await get("/v1/stats?days=1")).json();
check("stats report launches", stats.launches, 2);
check("stats report distinct installs", stats.installs, 2);
check("stats report versions", stats.versions, { "0.2.0": 2 });
check("stats do not list install ids", JSON.stringify(stats).includes("install-a"), false);

// 7. Unknown paths and methods.
check("an unknown path returns 404", (await get("/nope")).status, 404);
check("GET on /v1/launch returns 405",
  (await worker.fetch(new Request("https://x/v1/launch"), env)).status, 405);

// 8. The same install twice is one install, two launches.
await post(launch());
const repeat = JSON.parse(store.get(dayKey()));
check("a repeat launch counts twice", repeat.launches, 3);
check("a repeat install counts once", Object.keys(repeat.installs).length, 2);

// 9. The stats window bounds are clamped rather than trusted.
const clamped = await (await get("/v1/stats?days=100000")).json();
check("an absurd window is clamped to 365", clamped.window.days, 365);

// 10. Stats are private: no token, a wrong token, or no secret configured all
// look like an unknown path.
check("stats without a token are 404", (await get("/v1/stats", null)).status, 404);
check("stats with a wrong token are 404", (await get("/v1/stats", "nope")).status, 404);
check("stats with a token prefix are 404", (await get("/v1/stats", "test")).status, 404);
check("stats without a configured secret are 404",
  (await worker.fetch(new Request("https://x/v1/stats", {
    headers: { authorization: "Bearer " },
  }), { ...env, STATS_TOKEN: undefined })).status, 404);
check("authorised stats are not cached",
  (await get("/v1/stats")).headers.get("cache-control"), "private, no-store");

console.log(failures === 0 ? "\nworker: all checks passed" : `\nworker: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);

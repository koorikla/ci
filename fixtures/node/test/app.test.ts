import assert from "node:assert/strict";
import { test } from "node:test";

import { buildApp, greet } from "../src/app.js";

test("greet", () => {
  assert.equal(greet("koorikla"), "hello, koorikla");
  assert.equal(greet("  "), "hello, world");
});

test("GET / and /healthz", async () => {
  const app = buildApp();
  const res = await app.inject({ method: "GET", url: "/?name=ci" });
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().message, "hello, ci");
  const health = await app.inject({ method: "GET", url: "/healthz" });
  assert.equal(health.body, "ok");
  await app.close();
});

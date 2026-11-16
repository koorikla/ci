import Fastify, { type FastifyInstance } from "fastify";

export function greet(name?: string): string {
  const n = (name ?? "").trim();
  return `hello, ${n === "" ? "world" : n}`;
}

export function buildApp(): FastifyInstance {
  const app = Fastify({ logger: process.env.NODE_ENV === "production" });
  app.get("/healthz", async () => "ok");
  app.get<{ Querystring: { name?: string } }>("/", async (req) => ({
    message: greet(req.query.name),
    version: process.env.VERSION ?? "dev",
  }));
  return app;
}

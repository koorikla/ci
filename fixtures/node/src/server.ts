import { buildApp } from "./app.js";

const app = buildApp();
const port = Number(process.env.PORT ?? 8080);
await app.listen({ host: process.env.HOST ?? "0.0.0.0", port });

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    void app.close().then(() => process.exit(0));
  });
}

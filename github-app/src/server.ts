// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

import http from "node:http";
import { App, createNodeMiddleware } from "octokit";
import { config } from "./config.js";
import { registerHandlers } from "./handlers/index.js";

const app = new App({
  appId: config.appId,
  privateKey: config.privateKey,
  webhooks: { secret: config.webhookSecret },
});

registerHandlers(app);

const webhookPath = "/api/github/webhooks";
const middleware = createNodeMiddleware(app, { pathPrefix: webhookPath });

http
  .createServer(async (req, res) => {
    if (await middleware(req, res)) {
      return;
    }
    if (req.url === "/health") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("ok\n");
      return;
    }
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found\n");
  })
  .listen(config.port, () => {
    console.log(`dev-control github app listening on :${config.port} (${webhookPath})`);
  });

# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience
#
# The worker shells out to ../scripts/fix-history.sh, so the image needs git +
# bash + the dev-control scripts present. Build from the repo root:
#   docker build -f github-app/Dockerfile -t dev-control-github-app .

FROM node:22-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git bash gnupg ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/dev-control

# Bring in the dev-control scripts the worker invokes
COPY scripts ./scripts

# Install and build the app
WORKDIR /opt/dev-control/github-app
COPY github-app/package.json github-app/package-lock.json* ./
RUN npm install --omit=dev || npm install
COPY github-app/ ./
RUN npm run build

ENV NODE_ENV=production \
    DC_FIX_HISTORY=/opt/dev-control/scripts/fix-history.sh \
    PORT=3000
EXPOSE 3000

CMD ["node", "dist/server.js"]

FROM node:22-alpine

WORKDIR /app

COPY web/package.json web/package-lock.json ./web/
COPY web/apps/site/package.json ./web/apps/site/package.json
COPY web/packages/ingestion-platform/package.json ./web/packages/ingestion-platform/package.json

RUN cd web && npm ci --workspace @vamo/ingestion-platform

COPY web/packages/ingestion-platform ./web/packages/ingestion-platform

RUN cd web && npm --workspace @vamo/ingestion-platform run build

WORKDIR /app/web

CMD ["npm", "--workspace", "@vamo/ingestion-platform", "run", "worker"]

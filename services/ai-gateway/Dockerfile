# Multi-stage build for the MILO AI gateway.
# Usage:
#   docker build -t milo-gateway ./services/ai-gateway
#   docker run --rm -p 8787:8787 --env-file ./services/ai-gateway/.env milo-gateway

FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

FROM node:20-alpine AS build
WORKDIR /app
COPY package.json tsconfig.json ./
COPY src ./src
RUN npm install --no-audit --no-fund \
 && npx tsc -p tsconfig.json

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8787
ENV HOST=0.0.0.0
COPY --from=deps  /app/node_modules ./node_modules
COPY --from=build /app/dist         ./dist
COPY package.json ./
EXPOSE 8787
USER node
CMD ["node", "dist/main.js"]

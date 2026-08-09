FROM node:22-alpine AS build

WORKDIR /app
COPY package.json package-lock.json ./
COPY server/package.json ./server/package.json
RUN npm ci

COPY contracts ./contracts
COPY server ./server
RUN npm --workspace study-room-server run db:generate \
    && npm --workspace study-room-server run build

FROM node:22-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/contracts ./contracts
COPY --from=build /app/server/dist ./server/dist
COPY --from=build /app/server/node_modules ./server/node_modules
COPY --from=build /app/server/package.json ./server/package.json
COPY --from=build /app/server/prisma ./server/prisma
COPY --from=build /app/server/tool ./server/tool
WORKDIR /app/server
RUN node -e "require('./dist/telemetry.js')"
USER node
CMD ["node", "dist/main.js"]

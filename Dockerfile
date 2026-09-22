FROM node:20-bookworm-slim
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY backend/package.json ./package.json
COPY backend/prisma ./prisma
RUN npm install --no-audit --no-fund

COPY backend/src ./src
ENV NODE_ENV=production
EXPOSE 10000
CMD ["npm", "start"]

FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src
COPY schema.postgres.full.sql ./schema.postgres.full.sql
ENV NODE_ENV=production
EXPOSE 5521
CMD ["node", "src/server.js"]

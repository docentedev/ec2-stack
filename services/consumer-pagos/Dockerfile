FROM node:22-alpine
WORKDIR /app

ENV NODE_ENV=production

# Primero las dependencias para aprovechar la cache de capas de Docker
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY index.js server.js ./

EXPOSE 8083
USER node
CMD ["node", "server.js"]

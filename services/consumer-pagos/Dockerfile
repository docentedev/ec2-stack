# node:22-alpine es la imagen oficial de Node más pequeña y funcional
# (incluye npm). No existe variante oficial menor con shell.
FROM node:22-alpine
WORKDIR /app

ENV NODE_ENV=production

# Primero las dependencias para aprovechar la cache de capas de Docker.
# cache clean evita dejar el cache de descargas de npm dentro de la imagen.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY index.js server.js kafka-consumer.js ./

EXPOSE 8083
USER node
CMD ["node", "server.js"]

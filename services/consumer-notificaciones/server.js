// Punto de entrada del servicio: monta el router de index.js y levanta el servidor HTTP.
const express = require("express");
const routes = require("./index.js");

const app = express();
const PORT = process.env.PORT || 8082;
const SERVICE_NAME = process.env.SERVICE_NAME || "consumer-notificaciones";

app.use(routes);

app.listen(PORT, () => {
  console.log(`${SERVICE_NAME} escuchando en http://0.0.0.0:${PORT}`);
});

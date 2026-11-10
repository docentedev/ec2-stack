// Punto de entrada del servicio: monta el router de index.js y levanta el servidor HTTP.
const express = require("express");
const routes = require("./index.js");

const app = express();
const PORT = process.env.PORT || 8081;
const SERVICE_NAME = process.env.SERVICE_NAME || "consumer-analiticas";

app.use(routes);

app.listen(PORT, () => {
  console.log(`${SERVICE_NAME} escuchando en http://0.0.0.0:${PORT}`);
});

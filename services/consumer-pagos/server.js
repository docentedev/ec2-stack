// Punto de entrada del servicio: monta el router de index.js, levanta el
// servidor HTTP y arranca el consumidor kafka (topico pagos, grupo propio).
const express = require("express");
const routes = require("./index.js");
const { startKafkaConsumer } = require("./kafka-consumer.js");

const app = express();
const PORT = process.env.PORT || 8083;
const SERVICE_NAME = process.env.SERVICE_NAME || "consumer-pagos";

app.use(routes);

app.listen(PORT, () => {
  console.log(`${SERVICE_NAME} escuchando en http://0.0.0.0:${PORT}`);
  startKafkaConsumer(); // no bloquea; reconecta solo si kafka no esta listo
});

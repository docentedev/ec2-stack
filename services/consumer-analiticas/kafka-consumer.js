// Consumidor Kafka del servicio.
// Lee la config de variables de entorno (definidas en docker-compose.yml):
//   KAFKA_BOOTSTRAP_SERVERS (default kafka:9092)
//   KAFKA_GROUP_ID          (default analiticas)  <- cada servicio tiene su grupo: fan-out
//   KAFKA_TOPIC             (default pagos)
// Al recibir un mensaje lo loguea en consola (ver README: mensajería kafka).
const { Kafka } = require("kafkajs");

const SERVICE_NAME = process.env.SERVICE_NAME || "consumer-analiticas";
const KAFKA_BOOTSTRAP_SERVERS = process.env.KAFKA_BOOTSTRAP_SERVERS || "kafka:9092";
const KAFKA_GROUP_ID = process.env.KAFKA_GROUP_ID || "analiticas";
const KAFKA_TOPIC = process.env.KAFKA_TOPIC || "pagos";

function log(msg) {
  console.log(`[${SERVICE_NAME}] ${msg}`);
}

async function connectWithRetry() {
  const maxAttempts = 30; // kafka puede tardar unos segundos tras compose up
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const kafka = new Kafka({
        clientId: SERVICE_NAME,
        brokers: [KAFKA_BOOTSTRAP_SERVERS],
      });
      const consumer = kafka.consumer({ groupId: KAFKA_GROUP_ID });

      await consumer.connect();
      await consumer.subscribe({ topic: KAFKA_TOPIC, fromBeginning: false });
      await consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          log(
            `kafka <- topic=${topic} grupo=${KAFKA_GROUP_ID} ` +
              `partition=${partition} offset=${message.offset} ` +
              `mensaje=${message.value.toString()}`
          );
        },
      });

      log(
        `consumidor kafka activo: brokers=${KAFKA_BOOTSTRAP_SERVERS} ` +
          `topic=${KAFKA_TOPIC} grupo=${KAFKA_GROUP_ID}`
      );
      return;
    } catch (err) {
      log(`kafka no disponible (intento ${attempt}/${maxAttempts}): ${err.message || err}`);
      await new Promise((resolve) => setTimeout(resolve, 5000));
    }
  }
  log("kafka no disponible tras varios intentos; el health sigue en linea");
}

function startKafkaConsumer() {
  connectWithRetry().catch((err) => log(`error inesperado en consumidor kafka: ${err}`));
}

module.exports = { startKafkaConsumer };

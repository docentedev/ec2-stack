// Consumidor Kafka del servicio.
// Lee la config de variables de entorno (definidas en docker-compose.yml):
//   KAFKA_BOOTSTRAP_SERVERS (default kafka:9092)
//   KAFKA_GROUP_ID          (default pagos)  <- cada servicio tiene su grupo: fan-out
//   KAFKA_TOPIC             (default pagos)
// Al recibir un mensaje lo loguea en consola (ver README: mensajería kafka).
const { Kafka } = require("kafkajs");
const { DynamoDBClient, PutItemCommand } = require("@aws-sdk/client-dynamodb");

const SERVICE_NAME = process.env.SERVICE_NAME || "consumer-pagos";
const dynamoDBClient = new DynamoDBClient({
  region: process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || "us-east-2",
});
const KAFKA_BOOTSTRAP_SERVERS = process.env.KAFKA_BOOTSTRAP_SERVERS || "kafka:9092";
const KAFKA_GROUP_ID = process.env.KAFKA_GROUP_ID || "pagos";
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

          // ---- Persistencia en DynamoDB (idempotente: PK unica = topico-particion-offset)
          const pk = `${topic}-${partition}-${message.offset}`;
          const params = {
            TableName: KAFKA_GROUP_ID, // tabla con el nombre del grupo (pagos/notificaciones/analiticas)
            Item: {
              PK: { S: pk },
              mensaje: { S: message.value.toString() },
              origen: { S: "api" },
              fecha: { S: new Date().toISOString() },
            },
            ConditionExpression: "attribute_not_exists(PK)",
          };
          try {
            await dynamoDBClient.send(new PutItemCommand(params));
            log(`guardado en dynamodb: tabla=${KAFKA_GROUP_ID} pk=${pk}`);
          } catch (err) {
            if (err.name === "ConditionalCheckFailedException") {
              log(`duplicado ignorado (idempotente): pk=${pk}`);
            } else {
              log(`error al guardar en dynamodb: ${err.message || err}`);
            }
          }
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

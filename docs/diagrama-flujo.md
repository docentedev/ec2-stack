# Flujo end-to-end: `/topic-test` → Kafka → consumers → DynamoDB

## Arquitectura

```mermaid
flowchart LR
    U([Cliente<br/>curl / e2e-dynamo.sh]) -->|"GET :8080/topic-test?msj=X"| API

    subgraph EC2["EC2 · Docker Compose (us-east-2)"]
        API["api<br/>Spring Boot · Producer<br/>:8080"]

        subgraph K["Kafka (KRaft)"]
            T[("tópico: pagos<br/>partición 0")]
        end

        subgraph G["Consumer groups (cada grupo recibe TODOS los mensajes)"]
            C1["consumer-pagos<br/>group: pagos · :8083"]
            C2["consumer-notificaciones<br/>group: notificaciones · :8082"]
            C3["consumer-analiticas<br/>group: analiticas · :8081"]
        end

        UI["kafka-ui :8084"] -.->|monitorea| K

        API -->|"produce<br/>(devuelve partición + offset)"| T
        T -->|poll| C1
        T -->|poll| C2
        T -->|poll| C3
    end

    subgraph AWS["AWS DynamoDB (PAY_PER_REQUEST)"]
        D1[("tabla pagos")]
        D2[("tabla notificaciones")]
        D3[("tabla analiticas")]
    end

    C1 -->|"PutItem<br/>PK = pagos-part-offset<br/>attribute_not_exists(PK)"| D1
    C2 -->|PutItem| D2
    C3 -->|PutItem| D3

    API -. "{status, particion, offset}" .-> U
    U -. "get-item / scan COUNT<br/>(AWS CLI)" .-> AWS
```

## Secuencia

```mermaid
sequenceDiagram
    autonumber
    actor U as Cliente
    participant A as api (Producer)
    participant K as Kafka · tópico pagos
    participant C as consumer-* (x3 grupos)
    participant D as DynamoDB (tabla = grupo)

    U->>A: GET /topic-test?msj=X
    A->>K: send(pagos, {mensaje:X, origen:api, fecha})
    K-->>A: ack (partición, offset)
    A-->>U: {"status":"enviado","particion":0,"offset":N}

    par grupo pagos
        K->>C: eachMessage → consumer-pagos
        C->>D: PutItem(tabla pagos, PK=pagos-0-N)
    and grupo notificaciones
        K->>C: eachMessage → consumer-notificaciones
        C->>D: PutItem(tabla notificaciones, PK=pagos-0-N)
    and grupo analiticas
        K->>C: eachMessage → consumer-analiticas
        C->>D: PutItem(tabla analiticas, PK=pagos-0-N)
    end

    alt PK nueva
        D-->>C: OK → log "guardado en dynamodb"
    else PK ya existe (reintento / reentrega)
        D-->>C: ConditionalCheckFailed → log "duplicado ignorado"
    end

    U->>D: aws dynamodb get-item / scan COUNT (validación)
```

## Notas

- **Idempotencia:** la clave `PK = <tópico>-<partición>-<offset>` es única por mensaje; `attribute_not_exists(PK)` evita duplicados si Kafka reentrega.
- **Un item por tabla:** cada grupo de consumers tiene su propia tabla (nombre = `KAFKA_GROUP_ID`), por eso un mensaje genera 3 items.
- **Credenciales:** `deploy.sh` exporta `AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN` a `docker compose`; si hay instance profile en la EC2, el SDK lo usa como fallback.
- **Validación:** `scripts/e2e-dynamo.sh` ejecuta todo este flujo y compara el conteo de items antes/después.

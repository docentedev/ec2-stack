# Proyecto Final – Cloud (Sistema de microservicios en EC2)

Sistema basado en microservicios desplegado en **una única instancia EC2 de AWS**, completamente dockerizado con **Docker Compose**.

## Arquitectura

| Servicio              | Puerto | Tecnología                     | Estado actual             |
| --------------------- | ------ | ------------------------------ | ------------------------- |
| api                   | 8080   | Java 21 + Spring Boot 4 (Gradle) | Solo `GET /health`        |
| consumer-analiticas   | 8081   | Node.js + Express              | Solo `GET /health`        |
| consumer-notificaciones | 8082 | Node.js + Express              | Solo `GET /health`        |
| consumer-pagos        | 8083   | Node.js + Express              | Solo `GET /health`        |
| kafka                 | 9092   | Kafka                          | Broker de mensajería      |
| kafka-ui              | 8084   | Kafka UI                       | UI de administración      |

> **Nota:** el puerto de kafka-ui está propuesto en 8084 (su default es 8080, que choca con `api`).

## Estructura del repositorio

```
proyectoFinal/
├── README.md
├── scripts/                  # Scripts de despliegue y operación
│   ├── deploy.sh             # (a generar) despliegue completo en EC2
│   └── cleanup.sh            # (a generar) limpieza del stack anterior sin docker
└── services/
    ├── api/                  # Spring Boot (Java 21, Gradle)
    ├── consumer-analiticas/  # Node.js + Express
    ├── consumer-notificaciones/ # Node.js + Express
    └── consumer-pagos/       # Node.js + Express
```

Pendiente a generar en la raíz:

- `docker-compose.yml` (servicios + kafka + kafka-ui)
- `Dockerfile` por cada servicio
- `.env` / variables de entorno

## Infraestructura

- **1 instancia EC2** (única) en AWS.
- Hoy el EC2 tiene corriendo **sin Docker** un proyecto Java + Spring Boot desplegado directamente sobre el sistema operativo.
- **Objetivo:** partir de cero — limpiar lo que corre hoy y desplegar el stack nuevo 100% dockerizado con `docker-compose`.

## Despliegue

- Se despliega con `scripts/deploy.sh` (a futuro existe la versión Windows `deploy.ps1`).
- Utiliza **AWS CLI** + `ssh`/`rsync` para conectar y desplegar en el EC2.
- Kafka y kafka-ui también se levantan como contenedores dentro del mismo compose.

## Reglas del proyecto

1. **Todo se ejecuta con scripts previamente generados** en `./scripts` (nada de comandos sueltos a mano / "por clic").
2. **Cada paso queda documentado en un checklist** (ver abajo).
3. Los cambios al stack se hacen editando `docker-compose.yml` o los Dockerfiles, no tocando el EC2 a mano.

## Checklist de migración (partir de cero en el EC2)

> Marcar cada paso al completarlo.

- [ ] 1. Detectar y detener el proceso Spring Boot que corre hoy sin Docker en el EC2.
- [ ] 2. Liberar los puertos usados por el stack anterior (8080, etc.).
- [ ] 3. Eliminar binarios/jars y artefactos del despliegue anterior (opcional: desinstalar Java).
- [ ] 4. Verificar/instalar Docker y Docker Compose en el EC2.
- [ ] 5. Generar `Dockerfile` por servicio y `docker-compose.yml`.
- [ ] 6. Sincronizar el código del proyecto al EC2 (`rsync`).
- [ ] 7. Levantar el stack completo (`docker compose up -d --build`).
- [ ] 8. Verificar health de cada servicio (`/health` en 8080–8083) y kafka-ui en 8084.
- [ ] 9. Ajustar Security Group de la instancia (puertos según decisión).
- [ ] 10. Documentar resultado del despliegue en este README.

## Decisiones pendientes

- ¿Cómo corre hoy el Spring Boot en el EC2 (systemd, nohup, pm2)? → afecta el script de limpieza.
- ¿Cómo llega el código al EC2 (rsync desde local, git clone, imágenes ECR)?
- ¿Kafka en modo KRaft (sin Zookeeper) o con Zookeeper?
- ¿Qué puertos se exponen en el Security Group?
- ¿Se desinstala Java del EC2 tras dockerizar, o solo se detiene el proceso?

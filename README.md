# Proyecto Final – Cloud (Sistema de microservicios en EC2)

Sistema basado en microservicios desplegado en **una única instancia EC2 de AWS**, completamente dockerizado con **Docker Compose**.

## Arquitectura

| Servicio                 | Puerto | Tecnología                        | Estado actual                  |
| ------------------------ | ------ | --------------------------------- | ------------------------------ |
| api                      | 8080   | Java 21 + Spring Boot 4 (Gradle)  | Solo `GET /health`             |
| consumer-analiticas      | 8081   | Node.js 22 + Express              | Solo `GET /health`             |
| consumer-notificaciones  | 8082   | Node.js 22 + Express              | Solo `GET /health`             |
| consumer-pagos           | 8083   | Node.js 22 + Express              | Solo `GET /health`             |
| kafka                    | 9092   | Apache Kafka 3.9 (KRaft)          | Broker de mensajería (interno) |
| kafka-ui                 | 8084   | Kafka UI                          | UI de administración           |

> Kafka queda **interno** a la red de Docker (los servicios se conectan como `kafka:9092`). Para debugging desde el propio EC2 existe `127.0.0.1:29092`. Kafka-ui usa **8084** porque su default (8080) choca con `api`.

## Estructura del repositorio

```
proyectoFinal/
├── README.md
├── docker-compose.yml        # stack completo: 4 servicios + kafka + kafka-ui
├── .gitignore                # ignora *.pem, node_modules, build, .gradle
├── mi-llave-privada.pem      # llave SSH del EC2 (NUNCA commitear)
├── scripts/
│   ├── config.sh             # EDITAR: IP/DNS del EC2, usuario, región, SG
│   ├── cleanup.sh            # detiene y respalda el stack viejo sin docker
│   ├── deploy.sh             # despliegue completo (limpia + rsync + build + health)
│   ├── verify.sh             # health checks contra la IP pública del EC2
│   └── security-group.sh     # abre puertos en el SG (SSH a tu IP + 8080-8084)
└── services/
    ├── api/                  # Spring Boot (Dockerfile multi-stage)
    ├── consumer-analiticas/  # Node + Express (server.js + Dockerfile)
    ├── consumer-notificaciones/
    └── consumer-pagos/
```

## Imágenes Docker (base mínima funcional)

Cada servicio usa la **imagen oficial más pequeña que sigue siendo funcional y mantenida** para su runtime:

| Servicio             | Imagen base (build)               | Imagen base (runtime)         | Imagen final medida |
| -------------------- | --------------------------------- | ----------------------------- | ------------------- |
| api                  | `eclipse-temurin:21-jdk-alpine`   | `eclipse-temurin:21-jre-alpine` | 324 MB |
| consumer-analiticas  | `node:22-alpine` (mismo)          | `node:22-alpine`              | 243 MB |
| consumer-notificaciones | `node:22-alpine` (mismo)       | `node:22-alpine`              | 243 MB |
| consumer-pagos       | `node:22-alpine` (mismo)          | `node:22-alpine`              | 243 MB |
| kafka                | `apache/kafka:3.9.0`              | —                             | 634 MB |
| kafka-ui             | `provectuslabs/kafka-ui:latest`   | —                             | 411 MB |

Decisiones:

- **api**: multi-stage — el JDK alpine solo existe en la etapa de build (descartada); el runtime lleva solo el JRE alpine. Las variantes `-alpine` de Temurin existen para amd64 y arm64 (cualquier tipo de EC2). `npm cache clean` / capas ordenadas para aprovechar cache de Docker.
- **consumers**: `node:22-alpine` es la imagen oficial de Node más pequeña con npm funcional; se corre con usuario no-root (`USER node`).
- Verificado en Mac ARM64 y portable a EC2 amd64 (t2/t3) o arm64 (t4g).

Si se quisiera reducir aún más (no necesario por ahora):

- api: **jlink** (JRE a medida solo con los módulos que usa Spring) → imagen ~120-150 MB, a costa de un Dockerfile frágil (faltantes de módulos aparecen en runtime).
- consumers: `gcr.io/distroless/nodejs22` → ~150 MB, sin shell (no se puede `docker exec sh` para debuggear).

## Infraestructura

- **1 instancia EC2** (única) en AWS.
- Hoy el EC2 tiene corriendo **sin Docker** un proyecto Java + Spring Boot desplegado directamente sobre el sistema operativo.
- **Objetivo:** partir de cero — limpiar lo que corre hoy y desplegar el stack nuevo 100% dockerizado con `docker-compose`.

## Despliegue

1. Editar `scripts/config.sh`: `EC2_HOST` (IP o DNS público del EC2) y revisar usuario/llave/región.
2. Ejecutar en orden:
   ```bash
   ./scripts/security-group.sh   # abre 22 (a tu IP) y 8080-8084
   ./scripts/deploy.sh           # limpia stack viejo + despliega el nuevo
   ./scripts/verify.sh           # verifica desde afuera, contra la IP pública
   ```
- `deploy.sh` usa `rsync` + `docker compose up -d --build` (build en el propio EC2, sin registry).
- La primera build de la api demora varios minutos (descarga Gradle + dependencias Maven dentro del contenedor).
- En instancias con poca RAM el deploy crea un swap de 2G para que el build de Gradle no muera por OOM.
- A futuro: versión Windows del deploy (`deploy.ps1`).

## Reglas del proyecto

1. **Todo se ejecuta con scripts previamente generados** en `./scripts` (nada de comandos sueltos a mano / "por clic").
2. **Cada paso queda documentado en un checklist** (ver abajo).
3. Los cambios al stack se hacen editando `docker-compose.yml` o los Dockerfiles, no tocando el EC2 a mano.

## Checklist de migración (partir de cero en el EC2)

> Marcar cada paso al completarlo.

- [x] 1. Generar `Dockerfile` por servicio y `docker-compose.yml` (stack: api, 3 consumers, kafka KRaft, kafka-ui).
- [x] 2. Generar scripts en `./scripts` (config, cleanup, deploy, verify, security-group).
- [x] 3. Verificación local del stack: build de las 4 imágenes + health checks OK (api, consumers, kafka-ui).
- [ ] 4. Definir `EC2_HOST` en `scripts/config.sh`.
- [ ] 5. Abrir puertos en el Security Group (`./scripts/security-group.sh`).
- [ ] 6. Detectar y detener el proceso Spring Boot que corre hoy sin Docker en el EC2 (`cleanup.sh` lo detecta por systemd y por puertos 8080-8083, y respalda los jars a `~/backup-pre-docker/`).
- [ ] 7. Desplegar el stack completo (`./scripts/deploy.sh`: rsync + build + health checks).
- [ ] 8. Verificar desde afuera contra la IP pública (`./scripts/verify.sh`).
- [ ] 9. Documentar resultado del despliegue en este README (URLs finales).

## Notas de verificación local (10-nov-2026)

- Stack levantado en Docker local (Rancher Desktop, ARM64): los 6 contenedores Up, health checks OK para los 5 endpoints (4 `/health` + kafka-ui HTTP 200).
- El health de la api dentro de la red Docker: `{"status":"OK"}` (consumers: `{"message":"OK"}`).
- El jar no corre con el `java` del Mac (Java 17 local vs class file 65 de Java 21): **no es problema** — el contenedor lleva su propio JRE 21; de hecho valida por qué conviene dockerizar.
- En el Mac hay un túnel SSH propio ocupando 8080-8084, por lo que los tests locales se hicieron dentro de la red de Docker (`docker run --network proyecto-final_default curlimages/curl ... http://api:8080/health`). Para probar en el navegador localmente, detener antes ese túnel o usar `docker compose up -d` y acceder por los puertos una vez libres.

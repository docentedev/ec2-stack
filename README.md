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
│   ├── security-group.sh     # abre puertos en el SG (SSH a tu IP + 8080-8084)
│   ├── config.ps1            # versión Windows: config común + helper remoto
│   ├── cleanup.ps1           # versión Windows de cleanup.sh
│   ├── deploy.ps1            # versión Windows de deploy.sh (tar+scp en vez de rsync)
│   ├── verify.ps1            # versión Windows de verify.sh
│   └── security-group.ps1    # versión Windows de security-group.sh
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

### macOS / Linux (bash)

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

### Windows (PowerShell)

Equivalentes 1:1 en `.ps1` (probados contra el EC2 real):

```powershell
.\scripts\security-group.ps1    # abre 22 (a tu IP) y 8080-8084 (requiere AWS CLI v2)
.\scripts\deploy.ps1             # limpia stack viejo + despliega el nuevo
.\scripts\verify.ps1              # verifica desde afuera, contra la IP pública
```

- También existe `.\scripts\cleanup.ps1` (equivale a `cleanup.sh`) y `.\scripts\config.ps1` (equivale a `config.sh`).
- `deploy.ps1` acepta `-SkipCleanup` para omitir la limpieza (re-deploy rápido).
- En vez de `rsync` (no existe en Windows) empaqueta el proyecto con `tar` (incluido en Windows 10 1803+) y lo sube con `scp`.
- Requisitos Windows 10/11: **Cliente OpenSSH** (Configuración > Aplicaciones > Características opcionales) y **AWS CLI v2** para `security-group.ps1`. `verify.ps1` usa `curl.exe` (incluido) con fallback nativo a `Invoke-WebRequest`.
- Compatibles con Windows PowerShell 5.1 y pwsh 7+.
- Si ssh rechaza la llave (`UNPROTECTED PRIVATE KEY`), restringir su ACL:
  ```powershell
  icacls .\mi-llave-privada.pem /inheritance:r /grant "${env:USERNAME}:F"
  ```
- Detalle técnico: los scripts PowerShell suben los payloads bash al EC2 como UTF-8 sin BOM con finales de línea LF (evita el clásico error `$'\r': command not found` de pipear texto por ssh desde Windows).

## Reglas del proyecto

1. **Todo se ejecuta con scripts previamente generados** en `./scripts` (nada de comandos sueltos a mano / "por clic").
2. **Cada paso queda documentado en un checklist** (ver abajo).
3. Los cambios al stack se hacen editando `docker-compose.yml` o los Dockerfiles, no tocando el EC2 a mano.

## Checklist de migración (partir de cero en el EC2)

> Marcar cada paso al completarlo.

- [x] 1. Generar `Dockerfile` por servicio y `docker-compose.yml` (stack: api, 3 consumers, kafka KRaft, kafka-ui).
- [x] 2. Generar scripts en `./scripts` (config, cleanup, deploy, verify, security-group) en bash y PowerShell (.ps1).
- [x] 3. Verificación local del stack: build de las 4 imágenes + health checks OK (api, consumers, kafka-ui).
- [x] 4. Definir `EC2_HOST` en `scripts/config.sh`.
- [x] 5. Abrir puertos en el Security Group (`./scripts/security-group.sh`).
- [x] 6. Detectar y detener el proceso Spring Boot que corre hoy sin Docker en el EC2 (`cleanup.sh` lo detecta por systemd y por puertos 8080-8083, y respalda los jars a `~/backup-pre-docker/`).
- [x] 7. Desplegar el stack completo (`./scripts/deploy.sh`: rsync + build + health checks).
- [x] 8. Verificar desde afuera contra la IP pública (`./scripts/verify.sh`).
- [x] 9. Documentar resultado del despliegue en este README (URLs finales).

## Resultado del despliegue (10-nov-2026) ✅

**Instancia:** `i-034c79128b1fa7373` (t3.micro, us-east-2, Amazon Linux 2023, `ec2-user`)
DNS público: `ec2-77-113-69-25.us-east-2.compute.amazonaws.com`

| Servicio              | URL verificada desde afuera                                        | Respuesta |
| --------------------- | ------------------------------------------------------------------ | --------- |
| api                   | http://ec2-77-113-69-25.us-east-2.compute.amazonaws.com:8080/health | `{"status":"OK"}` |
| consumer-analiticas   | http://ec2-77-113-69-25.us-east-2.compute.amazonaws.com:8081/health | `{"message":"OK"}` |
| consumer-notificaciones | http://ec2-77-113-69-25.us-east-2.compute.amazonaws.com:8082/health | `{"message":"OK"}` |
| consumer-pagos        | http://ec2-77-113-69-25.us-east-2.compute.amazonaws.com:8083/health | `{"message":"OK"}` |
| kafka-ui              | http://ec2-77-113-69-25.us-east-2.compute.amazonaws.com:8084        | HTTP 200 (UI) |

Historial de la migración:

1. `cleanup.sh`: detectó y mató el jar viejo (`cursos-0.0.1-SNAPSHOT.jar`, pid en 8080), liberó 8080-8083 y respaldó 3 jars (incl. `/opt/cloud-usuarios-bff/app.jar`) en `~/backup-pre-docker/20261110-124258/`.
2. Docker instalado desde repos de Amazon Linux (`docker 25.0.14`), plugin compose v5.7 y buildx v0.38.2 desde GitHub (Amazon Linux no los trae en la versión requerida).
3. Swap de 2G creado para el build de Gradle en el t3.micro (1GB RAM).
4. Stack levantado con `docker compose up -d --build` y health checks OK (internos y desde afuera).
5. Security Group `sg-0dac330c25b8c2240`: 22 solo a la IP de origen + 8080-8084 públicos; kafka 9092 interno.
6. Versiones Windows (`.ps1`) probadas contra el mismo EC2: `verify.ps1` OK contra los 5 endpoints y `deploy.ps1 -SkipCleanup` completó el ciclo completo (ssh + tar/scp + compose + health checks OK).

## Notas de verificación local (10-nov-2026)

- Stack levantado en Docker local (Rancher Desktop, ARM64): los 6 contenedores Up, health checks OK para los 5 endpoints (4 `/health` + kafka-ui HTTP 200).
- El health de la api dentro de la red Docker: `{"status":"OK"}` (consumers: `{"message":"OK"}`).
- El jar no corre con el `java` del Mac (Java 17 local vs class file 65 de Java 21): **no es problema** — el contenedor lleva su propio JRE 21; de hecho valida por qué conviene dockerizar.
- En el Mac hay un túnel SSH propio ocupando 8080-8084, por lo que los tests locales se hicieron dentro de la red de Docker (`docker run --network proyecto-final_default curlimages/curl ... http://api:8080/health`). Para probar en el navegador localmente, detener antes ese túnel o usar `docker compose up -d` y acceder por los puertos una vez libres.

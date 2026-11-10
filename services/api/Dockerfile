# syntax=docker/dockerfile:1
# =====================================================================
# Imagen mínima funcional de la api (Spring Boot, Java 21).
#
#   build   -> eclipse-temurin:21-jdk-alpine  (~190MB, capa descartada)
#   runtime -> eclipse-temurin:21-jre-alpine  (~95MB, solo JRE)
#
# Las variantes -alpine de Eclipse Temurin son las imágenes oficiales
# más livianas que siguen siendo un JDK/JRE completo, y existen tanto
# para amd64 (t2/t3) como arm64 (t4g), igual que el EC2 donde se buildea.
# Opciones aún más pequeñas (jlink con módulos a medida) ver README.
# =====================================================================

# ---------------------------------------------------- build (JDK completo)
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /app

# Primero los archivos de build para aprovechar la cache de capas de Docker
COPY gradlew settings.gradle build.gradle ./
COPY gradle/ gradle/
RUN chmod +x gradlew

COPY src/ src/

RUN ./gradlew bootJar --no-daemon

# ---------------------------------------------------- runtime (solo JRE)
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

COPY --from=build /app/build/libs/*.jar app.jar

EXPOSE 8080

# MaxRAMPercentage para convivir bien con otros contenedores en un EC2 chico
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]

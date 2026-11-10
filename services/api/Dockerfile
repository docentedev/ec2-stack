# Etapa 1: build con el Gradle wrapper (Java 21 / Gradle 9.8.2)
FROM eclipse-temurin:21-jdk AS build
WORKDIR /app

# Primero los archivos de build para aprovechar la cache de capas de Docker
COPY gradlew settings.gradle build.gradle ./
COPY gradle/ gradle/
RUN chmod +x gradlew

COPY src/ src/

RUN ./gradlew bootJar --no-daemon

# Etapa 2: runtime liviano, solo JRE
FROM eclipse-temurin:21-jre
WORKDIR /app

COPY --from=build /app/build/libs/*.jar app.jar

EXPOSE 8080

# MaxRAMPercentage para convivir bien con otros contenedores en un EC2 chico
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]

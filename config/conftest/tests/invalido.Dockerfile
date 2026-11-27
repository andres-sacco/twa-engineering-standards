# Rompe cada política de config/conftest/dockerfile.rego: make lint verifica que Conftest las encuentre todas
FROM maven:3.9-eclipse-temurin-25 AS build
ARG GITHUB_TOKEN
COPY settings.xml /root/.m2/settings.xml
RUN mvn -B package

FROM eclipse-temurin:25-jdk
ENV DB_PASSWORD=changeme
COPY --from=build /target/app.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]

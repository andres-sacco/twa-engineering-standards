# USER root explícito y HEALTHCHECK NONE
FROM eclipse-temurin:25-jre
COPY app.jar app.jar
USER root
HEALTHCHECK NONE
ENTRYPOINT ["java", "-jar", "app.jar"]

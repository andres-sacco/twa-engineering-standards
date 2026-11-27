# syntax=docker/dockerfile:1

# Misma forma que el Dockerfile de los servicios TWA. El settings.xml de GitHub Packages es opcional (required=false):
# la imagen no corre los tests ni el perfil architecture-rules, así que no baja twa-layered-rules
FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /workspace
COPY . .
RUN --mount=type=cache,target=/root/.m2/repository \
    --mount=type=secret,id=maven-settings,target=/root/.m2/settings.xml,required=false \
    mvn -B -ntp package -Dmaven.test.skip=true -DskipArchitectureRules -Dspotless.check.skip=true \
 && cp target/sample-service-*.jar application.jar \
 && java -Djarmode=tools -jar application.jar extract --layers --destination extracted

FROM eclipse-temurin:25-jre

RUN groupadd --system --gid 1001 app && useradd --system --uid 1001 --gid app --no-create-home app

WORKDIR /application
COPY --from=build /workspace/extracted/dependencies/ ./
COPY --from=build /workspace/extracted/spring-boot-loader/ ./
COPY --from=build /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build /workspace/extracted/application/ ./

USER app

ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080 && printf 'GET /api/flights/sample/health/liveness HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n' >&3 && grep -q '\"UP\"' <&3"]

ENTRYPOINT ["java", "-jar", "application.jar"]

FROM eclipse-temurin:25-alpine
WORKDIR /workspace
COPY pom.xml .
COPY src ./src
RUN mvn -B -DskipTests package

FROM eclipse-temurin:25-alpine
WORKDIR /app
COPY --from=build --chown=10001:10001 /workspace/target/kong-chatbot-*.jar /app/app.jar
USER 10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]

SHELL := /bin/sh

MVN ?= mvn
MVN_ARGS ?=
DOCKER ?= docker
COMPOSE ?= $(DOCKER) compose
ENV_FILE ?= .env
COMPOSE_ARGS ?=

COMPOSE_ENV = $(COMPOSE) --env-file $(ENV_FILE) $(COMPOSE_ARGS)

.PHONY: help env setup-example-env build package test verify clean up down restart logs ps config host-run java-version deps-java-update deps-plugins-update

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make env       Create .env from .env.example (does not overwrite)' \
		'  make setup-example-env  Set up a sample .env for local development' \
		'  make build     Build the chatbot Docker image' \
		'  make package  Package the application with Maven' \
		'  make test     Run the Maven tests' \
		'  make verify   Run the Maven verification lifecycle' \
		'  make clean    Clean Maven build output' \
		'  make up       Build and start the full Compose stack' \
		'  make down     Stop the Compose stack (preserve named volumes)' \
		'  make restart  Rebuild and restart the Compose stack' \
		'  make logs     Follow logs for all Compose services' \
		'  make ps       Show Compose service status' \
		'  make config   Validate and print resolved Compose configuration' \
		'  make host-run Run Spring Boot on the host (Kong must be reachable)' \
		'  make java-version  Print the Java version configured in pom.xml' \
		'  JAVA_VERSION=21 make deps-java-update  Set the Maven Java version property' \
		'  make deps-plugins-update  Update Kotlin dependency version properties' \
		'' \
		'Common overrides: ENV_FILE=.env.dev, MVN=mvn, MVN_ARGS="-DskipTests"'

env:
	@if [ -f .env ]; then \
		printf '.env already exists; leaving it unchanged.\n'; \
	else \
		cp .env.example .env && printf 'Created .env from .env.example. Update the Konnect and Redis values before starting Compose.\n'; \
	fi

setup-example-env: env

build:
	$(COMPOSE_ENV) build

package:
	$(MVN) $(MVN_ARGS) package

test:
	$(MVN) $(MVN_ARGS) test

verify:
	$(MVN) $(MVN_ARGS) --batch-mode --no-transfer-progress verify

clean:
	$(MVN) $(MVN_ARGS) clean

up:
	$(COMPOSE_ENV) up --build

down:
	$(COMPOSE_ENV) down

restart:
	$(COMPOSE_ENV) up --build --force-recreate

logs:
	$(COMPOSE_ENV) logs --follow

ps:
	$(COMPOSE_ENV) ps

config:
	$(COMPOSE_ENV) config

host-run:
	$(MVN) $(MVN_ARGS) spring-boot:run

deps-plugins-update:
	curl -sL https://raw.githubusercontent.com/jesperancinha/project-signer/master/pluginUpdatesOne.sh | bash -s -- $(PARAMS)
deps-java-update:
	curl -sL https://raw.githubusercontent.com/jesperancinha/project-signer/master/javaUpdatesOne.sh | bash
deps-node-update:
	curl -sL https://raw.githubusercontent.com/jesperancinha/project-signer/master/nodeUpdatesOne.sh | bash
deps-quick-update:  deps-plugins-update deps-java-update deps-node-update
update-repo-prs:
	curl -sL https://raw.githubusercontent.com/jesperancinha/project-signer/master/update-all-repo-prs.sh | bash
accept-prs:
	curl -sL https://raw.githubusercontent.com/jesperancinha/project-signer/master/acceptPR.sh | bash

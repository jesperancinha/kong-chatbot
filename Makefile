SHELL := /bin/sh

MVN ?= mvn
MVN_ARGS ?=
DOCKER ?= docker
COMPOSE ?= $(DOCKER) compose
ENV_FILE ?= $(if $(filter konnect,$(MODE)),.env.konnect,.env)
COMPOSE_ARGS ?=
TERRAFORM ?= terraform
MODE ?= local
TF = TERRAFORM="$(TERRAFORM)" sh scripts/terraform.sh

COMPOSE_FILE = $(if $(filter konnect,$(MODE)),compose.yaml,compose.local.yaml)
COMPOSE_ENV = $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) $(COMPOSE_ARGS)

.PHONY: help env setup-example-env build package test verify clean up down restart logs ps config host-run java-version deps-java-update deps-plugins-update terraform-init terraform-plan terraform-up terraform-down switch smoke konnect-bootstrap konnect-ingest

help:
	@printf '%s\n' \
		'Available targets:' \
		'  MODE=local|konnect (default: local); applies to Compose and Terraform' \
		'  make switch    Stop the other Compose mode, then start MODE' \
		'  make smoke     Ask a question grounded in the sample knowledge' \
		'  make konnect-bootstrap  Configure a dedicated Konnect control plane and TLS' \
		'  make konnect-ingest     Index knowledge documents via Kong RAG Injector' \
		'  make env       Create .env from .env.example (does not overwrite)' \
		'  make setup-example-env  Set up a sample .env for local development' \
		'  make build     Build the chatbot Docker image' \
		'  make package  Package the application with Maven' \
		'  make test     Run the Maven tests' \
		'  make verify   Run the Maven verification lifecycle' \
		'  make clean    Clean Maven build output' \
		'  make up       Build, download local models, index documents, wait for readiness' \
		'  make down     Stop the Compose stack (preserve named volumes)' \
		'  make restart  Rebuild and restart the Compose stack' \
		'  make logs     Follow logs for all Compose services' \
		'  make ps       Show Compose service status' \
		'  make config   Validate and print resolved Compose configuration' \
		'  make host-run Run Spring Boot on the host (Kong must be reachable)' \
		'  make terraform-init  Initialize the Terraform Docker deployment' \
		'  make terraform-plan  Preview Terraform container changes' \
		'  make terraform-up    Start Kong, Redis Stack, and the chatbot with Terraform' \
		'  make terraform-down  Stop and remove Terraform-managed containers and network' \
		'  make java-version  Print the Java version configured in pom.xml' \
		'  JAVA_VERSION=21 make deps-java-update  Set the Maven Java version property' \
		'  make deps-plugins-update  Update Kotlin dependency version properties' \
		'' \
		'Common overrides: ENV_FILE=.env.dev, MVN=mvn, MVN_ARGS="-DskipTests"'

env:
	@if [ -f "$(ENV_FILE)" ]; then \
		printf '%s already exists; leaving it unchanged.\n' "$(ENV_FILE)"; \
	else \
		(umask 077; cp .env.example "$(ENV_FILE)") && printf 'Created %s from .env.example.\n' "$(ENV_FILE)"; \
	fi

setup-example-env: env

build: env
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
	ENV_FILE=$(ENV_FILE) sh scripts/stack.sh $(MODE) up

down:
	ENV_FILE=$(ENV_FILE) sh scripts/stack.sh $(MODE) down

restart: down up

switch:
	ENV_FILE=$(ENV_FILE) sh scripts/stack.sh $(MODE) check
	ENV_FILE=$(ENV_FILE) sh scripts/stack.sh $(if $(filter konnect,$(MODE)),local,konnect) down
	ENV_FILE=$(ENV_FILE) sh scripts/stack.sh $(MODE) up

smoke:
	sh scripts/smoke.sh

konnect-bootstrap:
	sh scripts/konnect.sh bootstrap

konnect-ingest:
	sh scripts/konnect.sh ingest

logs:
	$(COMPOSE_ENV) logs --follow

ps:
	$(COMPOSE_ENV) ps

config:
	$(COMPOSE_ENV) config

host-run:
	$(MVN) $(MVN_ARGS) spring-boot:run

terraform-init:
	$(TF) init

terraform-plan: terraform-init
	$(TF) plan $(if $(filter konnect,$(MODE)),-var-file=konnect.tfvars,) -var='mode=$(MODE)'

terraform-up: terraform-init
	$(TF) apply $(if $(filter konnect,$(MODE)),-var-file=konnect.tfvars,) -var='mode=$(MODE)'
	sh scripts/wait-api.sh "$$($(TF) output -raw chatbot_url)"

terraform-down: terraform-init
	$(TF) destroy $(if $(filter konnect,$(MODE)),-var-file=konnect.tfvars,) -var='mode=$(MODE)'

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

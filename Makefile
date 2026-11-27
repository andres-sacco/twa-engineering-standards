.DEFAULT_GOAL := help
SAMPLE := examples/sample-service

.PHONY: help lint sample sample-image

help: ## Lista los comandos
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

lint: ## Workflows (actionlint, zizmor), schema, catálogo de controles y scripts
	@./scripts/lint.sh

sample: ## Compila y testea el servicio de prueba (mvn verify, necesita Java 25)
	@cd $(SAMPLE) && mvn -B -ntp verify

sample-image: ## Construye la imagen del servicio de prueba
	@docker build --tag sample-service:local $(SAMPLE)

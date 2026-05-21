CLUSTER_NAME  := casdoor-lab
NAMESPACE     := casdoor
CASDOOR_PORT  := 8000
LOCAL_PORT    := 8000
APP_IMAGE     := casdoor-flask-demo:latest

export PATH := $(HOME)/.local/bin:$(PATH)

.DEFAULT_GOAL := help

# ─── Cluster ────────────────────────────────────────────────────────────────

.PHONY: cluster
cluster: ## Cria o cluster Kind
	kind create cluster --name $(CLUSTER_NAME)

.PHONY: cluster-delete
cluster-delete: ## Destroi o cluster Kind
	kind delete cluster --name $(CLUSTER_NAME)

# ─── Deploy ─────────────────────────────────────────────────────────────────

.PHONY: deploy
deploy: ## Aplica todos os manifests (namespace → mysql → config → casdoor → app)
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/mysql.yaml
	@echo "⏳ Aguardando MySQL ficar pronto..."
	kubectl rollout status deployment/mysql -n $(NAMESPACE) --timeout=120s
	kubectl apply -f k8s/casdoor-config.yaml
	kubectl apply -f k8s/casdoor.yaml
	@echo "⏳ Aguardando Casdoor ficar pronto..."
	kubectl rollout status deployment/casdoor -n $(NAMESPACE) --timeout=120s
	kubectl apply -f k8s/app.yaml
	@echo "✅ Stack completa — rode: make forward-all"

.PHONY: undeploy
undeploy: ## Remove todos os recursos (mantém o cluster)
	kubectl delete namespace $(NAMESPACE) --ignore-not-found

# ─── Atalhos ─────────────────────────────────────────────────────────────────

.PHONY: all
all: cluster app-build app-load deploy ## Cria o cluster, build da app e deploy completo

.PHONY: reset
reset: undeploy deploy ## Remove e faz o deploy novamente (mantém o cluster)

.PHONY: destroy
destroy: undeploy cluster-delete ## Remove tudo: recursos + cluster

# ─── Flask Demo App ──────────────────────────────────────────────────────────

.PHONY: app-build
app-build: ## Build da imagem Docker da Flask demo app
	docker build -t $(APP_IMAGE) ./app

.PHONY: app-load
app-load: ## Carrega a imagem no cluster Kind (sem precisar de registry)
	kind load docker-image $(APP_IMAGE) --name $(CLUSTER_NAME)

.PHONY: app-deploy
app-deploy: ## Aplica o manifest da Flask demo app
	kubectl apply -f k8s/app.yaml

.PHONY: app-restart
app-restart: ## Reinicia o pod da Flask demo (após rebuild)
	kubectl rollout restart deployment/flask-demo -n $(NAMESPACE)

.PHONY: logs-app
logs-app: ## Exibe logs da Flask demo app (segue em tempo real)
	kubectl logs -f -l app=flask-demo -n $(NAMESPACE)

# ─── Observabilidade ─────────────────────────────────────────────────────────

.PHONY: status
status: ## Mostra pods, services e events do namespace
	kubectl get pods,svc -n $(NAMESPACE) -o wide
	@echo ""
	kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | tail -20

.PHONY: logs
logs: ## Exibe logs do Casdoor (segue em tempo real)
	kubectl logs -f -l app=casdoor -n $(NAMESPACE)

.PHONY: logs-mysql
logs-mysql: ## Exibe logs do MySQL (segue em tempo real)
	kubectl logs -f -l app=mysql -n $(NAMESPACE)

# ─── Acesso ──────────────────────────────────────────────────────────────────

.PHONY: forward
forward: ## Port-forward do Casdoor → http://localhost:8000
	@echo "Acesse: http://localhost:8000  (admin / 123)"
	kubectl port-forward svc/casdoor-svc 8000:8000 -n $(NAMESPACE)

.PHONY: forward-app
forward-app: ## Port-forward da Flask demo → http://localhost:5000
	@echo "Acesse: http://localhost:5000"
	kubectl port-forward svc/flask-demo-svc 5000:5000 -n $(NAMESPACE)

.PHONY: forward-all
forward-all: ## Port-forward de tudo em paralelo (Casdoor :8000 e Flask :5000)
	@echo "Casdoor → http://localhost:8000"
	@echo "Flask   → http://localhost:5000"
	kubectl port-forward svc/casdoor-svc 8000:8000 -n $(NAMESPACE) & \
	kubectl port-forward svc/flask-demo-svc 5000:5000 -n $(NAMESPACE)

# ─── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Lista todos os targets disponíveis
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

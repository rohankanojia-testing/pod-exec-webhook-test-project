# -------- Config --------
IMAGE ?= exec-webhook
REGISTRY ?= quay.io/rokumar
TAG ?= latest
NAMESPACE ?= webhook
SECRET_NAME ?= exec-webhook-tls
SERVICE_NAME ?= exec-webhook
OPENSSL_CONFIG := config/openssl.cnf
TLS_DIR := tls
DOCKERFILE ?= Containerfile

.PHONY: all certs secret docker push deploy run clean

certs:
	@echo "🔐 Generating TLS and CA certs using $(OPENSSL_CONFIG)..."
	mkdir -p $(TLS_DIR)

	@# Generate CA key and certificate
	openssl genrsa -out $(TLS_DIR)/ca.key 2048
	openssl req -x509 -new -nodes -key $(TLS_DIR)/ca.key \
		-subj "/CN=WebhookCA" -days 3650 -out $(TLS_DIR)/ca.crt

	@# Generate server key and CSR
	openssl genrsa -out $(TLS_DIR)/tls.key 2048
	openssl req -new -key $(TLS_DIR)/tls.key \
		-out $(TLS_DIR)/tls.csr \
		-subj "/CN=${SERVICE_NAME}.${NAMESPACE}.svc" \
		-config $(OPENSSL_CONFIG)

	@# Sign server certificate with CA
	openssl x509 -req -in $(TLS_DIR)/tls.csr \
		-CA $(TLS_DIR)/ca.crt -CAkey $(TLS_DIR)/ca.key -CAcreateserial \
		-out $(TLS_DIR)/tls.crt -days 3650 \
		-extensions v3_req -extfile $(OPENSSL_CONFIG)

	@echo "✅ TLS cert and CA generated in $(TLS_DIR)/"

# -------- Create Kubernetes Secret --------
secret:
	kubectl create ns $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl delete secret $(SECRET_NAME) -n $(NAMESPACE) --ignore-not-found
	kubectl create secret tls $(SECRET_NAME) \
	  --cert=$(TLS_DIR)/tls.crt --key=$(TLS_DIR)/tls.key \
	  -n $(NAMESPACE)

# -------- Build Docker Image --------
oci-build:
	podman build -f $(DOCKERFILE) -t $(REGISTRY)/$(IMAGE):$(TAG) .

oci-push:
	podman push $(REGISTRY)/$(IMAGE):$(TAG)

# -------- Deploy (apply YAMLs yourself) --------
#deploy: secret oci-build oci-push
deploy:
	CA_BUNDLE := $(shell kubectl get secret exec-webhook-tls -n webhook -o jsonpath='{.data.tls\.crt}')
	echo "CA_BUNDLE: $(CA_BUNDLE)"
	echo "Applying webhook configuration with embedded CA_BUNDLE..."; \
	@kubectl apply -f kubernetes.yaml
	@kubectl patch validatingwebhookconfiguration pods-exec-deny \
      --type='json' \
      -p '[{"op": "add", "path": "/webhooks/0/clientConfig/caBundle", "value": "$(CA_BUNDLE)"}]'

	@echo "All done. Now deploy the webhook deployment, service, and webhook config manually."

# -------- Run Locally (for testing without TLS) --------
run:
	go run main.go --cert-dir=$(TLS_DIR)

# -------- Clean Up --------
clean:
	rm -rf $(TLS_DIR)

.PHONY: undeploy

undeploy:
	@echo "Deleting ValidatingWebhookConfiguration..."
	kubectl delete validatingwebhookconfiguration pods-exec-deny --ignore-not-found
	@echo "Deleting webhook deployment and service..."
	kubectl delete deployment exec-webhook -n $(NAMESPACE) --ignore-not-found
	kubectl delete service exec-webhook -n $(NAMESPACE) --ignore-not-found
	@echo "Deleting TLS secret..."
	kubectl delete secret $(SECRET_NAME) -n $(NAMESPACE) --ignore-not-found
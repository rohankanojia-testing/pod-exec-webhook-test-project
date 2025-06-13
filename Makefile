IMAGE ?= exec-webhook
REGISTRY ?= quay.io/rokumar
TAG ?= latest
DEPLOY_NAMESPACE = webhook
SECRET_NAME ?= exec-webhook-tls
SERVICE_NAME ?= exec-webhook
OPENSSL_CONFIG := config/openssl.cnf
TLS_DIR := tls
DOCKERFILE ?= Containerfile
EXEC_WEBHOOK_INDEX ?= 0
CREATE_WEBHOOK_INDEX ?= 1
WEBHOOK_NAME ?= pods-exec-deny
POD_NAME=exec-webhook-test-pod

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
		-subj "/CN=${SERVICE_NAME}.${DEPLOY_NAMESPACE}.svc" \
		-config $(OPENSSL_CONFIG)

	@# Sign server certificate with CA
	openssl x509 -req -in $(TLS_DIR)/tls.csr \
		-CA $(TLS_DIR)/ca.crt -CAkey $(TLS_DIR)/ca.key -CAcreateserial \
		-out $(TLS_DIR)/tls.crt -days 3650 \
		-extensions v3_req -extfile $(OPENSSL_CONFIG)

	@echo "✅ TLS cert and CA generated in $(TLS_DIR)/"

secret:
	kubectl create ns $(DEPLOY_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl delete secret $(SECRET_NAME) -n $(DEPLOY_NAMESPACE) --ignore-not-found
	kubectl create secret tls $(SECRET_NAME) \
	  --cert=$(TLS_DIR)/tls.crt --key=$(TLS_DIR)/tls.key \
	  -n $(DEPLOY_NAMESPACE)

oci-build:
	podman build -f $(DOCKERFILE) -t $(REGISTRY)/$(IMAGE):$(TAG) .

oci-push:
	podman push $(REGISTRY)/$(IMAGE):$(TAG)

deploy: secret oci-build oci-push
	@CA_BUNDLE=$$(kubectl get secret exec-webhook-tls -n $(DEPLOY_NAMESPACE) -o jsonpath="{.data.tls\\.crt}"); \
	sed "s|{{CA_BUNDLE}}|$$CA_BUNDLE|g" deploy/kubernetes.yaml | kubectl apply -f - 
	@echo "✅ All done. Now deploy the webhook deployment, service, and webhook config manually."

run:
	go run main.go --cert-dir=$(TLS_DIR)

clean:
	rm -rf $(TLS_DIR)

.PHONY: undeploy
undeploy:
	@echo "Deleting ValidatingWebhookConfiguration..."
	kubectl delete validatingwebhookconfiguration pods-exec-deny --ignore-not-found
	@echo "Deleting webhook deployment and service..."
	kubectl delete deployment exec-webhook -n $(DEPLOY_NAMESPACE) --ignore-not-found
	kubectl delete service exec-webhook -n $(DEPLOY_NAMESPACE) --ignore-not-found
	@echo "Deleting TLS secret..."
	kubectl delete secret $(SECRET_NAME) -n $(DEPLOY_NAMESPACE) --ignore-not-found
	kubectl delete pods -l app=exec-webhook

.PHONY: test-pod-exec
test-pod-exec:
	@echo "Creating a test pod..."
	kubectl run $(POD_NAME)-created-test-pod-exec --image=busybox --labels="app=exec-webhook" --restart=Never -- sleep 3600
	

.PHONY: test-pod-exec-object-selector
test-pod-exec-object-selector:
	@echo "Updating ValidatingWebhookConfiguration to have objectSelector"
	@echo "Patching ValidatingWebhookConfiguration '$(WEBHOOK_NAME)' to have objectSelector for label controller.devfile.io/creator=yesd"
	kubectl patch validatingwebhookconfiguration $(WEBHOOK_NAME) --type=json \
    		-p='[{"op": "add", "path": "/webhooks/$(EXEC_WEBHOOK_INDEX)/objectSelector", "value": {"matchLabels": {"controller.devfile.io/creator": "yesd"}}}]'
	kubectl patch validatingwebhookconfiguration $(WEBHOOK_NAME) --type=json \
        		-p='[{"op": "add", "path": "/webhooks/$(CREATE_WEBHOOK_INDEX)/objectSelector", "value": {"matchLabels": {"controller.devfile.io/creator": "yesd"}}}]'
	kubectl run $(POD_NAME)-created-objectselector --image=busybox --labels="app=exec-webhook" --restart=Never -- sleep 3600
	@echo "✅ Creating a new Pod without label worked"
	kubectl wait --for=condition=Ready pod/$(POD_NAME)-created-objectselector --timeout=30s
	kubectl exec $(POD_NAME) -- echo "Hello from inside the pod! (No label)"
	@echo "✅ Exec into the Pod without label worked"
	
	@if kubectl run $(POD_NAME)-with-label --image=busybox --labels="app=exec-webhook,controller.devfile.io/creator=yesd" --restart=Never -- sleep 3600; then \
		echo "Exec into Pod with label worked [This is not expected]">&2; \
		exit 1; \
	else \
		echo "✅ SUCCESS: Pod creation with label got rejected"; \
	fi
	
.PHONY: test-pod-create
test-pod-create:
	@echo "Creating Simple Pod without Labels"
	kubectl run $(POD_NAME) --image=busybox --labels="app=exec-webhook" --restart=Never -- sleep 3600
	@echo "Creating Simple Pod with label"
	kubectl run $(POD_NAME) --image=busybox --labels="app=exec-webhook,controller.devfile.io/creator=yesd" --restart=Never -- sleep 3600	
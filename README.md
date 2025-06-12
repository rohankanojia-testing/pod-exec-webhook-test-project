## Simple Pod Exec WebHook
This is a simple Pod Exec Webhook that only allows to exec into specific namespaces.

## How to Deploy
You need to have access to some Kubernetes cluster.

First you need to generate Self Signed Certificates required for webhook:
```shell
make certs
```
Then you can deploy the webhook using this command:
```shell
make deploy
```
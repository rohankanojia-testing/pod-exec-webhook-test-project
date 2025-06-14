## Simple Pod Exec WebHook
This is a simple Webhook project that restricts pod operations in certain namespaces:
- Allow exec into specific namespaces `kube-system`/`dev`
- Allow creating Pod with a specific label in `kube-system`/`dev`

## Prerequisites
- Kubernetes cluster (Kind/Minikube)
- Quay/DockerHub account to push container image

## How to Deploy
You need to have access to some Kubernetes cluster.

First you need to generate Self Signed Certificates required for webhook:
```shell
make certs
```
Before deploying, you would need to adjust `REGISTRY` variable in Makefile to push it to your container registry namespace:
```shell
REGISTRY ?= quay.io/rokumar
```

Then you can deploy the webhook using this command:
```shell
make deploy
```

The webhook should be deployed in `webhoook` namespace:
```shell
pod-exec-webhook-test-project : $ kubectl get pods -nwebhook
NAME                            READY   STATUS    RESTARTS   AGE
exec-webhook-597b9b4759-mp8h8   1/1     Running   0          14m
```

Now if you try to exec into a Pod other than `kube-system` or `dev` namespace, you'll get this error:
```shell
Error from server (Forbidden): admission webhook "podexec.webhook.k8s.io" denied the request: exec into pods denied for user minikube-user in namespace default
```

But if you're going to exec in one of the Pods in `kube-system` or `dev`, you would be able to do it:
```shell
kubectl exec -it pod/etcd-minikube -n kube-system -- /bin/sh
sh-5.2#
```

## Reproducing the original issue

Original motivation of creating this repository is to showcase that `objectSelector` is not working for pods/exec webhook.

Let's modify ValidatingWebhookConfiguration to match only Pods with selected labels:
```shell
  objectSelector:
    matchLabels:
      controller.devfile.io/creator: foocreator
```
You can also run this command that would automatically update ValidatingWebhookConfiguration and test it:
```shell
make test-pod-exec-object-selector
```
Now expectation should be that webhook should only check Pods with labels `controller.devfile.io/creator`.

However, after applying this change webhook isn't fired at all. 
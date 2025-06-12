package main

import (
	"flag"
	"fmt"
	"k8s.io/apimachinery/pkg/runtime"
	"os"
	"pods-exec-webhook/api"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/webhook"
)

func main() {
	opts := zap.Options{}
	var certDir string
	flag.StringVar(&certDir, "cert-dir", "/tls", "directory where TLS certs are stored")
	flag.Parse()
	log.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	webhookServer := webhook.NewServer(webhook.Options{
		CertDir: certDir,
		Port:    9443,
	})
	fmt.Println("setting logging")
	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:        runtime.NewScheme(),
		WebhookServer: webhookServer,
	})
	fmt.Println("initializing manager")
	if err != nil {
		os.Exit(1)
	}

	hookServer := mgr.GetWebhookServer()
	fmt.Println("registering webhooks to the webhook server")
	hookServer.Register("/validate-v1-pod-exec", &webhook.Admission{Handler: api.NewExecValidator(mgr)})

	fmt.Println("starting webhook server")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		fmt.Println("manager exited with error", err)
		os.Exit(1)
	}
}

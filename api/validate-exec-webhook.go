package api

import (
	"context"
	"fmt"
	admissionv1 "k8s.io/api/admission/v1"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

type ExecValidator struct {
	Decoder admission.Decoder
}

func NewExecValidator(mgr manager.Manager) *ExecValidator {
	return &ExecValidator{
		Decoder: admission.NewDecoder(mgr.GetScheme()),
	}
}

var allowedNamespaces = map[string]bool{
	"kube-system": true,
	"dev":         true,
}

func (v *ExecValidator) Handle(ctx context.Context, req admission.Request) admission.Response {
	fmt.Println("handling admission request")
	if req.Resource.Resource == "pods" && req.SubResource == "exec" && req.Operation == admissionv1.Connect {
		fmt.Println("Is pod/exec request")
		ns := req.Namespace
		user := req.UserInfo.Username
		groups := req.UserInfo.Groups

		fmt.Println("namespace is", ns)
		fmt.Printf("user: %s, groups: %v\n", user, groups)
		// Allow if in allowed namespace
		if allowedNamespaces[ns] {
			fmt.Println("is in allowed namespace request, allowing by default")
			return admission.Allowed(fmt.Sprintf("namespace %s is allowed", ns))
		}

		fmt.Println("denied exec access", "user", user, "namespace", ns)
		return admission.Denied(fmt.Sprintf("exec into pods denied for user %s in namespace %s", user, ns))
	}

	fmt.Println("not an exec subresource request, allowing by default")
	return admission.Allowed("not an exec subresource request")
}

package api

import (
	"context"
	"fmt"
	admissionv1 "k8s.io/api/admission/v1"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

type CreationValidator struct {
	Decoder admission.Decoder
}

func NewCreationValidator(mgr manager.Manager) *CreationValidator {
	return &CreationValidator{
		Decoder: admission.NewDecoder(mgr.GetScheme()),
	}
}

func (v *CreationValidator) Handle(ctx context.Context, req admission.Request) admission.Response {
	fmt.Println("handling admission request")
	if req.Resource.Resource == "pods" && req.Operation == admissionv1.Create {
		fmt.Println("Is pod creation request")
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

		fmt.Println("denied creation access", "user", user, "namespace", ns)
		return admission.Denied(fmt.Sprintf("create pods denied for user %s in namespace %s", user, ns))
	}

	fmt.Println("not pod create request, allowing by default")
	return admission.Allowed("not a pod create request")
}

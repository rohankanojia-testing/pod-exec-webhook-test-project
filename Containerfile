FROM golang:1.24 as builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o webhook main.go

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/webhook /webhook
USER nonroot:nonroot
ENTRYPOINT ["/webhook"]


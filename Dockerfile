ARG DATA_RACE=false

# Extract the wasm-shim binary (platform-independent) from the OCI image
ARG WASM_SHIM_IMAGE=quay.io/kuadrant/wasm-shim:latest
FROM ${WASM_SHIM_IMAGE} AS wasm-shim

# Build the manager binary
FROM --platform=$TARGETPLATFORM golang:1.26 AS builder

WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum
# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# Copy the go source
COPY cmd/ cmd/
COPY api/ api/
COPY internal/ internal/
COPY pkg/ pkg/

# Set environment variables for cross-compilation
ARG TARGETARCH

# Build

ARG GIT_SHA
ARG DIRTY
ARG VERSION
ARG DATA_RACE
ARG WITH_EXTENSIONS=true
ARG EXTRA_EXTENSIONS=""

ENV GIT_SHA=${GIT_SHA:-unknown}
ENV DIRTY=${DIRTY:-unknown}
ENV VERSION=${VERSION:-unknown}

# Kuadrant Operator
RUN if [ "${DATA_RACE}" = "true" ]; then \
    CGO_ENABLED=1 GOOS=linux GOARCH=${TARGETARCH} go build -race -a -ldflags "-X main.version=${VERSION} -X main.gitSHA=${GIT_SHA} -X main.dirty=${DIRTY}" -o manager cmd/main.go; \
    else \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -a -ldflags "-X main.version=${VERSION} -X main.gitSHA=${GIT_SHA} -X main.dirty=${DIRTY}" -o manager cmd/main.go; \
    fi

# Conditionally build extensions
RUN mkdir -p extensions
RUN if [ "$WITH_EXTENSIONS" = "true" ]; then \
    echo "Building extensions..." && \
    if [ "${DATA_RACE}" = "true" ]; then \
      CGO_FLAG=1; RACE_FLAG="-race"; \
    else \
      CGO_FLAG=0; RACE_FLAG=""; \
    fi && \
    mkdir -p extensions/oidc-policy && \
    CGO_ENABLED=$CGO_FLAG GOOS=linux GOARCH=${TARGETARCH} go build $RACE_FLAG -a -o extensions/oidc-policy/oidc-policy cmd/extensions/oidc-policy/main.go && \
    mkdir -p extensions/plan-policy && \
    CGO_ENABLED=$CGO_FLAG GOOS=linux GOARCH=${TARGETARCH} go build $RACE_FLAG -a -o extensions/plan-policy/plan-policy cmd/extensions/plan-policy/main.go && \
    mkdir -p extensions/telemetry-policy && \
    CGO_ENABLED=$CGO_FLAG GOOS=linux GOARCH=${TARGETARCH} go build $RACE_FLAG -a -o extensions/telemetry-policy/telemetry-policy cmd/extensions/telemetry-policy/main.go; \
    else \
    echo "Skipping extensions build"; \
    fi

# Build additional extensions specified via EXTRA_EXTENSIONS (space-separated list of directory names under cmd/extensions/)
RUN set -e; \
    if [ "${DATA_RACE}" = "true" ]; then \
      CGO_FLAG=1; RACE_FLAG="-race"; \
    else \
      CGO_FLAG=0; RACE_FLAG=""; \
    fi; \
    for ext in $EXTRA_EXTENSIONS; do \
      echo "Building extra extension: $ext"; \
      mkdir -p "extensions/$ext"; \
      CGO_ENABLED=$CGO_FLAG GOOS=linux GOARCH=${TARGETARCH} \
        go build $RACE_FLAG -a -o "extensions/$ext/$ext" "cmd/extensions/$ext/main.go"; \
    done

# Use distroless as minimal base image to package the manager binary
# Refer to https://github.com/GoogleContainerTools/distroless for more details
# CGO_ENABLED=1 (race) produces a dynamically linked binary requiring glibc (distroless/base)
FROM gcr.io/distroless/base:nonroot AS runtime-true
FROM gcr.io/distroless/static:nonroot AS runtime-false
FROM runtime-${DATA_RACE}
WORKDIR /
COPY --from=builder /workspace/manager .
COPY --from=builder /workspace/extensions /extensions
COPY --from=wasm-shim /plugin.wasm /wasm/plugin.wasm

# Quay image expiry
ARG QUAY_IMAGE_EXPIRY
ENV QUAY_IMAGE_EXPIRY=${QUAY_IMAGE_EXPIRY:-never}
LABEL quay.expires-after=$QUAY_IMAGE_EXPIRY

ENTRYPOINT ["/manager"]

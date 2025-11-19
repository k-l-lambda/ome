# Build the manager binary
FROM golang:1.24 AS builder

# Install Rust and Cargo for building the XET library
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Build arguments for cross-compilation
ARG TARGETOS
ARG TARGETARCH

# Set working directory
WORKDIR /workspace

# Copy go mod files
COPY go.mod go.mod
COPY go.sum go.sum

# Download dependencies with Go module cache
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Copy source code
COPY cmd/ cmd/
COPY pkg/ pkg/

# Build the XET library first
RUN cd pkg/xet && make build

# Build arguments for version info
ARG VERSION
ARG GIT_TAG
ARG GIT_COMMIT

# Build the manager binary with Go build cache (CGO must be enabled for XET library)
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=1 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} \
    go build -a \
    -ldflags "-X github.com/sgl-project/ome/pkg/version.GitVersion=${GIT_TAG} -X github.com/sgl-project/ome/pkg/version.GitCommit=${GIT_COMMIT}" \
    -o manager ./cmd/manager

# Use debian12:bookworm-slim as runtime for exact glibc match with golang:1.24
# This ensures both glibc 2.38 and OpenSSL 3.x are available
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && adduser --uid 65532 --disabled-password --gecos "" --shell /bin/false nonroot
WORKDIR /
COPY --from=builder /workspace/manager .
USER 65532:65532

ENTRYPOINT ["/manager"]

# Agent Orrery — Multi-stage OCI container build
# Bead: agent-orrery-eb0.7.3
#
# Usage:
#   docker build -t agent-orrery:latest -f packaging/Dockerfile .
#   docker run -p 7890:7890 agent-orrery:latest
#
# Build args:
#   TARGET — build target (cli|tui|web|mcclim), default web

ARG SBCL_VERSION=2.5.8
ARG TARGET=web

# ─── Stage 1: Builder ───
FROM docker.io/fukamachi/sbcl:${SBCL_VERSION} AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev libcurl4-openssl-dev gcc make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

# Install Quicklisp
RUN curl -fsSL https://beta.quicklisp.org/quicklisp.lisp -o /tmp/ql.lisp \
    && sbcl --noinform --non-interactive \
      --load /tmp/ql.lisp \
      --eval '(quicklisp-quickstart:install :path "/root/quicklisp/")' \
      --eval '(ql-dist:install-dist "http://beta.quicklisp.org/dist/quicklisp.txt" :prompt nil)' \
    && rm /tmp/ql.lisp

# Build system
RUN sbcl --noinform --non-interactive \
    --eval '(load "/root/quicklisp/setup.lisp")' \
    --eval '(push #p"/build/" asdf:*central-registry*)' \
    --eval '(asdf:load-system "agent-orrery")' \
    --eval '(load "packaging/build-binary.lisp")' \
    --eval "(orrery/build:build :target :${TARGET})"

# ─── Stage 2: Runtime ───
FROM docker.io/fukamachi/sbcl:${SBCL_VERSION}-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/dist/ /app/

EXPOSE 7890

ENV ORRERY_PORT=7890
ENV ORRERY_HOST=0.0.0.0

# Entry point set via manifest; override for specific targets
CMD ["sbcl", "--noinform", "--non-interactive", "--eval", "(format t \"Agent Orrery container ready~%\")"]

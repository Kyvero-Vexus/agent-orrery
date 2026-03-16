# Agent Orrery — Packaging build targets
# Bead: agent-orrery-eb0.7.3

SBCL ?= sbcl
QL_SETUP ?= $(HOME)/quicklisp/setup.lisp
PROJECT_ROOT := $(shell cd .. && pwd)
DIST_DIR := $(PROJECT_ROOT)/dist

.PHONY: all cli tui web mcclim container install-services clean

all: cli tui web

cli:
	@echo "=== Building CLI binary ==="
	@mkdir -p $(DIST_DIR)
	@$(SBCL) --noinform --non-interactive \
		--load $(QL_SETUP) \
		--eval '(push #p"$(PROJECT_ROOT)/" asdf:*central-registry*)' \
		--load build-binary.lisp \
		--eval '(orrery/build:build :target :cli)'

tui:
	@echo "=== Building TUI binary ==="
	@mkdir -p $(DIST_DIR)
	@$(SBCL) --noinform --non-interactive \
		--load $(QL_SETUP) \
		--eval '(push #p"$(PROJECT_ROOT)/" asdf:*central-registry*)' \
		--load build-binary.lisp \
		--eval '(orrery/build:build :target :tui)'

web:
	@echo "=== Building Web binary ==="
	@mkdir -p $(DIST_DIR)
	@$(SBCL) --noinform --non-interactive \
		--load $(QL_SETUP) \
		--eval '(push #p"$(PROJECT_ROOT)/" asdf:*central-registry*)' \
		--load build-binary.lisp \
		--eval '(orrery/build:build :target :web)'

mcclim:
	@echo "=== Building McCLIM binary ==="
	@mkdir -p $(DIST_DIR)
	@$(SBCL) --noinform --non-interactive \
		--load $(QL_SETUP) \
		--eval '(push #p"$(PROJECT_ROOT)/" asdf:*central-registry*)' \
		--load build-binary.lisp \
		--eval '(orrery/build:build :target :mcclim)'

container:
	@echo "=== Building OCI container ==="
	docker build -t agent-orrery:latest -f Dockerfile ..

install-services:
	@echo "=== Installing systemd services ==="
	sudo cp systemd/*.service /etc/systemd/system/
	sudo systemctl daemon-reload
	@echo "Services installed. Enable with: sudo systemctl enable agent-orrery-web"

clean:
	rm -rf $(DIST_DIR)

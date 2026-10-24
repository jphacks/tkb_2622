# 使い方: make -C infra plan STACK=envs/dev/gcp
# STACK は bootstrap または envs/<shared|dev|prod>/<gcp|cloudflare>
INFRA_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
STACKS := bootstrap $(patsubst $(INFRA_DIR)%/,%,$(sort $(dir $(wildcard $(INFRA_DIR)envs/*/*/main.tf))))
STACK ?=
TF = terraform -chdir="$(INFRA_DIR)$(STACK)"
# bootstrap はローカル state，それ以外は envs/backend.hcl の GCS バケットを使う
BACKEND_ARGS = $(if $(filter bootstrap,$(STACK)),,-backend-config="$(INFRA_DIR)envs/backend.hcl")

.PHONY: init plan apply output fmt validate lock check-stack

check-stack:
	@test -n "$(filter $(STACK),$(STACKS))" || { echo "STACK を指定してください: $(STACKS)"; exit 1; }

init: check-stack
	$(TF) init $(BACKEND_ARGS)

plan: check-stack
	$(TF) plan -out=tfplan

apply: check-stack
	$(TF) apply tfplan
	@rm -f "$(INFRA_DIR)$(STACK)/tfplan"

output: check-stack
	$(TF) output

fmt:
	terraform fmt -recursive "$(INFRA_DIR)"

# クラウドへ接続せずに構文・型を検査する
validate:
	terraform fmt -recursive -check "$(INFRA_DIR)"
	@for s in $(STACKS); do \
		echo "== $$s"; \
		terraform -chdir="$(INFRA_DIR)$$s" init -backend=false -input=false >/dev/null && \
		terraform -chdir="$(INFRA_DIR)$$s" validate -no-color || exit 1; \
	done

# macOS / Linux の開発者が同じロックファイルを使えるようにする
lock:
	@for s in $(STACKS); do \
		terraform -chdir="$(INFRA_DIR)$$s" providers lock \
			-platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64 || exit 1; \
	done

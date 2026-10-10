SHELL := /bin/bash
export ANSIBLE_LOCAL_TEMP ?= /tmp/uranus-ansible-local
export ANSIBLE_HOME ?= /tmp/uranus-ansible-home
export ANSIBLE_COLLECTIONS_PATH ?= $(HOME)/.ansible/collections:/usr/share/ansible/collections:/usr/lib/python3/dist-packages/ansible_collections
export ANSIBLE_CONFIG := $(CURDIR)/ansible-debian13.cfg

.PHONY: check test syntax lint
check: test syntax lint

test:
	python -m pytest -q tests

syntax:
	python scripts/check_syntax.py

lint:
	ansible-lint --offline -c .ansible-lint-debian13.yml playbooks/debian13 roles/debian13_* environments/hetzner/inventory.yml environments/hetzner/group_vars/all.yml .github/workflows/debian13.yml requirements.yml

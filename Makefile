SHELL := /bin/bash
export ANSIBLE_LOCAL_TEMP ?= /tmp/uranus-ansible-local
export ANSIBLE_HOME ?= /tmp/uranus-ansible-home
export ANSIBLE_COLLECTIONS_PATH ?= $(HOME)/.ansible/collections:/usr/share/ansible/collections:/usr/lib/python3/dist-packages/ansible_collections
export ANSIBLE_CONFIG := $(CURDIR)/ansible.cfg

.PHONY: check policy test syntax lint
check: policy test syntax lint

policy:
	python scripts/check_repository.py

test:
	python -m pytest -q tests

syntax:
	python scripts/check_syntax.py

lint:
	ansible-lint --offline -c .ansible-lint playbooks roles environments/hetzner/inventory.yml environments/hetzner/group_vars/all.yml .github/workflows/incus.yml requirements.yml

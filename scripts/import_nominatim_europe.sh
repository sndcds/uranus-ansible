#!/usr/bin/env bash
# Prepare/download/backup/import only when the operator runs this entrypoint.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"
if [[ ${1:-} == --help ]]; then
    cat <<'HELP'
Usage: scripts/import_nominatim_europe.sh [--preflight|--resize-db] [ansible-playbook options]

--preflight checks the existing database and capacity without downloads,
backups, service stops or database renames. A normal run imports Europe,
preserving the old database and its project. Do not run other deployments
concurrently. See docs/nominatim-europe.md for recovery and future deployments.
--resize-db first grows db01 to 600 GiB and prompts for host sudo in your terminal.
Incus may require a clean stop/start of db01, briefly interrupting its databases.
HELP
    exit 0
fi
extra_args=()
playbook_command=ansible-playbook
if [[ -x .venv/bin/ansible-playbook ]]; then
    playbook_command=$repo_dir/.venv/bin/ansible-playbook
fi
export ANSIBLE_CONFIG=$repo_dir/ansible.cfg
export ANSIBLE_LOCAL_TEMP=${ANSIBLE_LOCAL_TEMP:-/tmp/uranus-ansible-local}
export ANSIBLE_COLLECTIONS_PATH=${ANSIBLE_COLLECTIONS_PATH:-$HOME/.ansible/collections:/usr/share/ansible/collections:/usr/lib/python3/dist-packages/ansible_collections}
ssh_config=$(python3 scripts/resize_db01.py --prepare-ssh)
ssh_config_option=$(python3 -c 'import shlex,sys; print(shlex.join(["-F", sys.argv[1]]))' "$ssh_config")
export ANSIBLE_SSH_ARGS="${ANSIBLE_SSH_ARGS:--C -o ControlMaster=auto -o ControlPersist=60s} $ssh_config_option"
export ANSIBLE_TIMEOUT=${ANSIBLE_TIMEOUT:-60}
export ANSIBLE_NOCOWS=${ANSIBLE_NOCOWS:-1}
export URANUS_NOMINATIM_SSH_CONFIG=$ssh_config
if [[ ${1:-} == --resize-db ]]; then
    python3 scripts/resize_db01.py --ssh-config "$ssh_config"
    shift
fi
if [[ ${1:-} == --preflight ]]; then
    extra_args+=(-e debian13_nominatim_europe_preflight_only=true)
    shift
fi
exec "$playbook_command" playbooks/nominatim-europe.yml \
    -i environments/hetzner/inventory.yml \
    -i "${ssh_config%/*}/nominatim-inventory.json" \
    -e @environments/hetzner/deployment.yml \
    --vault-id pki@.uranus-private/pki/vault-password \
    --vault-id production@.uranus-private/secrets/vault-password \
    "${extra_args[@]}" "$@" \
    -e @environments/hetzner/nominatim-europe.yml

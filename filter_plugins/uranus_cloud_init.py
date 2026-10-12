"""Identify completed cloud-init failures covered by the Incus guest bootstrap."""
import re

from ansible.errors import AnsibleFilterError


def bootstrap_status(details):
    if not isinstance(details, dict) or not isinstance(details.get('errors'), list):
        raise AnsibleFilterError('Require the JSON cloud-init status with its errors list')
    errors = list(details['errors'])
    early_errors = []
    for stage in ['init-local', 'init', 'modules-config']:
        early_errors.extend(details.get(stage, {}).get('errors', []))
    final_errors = details.get('modules-final', {}).get('errors', [])
    failures = []
    for error in errors + final_errors:
        match = re.match(r"^\('(package-update-upgrade-install|scripts-user)',", str(error))
        failures.append(match.group(1) if match else 'unmanaged-error')
    terminal = details.get('stage') is None
    normal = details.get('status') in ['done', 'disabled'] and not errors and not final_errors
    recovery = details.get('status') == 'error' and bool(errors) and 'unmanaged-error' not in failures
    return {
        'allowed': terminal and not early_errors and (normal or recovery),
        'recover': terminal and not early_errors and recovery,
        'modules': sorted(set(failures)),
    }


class FilterModule:
    def filters(self):
        return {'uranus_cloud_init_bootstrap_status': bootstrap_status}

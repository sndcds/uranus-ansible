"""Identify completed cloud-init failures covered by verified DHCP and guest bootstrap."""
import re

from ansible.errors import AnsibleFilterError


def bootstrap_status(details):
    if not isinstance(details, dict) or not isinstance(details.get('errors'), list):
        raise AnsibleFilterError('Require the JSON cloud-init status with its errors list')
    errors = list(details['errors'])
    early_errors = details.get('init-local', {}).get('errors', []) + details.get('modules-config', {}).get('errors', [])
    init_errors = details.get('init', {}).get('errors', [])
    final_errors = details.get('modules-final', {}).get('errors', [])
    failures = []
    for error in errors + init_errors + final_errors:
        match = re.match(r"^\('(package-update-upgrade-install|scripts-user|bootcmd)',", str(error))
        failures.append(match.group(1) if match else 'unmanaged-error')
    # Only the exact historical managed DHCP bootcmd can be repaired by callers.
    # Other failures in early stages must still stop initialization.
    early_errors += [error for error in init_errors if not re.match(r"^\('bootcmd',", str(error))]
    terminal = details.get('stage') is None
    normal = details.get('status') in ['done', 'disabled'] and not errors and not init_errors and not final_errors
    recovery = details.get('status') == 'error' and bool(errors) and 'unmanaged-error' not in failures
    return {
        'allowed': terminal and not early_errors and (normal or recovery),
        'recover': terminal and not early_errors and recovery,
        'modules': sorted(set(failures)),
    }


def managed_bootcmd(config, expected_script):
    if not isinstance(config, dict):
        return False
    commands = config.get('bootcmd')
    return (isinstance(commands, list) and len(commands) == 1
            and isinstance(commands[0], list) and len(commands[0]) == 3
            and commands[0][:2] == ['sh', '-ec']
            and isinstance(commands[0][2], str)
            and commands[0][2].strip() == expected_script.strip())


class FilterModule:
    def filters(self):
        return {'uranus_cloud_init_bootstrap_status': bootstrap_status,
                'uranus_cloud_init_managed_bootcmd': managed_bootcmd}

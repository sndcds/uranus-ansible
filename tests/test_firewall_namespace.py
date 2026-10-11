import json
import os
import subprocess
import sys

import pytest
from conftest import ROOT


@pytest.mark.skipif(os.environ.get('URANUS_FIREWALL_INTEGRATION') != '1',
                    reason='Requires root, systemd and isolated network namespaces; enforced in CI')
def test_real_ssh_lockout_rolls_back_after_controller_sigkill(tmp_path):
    result = subprocess.run(['unshare', '--net', '--fork', sys.executable,
                             str(ROOT / 'scripts/check_firewall_namespace.py'), str(tmp_path)],
                            capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, result.stdout + result.stderr
    assert all(json.loads(result.stdout).values())

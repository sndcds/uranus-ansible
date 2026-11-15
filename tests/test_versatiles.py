"""Exercise publication guards with the real asynchronous Ansible import tasks."""
import getpass
import os
from pathlib import Path
import subprocess
import sys

import pytest
import yaml

from conftest import ROOT


@pytest.mark.parametrize('failure', ['none', 'download', 'validation'])
def test_partial_or_invalid_tilesets_are_never_published(tmp_path, failure):
    tile_dir = tmp_path / 'tiles'
    tile_dir.mkdir()
    binary = tmp_path / 'versatiles'
    binary.write_text(f'''#!{sys.executable}
from pathlib import Path
import sys
failure = {failure!r}
if sys.argv[1] == 'convert':
    Path(sys.argv[-1]).write_text('partial' if failure == 'download' else 'completed')
    sys.exit(9 if failure == 'download' else 0)
if sys.argv[1] == 'probe':
    assert Path(sys.argv[-1]).read_text() == 'completed'
    sys.exit(8 if failure == 'validation' else 0)
raise AssertionError(sys.argv)
''')
    binary.chmod(0o755)
    # Substitute only the CLI boundary; async, validation and atomic publication
    # execute the production tasks with actual local files and subprocesses.
    tasks = yaml.safe_load((ROOT / 'roles/debian13_versatiles/tasks/import.yml').read_text())
    for task in tasks:
        argv = task.get('ansible.builtin.command', {}).get('argv', [])
        if argv and argv[0] == '/usr/local/bin/versatiles':
            argv[0] = str(binary)
        if 'poll' in task:
            task['poll'] = 1
    playbook = tmp_path / 'import-test.yml'
    playbook.write_text(yaml.safe_dump([{
        'hosts': 'localhost', 'gather_facts': False,
        'vars': {
            'ansible_become': False, 'ansible_remote_tmp': str(tmp_path / 'remote'),
            'ansible_async_dir': str(tmp_path / 'async'),
            'versatiles_system_user': getpass.getuser(), 'versatiles_data_dir': str(tmp_path),
            'versatiles_tileset_name': 'europe.versatiles', 'versatiles_bbox': '-32,34,45,72',
            'versatiles_bbox_border': 3, 'versatiles_tiles_url': 'https://fixture.test/osm.versatiles',
            'debian13_versatiles_min_free_gib': 0, 'debian13_versatiles_import_timeout': 30,
        },
        'tasks': tasks,
        'handlers': [{'name': 'Restart Debian VersaTiles',
                      'ansible.builtin.debug': {'msg': 'Completed tileset can now be activated'}}],
    }]))
    result = subprocess.run(['ansible-playbook', '-i', 'localhost,', '-c', 'local', str(playbook)],
                            text=True, capture_output=True, env={
                                **os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
                                'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible'), 'ANSIBLE_NOCOWS': '1',
                            })
    final = tile_dir / 'europe.versatiles'
    assert result.returncode == (0 if failure == 'none' else 2), result.stdout + result.stderr
    if failure == 'none':
        assert final.read_text() == 'completed'
        assert not (tile_dir / 'europe.versatiles.building.versatiles').exists()
    else:
        assert not final.exists()

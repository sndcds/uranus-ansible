import importlib.util
from pathlib import Path
import sys

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'module_utils'))


@pytest.fixture
def settings():
    return yaml.safe_load((ROOT / 'environments/hetzner/group_vars/all.yml').read_text())


@pytest.fixture
def render(settings):
    from jinja2 import Environment, FileSystemLoader, StrictUndefined
    import json
    environment = Environment(
        loader=FileSystemLoader(ROOT / 'roles/incus_instance/templates'),
        undefined=StrictUndefined, keep_trailing_newline=True)
    environment.filters['to_json'] = json.dumps
    environment.filters['bool'] = bool
    environment.filters['regex_replace'] = __import__('re').sub
    def render_template(path, **variables):
        context = {**settings, **variables}
        context.setdefault('lookup', lambda kind, path: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureFixtureFixtureFixtureFixtureFixture tests')
        return environment.from_string((ROOT / path).read_text()).render(**context)
    return render_template

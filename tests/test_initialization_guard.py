import json

import pytest
from uranus_initialization import initialize


def test_initialization_claim_is_exclusive_and_survives_process_restart(tmp_path):
    claim = initialize(tmp_path, 'uranus_dev', 'claimed')
    with pytest.raises(ValueError, match='interrupted'):
        initialize(tmp_path, 'uranus_dev', 'claimed')
    pending = tmp_path / '.uranus_dev_initial_import_pending'
    assert json.loads(pending.read_text())['token'] == claim['token']
    with pytest.raises(ValueError, match='Mismatched'):
        initialize(tmp_path, 'uranus_dev', 'completed', token='wrong')
    assert pending.exists()
    initialize(tmp_path, 'uranus_dev', 'completed', token=claim['token'])
    assert not pending.exists() and (tmp_path / '.uranus_dev_initial_import_complete').exists()


def test_completion_failure_keeps_pending_and_existing_evidence(tmp_path):
    claim = initialize(tmp_path, 'uranus_dev', 'claimed')
    complete = tmp_path / '.uranus_dev_initial_import_complete'
    complete.write_text('Do not overwrite')
    with pytest.raises(FileExistsError):
        initialize(tmp_path, 'uranus_dev', 'completed', token=claim['token'])
    assert complete.read_text() == 'Do not overwrite'
    assert (tmp_path / '.uranus_dev_initial_import_pending').exists()


def test_claim_check_mode_writes_no_markers(tmp_path):
    assert initialize(tmp_path, 'uranus_dev', 'claimed', check_mode=True)['changed']
    assert not list(tmp_path.iterdir())

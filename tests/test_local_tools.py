import pytest
import uranus_safety as safety
from conftest import ROOT

@pytest.mark.parametrize('dump', [r'\! touch /tmp/forbidden', r'\connect other_db', r'\i other.sql', r'\gexec', 'DROP DATABASE valuable;', 'CREATE DATABASE unexpected;'])
def test_unsafe_initial_sql_dumps_are_rejected(dump, tmp_path):
    path = tmp_path / 'dump.sql'
    path.write_text(dump + '\n')
    with pytest.raises(safety.SafetyError):
        safety.validate_sql_dump(path)


def test_sql_copy_rows_are_treated_as_data_and_existing_repository_dumps_validate(tmp_path):
    path = tmp_path / 'dump.sql'
    path.write_text('COPY uranus.test FROM stdin;\nDROP DATABASE is only a data string here\n\\connect is data here\n\\.\n')
    safety.validate_sql_dump(path)
    for name in ['uranus.sql', 'uranus_dev.sql']:
        safety.validate_sql_dump(ROOT / name)


def test_incomplete_sql_copy_is_rejected(tmp_path):
    path = tmp_path / 'dump.sql'
    path.write_text('COPY uranus.test FROM stdin;\nunfinished data\n')
    with pytest.raises(safety.SafetyError):
        safety.validate_sql_dump(path)

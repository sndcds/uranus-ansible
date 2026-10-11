"""Durable exclusive initialization claims, written before database creation."""
import json
import os
from pathlib import Path
import re
import secrets


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def exclusive_record(path, record):
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(record, stream)
        stream.flush()
        os.fsync(stream.fileno())
    sync_directory(path.parent)


def initialize(state_dir, database, state, token=None, import_requested=False, check_mode=False):
    directory = Path(state_dir)
    if not re.fullmatch(r'[a-zA-Z0-9_]{1,63}', database):
        raise ValueError('Invalid database initialization identity')
    if any(p.is_symlink() for p in (directory, *directory.parents)) or not directory.is_dir():
        raise ValueError('Initialization state must be an existing protected directory')
    pending = directory / f'.{database}_initial_import_pending'
    complete = directory / f'.{database}_initial_import_complete'
    if state == 'claimed':
        if os.path.lexists(pending) or os.path.lexists(complete):
            raise ValueError('Initialization is interrupted or previously completed; recover manually')
        if check_mode:
            return {'changed': True}
        token = secrets.token_hex(32)
        exclusive_record(pending, {'database': database, 'token': token, 'import_requested': import_requested})
        return {'changed': True, 'token': token}
    if pending.is_symlink():
        raise ValueError('Symlink initialization marker is forbidden')
    record = json.loads(pending.read_text())
    if not token or record.get('token') != token or record.get('database') != database:
        raise ValueError('Mismatched initialization claim; preserve the database')
    if not check_mode:
        exclusive_record(complete, {**record, 'completed': True})
        pending.unlink()
        sync_directory(directory)
    return {'changed': True}

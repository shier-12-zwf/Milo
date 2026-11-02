#!/usr/bin/env python3
"""Atomically publish a previously built static dist archive on the Milo server."""
from pathlib import Path, PurePosixPath
import argparse
import os
import re
import shutil
import sys
import tarfile
import tempfile
import urllib.request


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path, help='tar.gz whose root contains index.html and assets/')
    parser.add_argument('release', help='unique release ID, e.g. 2026-09-23-001')
    args = parser.parse_args()
    if os.geteuid() != 0 or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,79}', args.release):
        raise RuntimeError('Root privileges and a safe release ID are required.')
    releases = Path('/opt/milo-web/releases')
    releases.mkdir(mode=0o755, parents=True, exist_ok=True)
    destination = releases / args.release
    if destination.exists():
        raise RuntimeError('This release already exists; choose a new release ID.')
    staging = Path(tempfile.mkdtemp(prefix='.staging-', dir=releases))
    current = Path('/opt/milo-web/current')
    if current.exists() and not current.is_symlink():
        shutil.rmtree(staging)
        raise RuntimeError('The current path must be a symlink; nothing was overwritten.')
    previous = os.readlink(current) if current.is_symlink() else None
    link = current.with_name('.current-next')
    try:
        with tarfile.open(args.archive, 'r:*') as archive:
            members = archive.getmembers()
            if sum(member.size for member in members) > 512 * 1024 * 1024:
                raise RuntimeError('The static release exceeds 512 MiB.')
            for member in members:
                path = PurePosixPath(member.name)
                if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
                    raise RuntimeError('Archive has an unsafe path or non-regular file.')
            archive.extractall(staging, members=members, filter='data')
        if not (staging / 'index.html').is_file() or not (staging / 'assets').is_dir():
            raise RuntimeError('Archive root must contain the Vite dist index.html and assets/.')
        for path in [staging, *staging.rglob('*')]:
            path.chmod(0o755 if path.is_dir() else 0o644)
        staging.rename(destination)
        link.unlink(missing_ok=True)
        link.symlink_to(destination)
        os.replace(link, current)
        try:
            expected = (destination / 'index.html').read_bytes()
            for route in ('/', '/app', '/privacy'):
                with urllib.request.urlopen('http://127.0.0.1:8080' + route, timeout=5) as response:
                    if response.status != 200 or response.read() != expected:
                        raise RuntimeError(f'The deployed SPA did not serve the expected document at {route}.')
        except Exception:
            if previous is None:
                current.unlink(missing_ok=True)
            else:
                link.symlink_to(previous)
                os.replace(link, current)
            raise
        print(f'Published private web release: {destination}')
        print('Verified /, /app, /privacy on 127.0.0.1:8080. Public ports unchanged.')
    finally:
        if staging.exists():
            shutil.rmtree(staging)
        link.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Publish failed: {error}', file=sys.stderr)
        sys.exit(1)

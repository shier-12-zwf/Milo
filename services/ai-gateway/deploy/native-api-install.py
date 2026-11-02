#!/usr/bin/env python3
"""Install only Milo's native API virtual host; packages/certificates stay external."""
import argparse
from datetime import datetime, timezone
import fcntl
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile


MARKER = b'# Managed by MILO native-api-install.py.'
TLS_MARKER = b'# BEGIN TLS: omitted by the installer in --bootstrap mode.\n'
SITE = Path('/etc/nginx/sites-available/milo-native-api.conf')
ENABLED = Path('/etc/nginx/sites-enabled/milo-native-api.conf')
BACKUPS = Path('/etc/nginx/milo-native-api-backups')
ACME = Path('/var/lib/milo-acme')
LOCK = Path('/run/lock/milo-native-api-install.lock')


def directory(path, create=False, mode=0o755):
    """Reject symlinks in every directory component of a managed destination."""
    if path.parent != path:
        directory(path.parent)
    try:
        info = path.lstat()
    except FileNotFoundError:
        if not create:
            raise RuntimeError(f'Required directory is missing: {path}')
        path.mkdir(mode=mode)
        return
    if not stat.S_ISDIR(info.st_mode):
        raise RuntimeError(f'Refusing a non-directory or symlink: {path}')


def existing_site():
    try:
        info = SITE.lstat()
    except FileNotFoundError:
        return None, 0o644
    if not stat.S_ISREG(info.st_mode):
        raise RuntimeError(f'Refusing a non-regular site file: {SITE}')
    content = SITE.read_bytes()
    if not content.startswith(MARKER):
        raise RuntimeError(f'Refusing to replace an unmanaged site: {SITE}')
    return content, stat.S_IMODE(info.st_mode)


def existing_link():
    if not os.path.lexists(ENABLED):
        return False
    if not ENABLED.is_symlink() or ENABLED.resolve() != SITE:
        raise RuntimeError(f'Refusing an unexpected enabled-site path: {ENABLED}')
    if not SITE.is_file():
        raise RuntimeError('The existing enabled-site link is broken.')
    return True


def atomic_write(path, content, mode):
    fd, temporary = tempfile.mkstemp(prefix='.milo-native-', dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def succeeds(command):
    # Diagnostics can expand other sites' private includes; never print their output.
    return subprocess.run(command, capture_output=True, timeout=30).returncode == 0


def candidate(tls):
    source = Path(__file__).with_name('native-api-nginx.conf')
    if source.is_symlink() or not source.is_file():
        raise RuntimeError('The adjacent Nginx template must be a regular file.')
    content = source.read_bytes()
    if not content.startswith(MARKER) or content.count(TLS_MARKER) != 1:
        raise RuntimeError('The Nginx template has an unexpected format.')
    if tls:
        for name in ('fullchain.pem', 'privkey.pem'):
            certificate = Path('/etc/letsencrypt/live/milomood.xyz') / name
            resolved = certificate.resolve(strict=True)
            archive = Path('/etc/letsencrypt/archive/milomood.xyz')
            if certificate.is_symlink() and archive not in resolved.parents:
                raise RuntimeError('A certificate link points outside this API host archive.')
            if not resolved.is_file() or not os.access(resolved, os.R_OK):
                raise RuntimeError('The API certificate or key is missing or unreadable.')
        return content
    return content.split(TLS_MARKER, 1)[0]


def install(tls):
    nginx = shutil.which('nginx')
    systemctl = shutil.which('systemctl')
    if nginx is None or systemctl is None:
        raise RuntimeError('Nginx and systemctl must already be installed.')
    content = candidate(tls)
    directory(SITE.parent)
    directory(ENABLED.parent)
    previous, previous_mode = existing_site()
    had_link = existing_link()
    if not succeeds([nginx, '-t']):
        raise RuntimeError('The existing Nginx configuration does not pass validation.')
    if not succeeds([systemctl, 'is-active', '--quiet', 'nginx']):
        raise RuntimeError('Nginx must already be running; this installer only reloads it.')

    directory(ACME, create=True)
    directory(ACME / '.well-known', create=True)
    directory(ACME / '.well-known/acme-challenge', create=True)
    backup = None
    if previous is not None:
        directory(BACKUPS, create=True, mode=0o700)
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        backup = BACKUPS / f'milo-native-api-{stamp}.conf'
        with backup.open('xb') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(previous)

    created_link = False
    wrote_site = False
    try:
        atomic_write(SITE, content, 0o644)
        wrote_site = True
        if not had_link:
            ENABLED.symlink_to(SITE)
            created_link = True
        if not succeeds([nginx, '-t']):
            raise RuntimeError('Nginx rejected the candidate configuration.')
        if not succeeds([systemctl, 'reload', 'nginx']):
            raise RuntimeError('Nginx could not reload the candidate configuration.')
    except Exception as error:
        # Roll back only the file/link this invocation owns. Other sites are untouched.
        if not wrote_site:
            raise
        if created_link:
            if not ENABLED.is_symlink() or ENABLED.resolve() != SITE:
                raise RuntimeError('Enabled-site path changed concurrently; manual recovery needed.') from error
            ENABLED.unlink()
        if SITE.is_symlink() or SITE.read_bytes() != content:
            raise RuntimeError('Site changed concurrently; manual recovery needed.') from error
        if previous is None:
            SITE.unlink()
        else:
            atomic_write(SITE, previous, previous_mode)
        if not succeeds([nginx, '-t']) or not succeeds([systemctl, 'reload', 'nginx']):
            raise RuntimeError('Previous files restored, but Nginx recovery reload failed.') from error
        raise RuntimeError(f'{error} Previous configuration restored and reloaded.') from error

    mode = 'TLS API' if tls else 'HTTP ACME bootstrap'
    print(f'{mode} installed for milomood.xyz. Other site files were not modified.')
    if backup is not None:
        print(f'Previous API configuration backup: {backup}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--bootstrap', action='store_true', help='Enable HTTP ACME path before certificate issuance.')
    mode.add_argument('--tls', action='store_true', help='Enable HTTPS using the existing host certificate.')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise RuntimeError('Run this installer as root on the server.')
    directory(LOCK.parent)
    descriptor = os.open(LOCK, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise RuntimeError('The installer lock is not a regular file.')
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        install(args.tls)
    finally:
        os.close(descriptor)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Install failed: {error}', file=sys.stderr)
        sys.exit(1)

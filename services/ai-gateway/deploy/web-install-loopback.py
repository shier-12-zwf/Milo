#!/usr/bin/env python3
"""Install Milo's private Nginx preview without opening public HTTP/HTTPS ports."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

MARKER = b"Managed by MILO"
SITE = Path('/etc/nginx/sites-available/milo-web-loopback.conf')
ENABLED = Path('/etc/nginx/sites-enabled/milo-web-loopback.conf')
AUTH = Path('/etc/nginx/milo-private/gateway-auth.conf')


def atomic_write(path, content, mode):
    fd, temp = tempfile.mkstemp(prefix='.milo-', dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def main():
    if os.geteuid() != 0:
        raise RuntimeError('Run this installer as root on the server.')
    template = Path(__file__).with_name('web-nginx-loopback.conf').read_bytes()
    if MARKER not in template or b'listen 127.0.0.1:8080;' not in template:
        raise RuntimeError('The loopback template is missing or changed unexpectedly.')
    for path in (SITE, AUTH):
        if path.exists() and MARKER not in path.read_bytes():
            raise RuntimeError(f'Refusing to overwrite an unmanaged file: {path}')
    if ENABLED.is_symlink():
        if ENABLED.resolve() != SITE:
            raise RuntimeError('The enabled site points to a different configuration.')
    elif ENABLED.exists():
        raise RuntimeError('The enabled site path already contains an unmanaged file.')

    values = {}
    for line in Path('/etc/milo-gateway/gateway.env').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip().strip('\"\'')
    token = values.get('GATEWAY_BEARER_TOKEN', '')
    if not re.fullmatch(r'[A-Za-z0-9._~+/-]{32,}={0,2}', token):
        raise RuntimeError('Gateway token is missing or is not safe for a literal Nginx header.')
    if values.get('HOST') != '127.0.0.1' or values.get('TRUST_LOOPBACK_PROXY') != 'true':
        raise RuntimeError('The gateway must listen on loopback and trust its loopback proxy.')

    SITE.parent.mkdir(parents=True, exist_ok=True)
    ENABLED.parent.mkdir(parents=True, exist_ok=True)
    AUTH.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    AUTH.parent.chmod(0o700)
    previous = {path: path.read_bytes() if path.exists() else None for path in (SITE, AUTH)}
    had_link = ENABLED.is_symlink()
    try:
        atomic_write(AUTH, ('# Managed by MILO; server-only credential.\n'
                           f'proxy_set_header Authorization "Bearer {token}";\n').encode(), 0o600)
        atomic_write(SITE, template, 0o644)
        if not had_link:
            ENABLED.symlink_to(SITE)
        # Never print nginx -T: it expands the private Authorization include.
        result = subprocess.run(['nginx', '-t'], capture_output=True)
        if result.returncode:
            raise RuntimeError('Nginx rejected the candidate configuration; previous files restored.')
    except Exception:
        for path, content in previous.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, content, 0o600 if path == AUTH else 0o644)
        if not had_link:
            ENABLED.unlink(missing_ok=True)
        raise

    current = Path('/opt/milo-web/current')
    if not current.exists() and not current.is_symlink():
        placeholder = Path('/opt/milo-web/releases/placeholder')
        placeholder.mkdir(mode=0o755, parents=True, exist_ok=True)
        placeholder.joinpath('index.html').write_text(
            '<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
            '<title>MILO</title><body><h1>MILO 正在准备中</h1></body></html>')
        current.symlink_to(placeholder)
    subprocess.run(['systemctl', 'enable', 'nginx'], check=True, capture_output=True)
    subprocess.run(['systemctl', 'reload-or-restart', 'nginx'], check=True, capture_output=True)
    print('Private preview configured on 127.0.0.1:8080; no public site or certificate created.')
    print('Static root: /opt/milo-web/current; API upstream: 127.0.0.1:8787.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Do not include command output or configuration text in errors.
        print(f'Install failed: {error}', file=sys.stderr)
        sys.exit(1)

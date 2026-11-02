#!/usr/bin/env python3
"""Install pinned Huawei iOS SDKs inside this project; never touch global Pods.

--verify checks every installed file without network access.
--archive-cache PATH reuses already downloaded, SHA-verified ZIPs inside the repo.
"""
from __future__ import annotations
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat
import sys
import tempfile
import urllib.request
import zipfile

IOS = Path(__file__).resolve().parents[1]
ROOT = IOS.parents[1]
LOCK = IOS / 'agc-sdk-lock.json'
VENDOR = IOS / 'Vendor' / 'AGConnect'
RECEIPT = '.installed.json'


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def inventory(directory: Path) -> dict:
    result = {}
    for path in sorted(directory.rglob('*')):
        relative = path.relative_to(directory).as_posix()
        if relative == RECEIPT:
            continue
        if path.is_symlink():
            # A symlink escaping the managed install is never accepted.
            path.resolve().relative_to(directory.resolve())
            result[relative] = {'symlink': os.readlink(path)}
        elif path.is_file():
            result[relative] = {'sha256': sha(path)}
    return result


def validate_frameworks(directory: Path, lock: dict) -> None:
    for package in lock['packages']:
        framework = directory / package['framework']
        with (framework / 'Info.plist').open('rb') as stream:
            libraries = plistlib.load(stream)['AvailableLibraries']
        for variant in [None, 'simulator']:
            matches = [lib for lib in libraries if lib['SupportedPlatform'] == 'ios'
                       and lib.get('SupportedPlatformVariant') == variant
                       and 'arm64' in lib['SupportedArchitectures']]
            if len(matches) != 1:
                raise ValueError(f"Missing arm64 iOS {variant or 'device'} in {framework.name}")
            lib = matches[0]
            binary = framework / lib['LibraryIdentifier'] / lib['BinaryPath']
            if not binary.is_file() or binary.stat().st_size == 0:
                raise ValueError(f'Missing SDK binary: {binary}')
        for resource in package['resources']:
            if not (directory / resource).is_dir():
                raise ValueError(f'Missing required resource bundle: {resource}')


def verified(directory: Path, lock: dict) -> bool:
    try:
        receipt = json.loads((directory / RECEIPT).read_text())
        if receipt['lockSHA256'] != sha(LOCK):
            return False
        if receipt['files'] != inventory(directory):
            return False
        validate_frameworks(directory, lock)
        return True
    except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException):
        return False


def safe_extract(archive: Path, destination: Path) -> None:
    """Extract regular files and internal symlinks; reject traversal/devices."""
    destination.mkdir()
    symlinks = []
    seen = set()
    with zipfile.ZipFile(archive) as package:
        if sum(entry.file_size for entry in package.infolist()) > 256 * 1024 * 1024:
            raise ValueError('SDK archive is unexpectedly large')
        for entry in package.infolist():
            name = PurePosixPath(entry.filename)
            if name.is_absolute() or '..' in name.parts or '\\' in entry.filename:
                raise ValueError('Unsafe SDK archive path')
            if entry.filename in seen:
                raise ValueError('Duplicate SDK archive entry')
            seen.add(entry.filename)
            target = destination.joinpath(*name.parts)
            target.resolve().relative_to(destination.resolve())
            mode = entry.external_attr >> 16
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif stat.S_ISLNK(mode):
                symlinks.append((target, package.read(entry).decode('utf-8')))
            elif stat.S_IFMT(mode) in (0, stat.S_IFREG):
                target.parent.mkdir(parents=True, exist_ok=True)
                with package.open(entry) as source, target.open('xb') as output:
                    shutil.copyfileobj(source, output)
                target.chmod(0o755 if mode & 0o111 else 0o644)
            else:
                raise ValueError('Unsupported SDK archive entry type')
    for target, link in symlinks:
        if os.path.isabs(link):
            raise ValueError('Absolute SDK archive symlink')
        (target.parent / link).resolve().relative_to(destination.resolve())
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(link)
    # Validate again after all links exist, including chained links.
    inventory(destination)


def archive_for(package: dict, cache: Path, supplied: Path | None) -> Path:
    destination = cache / (package['name'] + '-' + package['version'] + '.zip')
    if destination.is_file() and sha(destination) == package['sha256']:
        return destination
    if supplied:
        for candidate in [supplied / destination.name, supplied / (package['name'] + '.zip')]:
            if candidate.is_file() and sha(candidate) == package['sha256']:
                shutil.copyfile(candidate, destination)
                return destination
    url = package['url']
    if not url.startswith('https://'):
        raise ValueError('SDK URLs must use HTTPS')
    error = None
    for _ in range(2):
        temporary = destination.with_suffix('.download')
        try:
            with urllib.request.urlopen(url, timeout=45) as source, temporary.open('wb') as output:
                total = 0
                while block := source.read(1024 * 1024):
                    total += len(block)
                    if total > 64 * 1024 * 1024:
                        raise ValueError('SDK download is unexpectedly large')
                    output.write(block)
            if sha(temporary) != package['sha256']:
                raise ValueError('SDK SHA-256 mismatch: ' + package['name'])
            temporary.replace(destination)
            return destination
        except (OSError, ValueError) as failure:
            error = failure
        finally:
            temporary.unlink(missing_ok=True)
    raise RuntimeError('Unable to download verified SDK: ' + package['name']) from error


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--archive-cache', type=Path)
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text())
    if lock['schemaVersion'] != 1 or not lock['version'].replace('.', '').isdigit():
        raise ValueError('Unsupported SDK lock')
    supplied = args.archive_cache.resolve() if args.archive_cache else None
    if supplied:
        supplied.relative_to(ROOT)
    VENDOR.resolve().relative_to(ROOT)
    VENDOR.mkdir(parents=True, exist_ok=True)
    destination = VENDOR / lock['version']
    with (VENDOR / '.install.lock').open('a') as mutex:
        fcntl.flock(mutex, fcntl.LOCK_EX)
        if verified(destination, lock):
            print('Verified AGC SDK ' + lock['version'] + ': every installed file matches its receipt.')
            return
        if args.verify:
            raise ValueError('AGC SDK is missing or changed; run install-agc-sdk.py before xcodegen.')
        cache = VENDOR / '.downloads'
        cache.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.install-', dir=VENDOR) as work:
            work = Path(work)
            assembled = work / 'assembled'
            assembled.mkdir()
            for package in lock['packages']:
                if package['version'] != lock['version']:
                    raise ValueError('SDK package versions must match')
                archive = archive_for(package, cache, supplied)
                extracted = work / package['name']
                safe_extract(archive, extracted)
                for relative in [package['framework'], *package['resources']]:
                    shutil.copytree(extracted / relative, assembled / relative, symlinks=True)
                licenses = assembled / 'Licenses'
                licenses.mkdir(exist_ok=True)
                shutil.copyfile(extracted / 'LICENSE', licenses / (package['name'] + '.txt'))
            validate_frameworks(assembled, lock)
            (assembled / RECEIPT).write_text(json.dumps({'lockSHA256': sha(LOCK), 'files': inventory(assembled)}, indent=2) + '\n')
            if destination.is_symlink():
                raise ValueError('SDK installation destination cannot be a symlink')
            previous = work / 'previous'
            if destination.exists():
                destination.rename(previous)
            try:
                assembled.rename(destination)
            except OSError:
                if previous.exists():
                    previous.rename(destination)
                raise
        if not verified(destination, lock):
            raise ValueError('Post-install SDK verification failed')
        print('Installed and verified AGC SDK ' + lock['version'] + ' in ' + str(destination.relative_to(ROOT)))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print('AGC SDK installation failed: ' + str(error), file=sys.stderr)
        sys.exit(1)

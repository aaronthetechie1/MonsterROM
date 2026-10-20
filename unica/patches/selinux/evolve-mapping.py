#!/usr/bin/env python3
"""Carry verified public type splits forward, retaining target compatibility."""
import pathlib
import re
import sys


def read_sets(path, version):
    text = path.read_text()
    result = {}
    suffix = '_' + version.replace('.', '_')
    for line in text.splitlines():
        if not line.lstrip().startswith('(typeattributeset '):
            continue
        match = re.fullmatch(r'\(typeattributeset ([\w-]+) \(([\w -]+)\)\)', line)
        if not match:
            raise SystemExit(f'Unsupported mapping expression in {path}: {line}')
        alias, members = match.groups()
        if not alias.endswith(suffix):
            raise SystemExit(f'Unexpected mapping version in {path}: {alias}')
        name = alias[:-len(suffix)]
        if name in result:
            raise SystemExit(f'Duplicate public mapping in {path}: {alias}')
        result[name] = (set(members.split()), line)
    if not result and any(line.strip() and not line.lstrip().startswith(';') for line in text.splitlines()):
        raise SystemExit(f'No public mappings in {path}')
    return text, result


def main():
    stock_old, stock_bridge, current_bridge, destination = map(pathlib.Path, sys.argv[1:])
    version = destination.stem
    _, old = read_sets(stock_old, version)
    _, bridge = read_sets(stock_bridge, '31.0')
    _, current = read_sets(current_bridge, '31.0')
    text, installed = read_sets(destination, version)
    changes = []
    for name, (old_members, _) in old.items():
        if name not in bridge or name not in current:
            continue
        bridge_members = bridge[name][0]
        current_members = current[name][0]
        if not bridge_members <= current_members:
            raise SystemExit(f'Non-additive public mapping evolution: {name}')
        additions = current_members - bridge_members
        if not additions:
            continue
        # Only an additive evolution of the SAME public alias is supported.
        # API30 may contain extra legacy members absent from API31: retain them.
        if not bridge_members <= old_members:
            raise SystemExit(f'Non-additive public mapping evolution: {name}')
        if name not in installed:
            raise SystemExit(f'Missing destination public mapping: {name}')
        wanted = old_members | additions
        members, line = installed[name]
        if members not in (old_members, wanted):
            raise SystemExit(f'Unexpected destination mapping members: {name}')
        if members != wanted:
            replacement = f'(typeattributeset {name}_{version.replace(".", "_")} ({" ".join(sorted(wanted))}))'
            text = text.replace(line, replacement, 1)
            changes.append(f'{name}: {", ".join(sorted(additions))}')
    if changes:
        # All contracts are checked before writing; preserve mode and metadata.
        destination.write_text(text)
        print('Updated public compatibility mappings: ' + '; '.join(changes))


if __name__ == '__main__':
    main()

"""The original Game Boy Color ROM (not part of this repository).

Looked for in this order: the WACKY_GBROM environment variable, the project directory, its
parent directory. Expected: "Wacky Races (Europe) (En,Fr,De,Es,It,Nl).gbc", 1 MB,
SHA-1 dba18064c886cebe4c4be80f941622f377adab98."""
import os, sys, hashlib

NAME = 'Wacky Races (Europe) (En,Fr,De,Es,It,Nl).gbc'
SHA1 = 'dba18064c886cebe4c4be80f941622f377adab98'
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def path():
    cands = [os.environ.get('WACKY_GBROM', ''), os.path.join(PROJECT, NAME),
             os.path.join(os.path.dirname(PROJECT), NAME)]
    for p in cands:
        if p and os.path.isfile(p):
            return p
    sys.exit(f'ROM not found: put "{NAME}" in {PROJECT} (or its parent directory), '
             'or set WACKY_GBROM to its path')


def load():
    p = path()
    data = open(p, 'rb').read()
    if hashlib.sha1(data).hexdigest() != SHA1:
        print(f'warning: {p} is not the expected ROM (SHA-1 {SHA1})', file=sys.stderr)
    return data

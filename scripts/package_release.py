#!/usr/bin/env python3
"""Validate the addon and make a reproducible installable GitHub release ZIP."""
from pathlib import Path
import re, sys, zipfile, argparse
ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / 'VibeFishin.toc'
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true', help='Validate sources, no release package')
args = parser.parse_args()
manifest = TOC.read_text(encoding='utf-8')
version_match = re.search(r'^## Version:\s*([^\s]+)', manifest, re.MULTILINE)
assert version_match, 'Missing Version in toc'
version = version_match.group(1)
assert re.search(r'^## Interface:\s*16001\s*$', manifest, re.MULTILINE), 'Interface mismatch'
assert '## Title: Vibe - Fishing Aquarium' in manifest, 'Unexpected addon title'
assert '## Author: Pepkilz' in manifest, 'Unexpected author'
assert '## SavedVariablesPerCharacter: VibeFishinDB' in manifest, 'Saved variables renamed'
# WowUpHub recognizes the Forever-specific TOC and uses it for game flavor detection.
forever_toc = ROOT / 'VibeFishin_Forever.toc'
assert forever_toc.is_file(), 'Missing WowUpHub Forever-specific TOC'
forever_manifest = forever_toc.read_text(encoding='utf-8')
assert forever_manifest == manifest, 'Forever and standard TOC metadata differ'

loaded = []
for line in manifest.splitlines():
    line=line.strip()
    if line and not line.startswith('#'):
        f=ROOT / line.replace('\\','/')
        assert f.is_file(), f'Missing .toc source: {line}'
        loaded.append(f)
assert len(loaded) == 1, 'Unexpected .toc Lua load order'
lua=loaded[0].read_text(encoding='utf-8')
assert f'v{version}' in lua or f' {version} ' in lua, 'Lua version header mismatch'
assert 'DeleteCursorItem' not in lua and 'SplitContainerItem' not in lua, 'Item deletion code present'
textures=set(re.findall(r'Interface\\\\AddOns\\\\VibeFishin\\\\Media\\\\([a-zA-Z0-9_.-]+)',lua))
for name in textures:
    path=ROOT/'Media'/name
    if not path.exists() and not (ROOT/'Media'/(name+'.tga')).exists():
        raise AssertionError(f'Missing media texture {name}')
assert len(textures)>=8, f'Unexpected texture count {len(textures)}'
media = sorted((ROOT/'Media').glob('*.tga'))
assert len(media)==8, f'Unexpected media inventory: {len(media)}'
print(f'PASS: v{version}; {len(loaded)} Lua entry; {len(media)} textures; no item deletion API')
if not args.check:
    out=ROOT / f'VibeFishin-v{version}-forever.zip'
    included=[ROOT/'VibeFishin.toc',ROOT/'VibeFishin_Forever.toc',ROOT/'README.md',ROOT/'CHANGELOG.md',ROOT/'CONTRIBUTING.md']
    included += sorted((ROOT/'Core').rglob('*.lua'))
    included += media
    included += sorted((ROOT/'Docs').rglob('*.md'))
    with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for f in included:
            z.write(f,'VibeFishin/'+str(f.relative_to(ROOT)))
    with zipfile.ZipFile(out) as z:
        assert z.testzip() is None, 'ZIP integrity failure'
        names = z.namelist()
        assert all(x.startswith('VibeFishin/') for x in names), 'Unexpected archive root'
        assert 'VibeFishin/VibeFishin.toc' in names, 'Missing TOC in archive root'
        assert 'VibeFishin/VibeFishin_Forever.toc' in names, 'Missing Forever TOC for WowUpHub'
    print('Created:',out)

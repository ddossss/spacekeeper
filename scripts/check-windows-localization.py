#!/usr/bin/env python3
"""Check Windows source keys against the shared and platform catalogs."""
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
catalog = json.loads((root / 'Sources/SpacekeeperCore/Resources/translations.json').read_text(encoding='utf-8'))
catalog.update(json.loads((root / 'windows/Spacekeeper.Core/translations.json').read_text(encoding='utf-8')))
missing = set()
for folder in ('Spacekeeper.Core', 'Spacekeeper.Windows'):
    for file in (root / 'windows' / folder).glob('*.cs'):
        if file.name.endswith('Validation.cs'):
            continue
        for key in re.findall(r'"([^"\n]*[가-힣][^"\n]*)"', file.read_text(encoding='utf-8')):
            if key not in catalog and key not in {'한국어', '일'}:
                missing.add(key)
for days in (7, 14, 30, 90):
    if f'{days}일' not in catalog:
        missing.add(f'{days}일')
assert not missing, f'Missing Windows translations: {sorted(missing)}'
for key, values in catalog.items():
    for language in ('en', 'ja'):
        assert values.get(language), (key, language)
        assert sorted(re.findall(r'\{\d+\}', key)) == sorted(re.findall(r'\{\d+\}', values[language])), (key, language)
print(f'PASS: Windows source coverage and {len(catalog)} bilingual catalog entries')

#!/usr/bin/env python3
"""Check app-authored Korean message keys and translation placeholders."""
from pathlib import Path
import re,json
base=Path(__file__).resolve().parent.parent
keys=set()
def parse_string(s,i,wrap=False):
    out='"'; key=''; n=0; j=i+1
    while j<len(s):
        if s[j]=='"':
            out+='"'; j+=1
            if re.search('[가-힣]',key):
                keys.add(key)
                if wrap: out='L('+out+')'
            return out,j,key
        if s.startswith('\\(',j):
            expression,j=code(s,j+2,wrap,closing=True)
            out+='\\('+expression+')';key+='{'+str(n)+'}'; n+=1
        elif s[j]=='\\':
            esc=s[j:j+2];out+=esc;key+= {'\\n':'\n','\\t':'\t','\\"':'"','\\\\':'\\'}.get(esc,esc);j+=2
        else: out+=s[j];key+=s[j];j+=1
    raise ValueError('Unclosed string')
def code(s,i=0,wrap=False,closing=False):
    out='';depth=0
    while i<len(s):
        if s.startswith('//',i):
            end=s.find('\n',i)
            if end<0: return out+s[i:],len(s)
            out+=s[i:end+1];i=end+1
        elif s[i]=='"':
            text,i,_=parse_string(s,i,wrap);out+=text
        elif closing and s[i]==')' and depth==0: return out,i+1
        else:
            if s[i]=='(':depth+=1
            if s[i]==')':depth-=1
            out+=s[i];i+=1
    return out,i

for path in (base / "Sources").rglob("*.swift"):
    if path.name not in ["Localization.swift", "UIValidation.swift"]:
        code(path.read_text())
catalog=json.loads((base / "Sources/SpacekeeperCore/Resources/translations.json").read_text())
errors=[]
for key in keys:
    for language in ["en","ja"]:
        value=catalog.get(key,{}).get(language)
        if not value: errors.append(f"Missing {language}: {key}")
        elif sorted(re.findall(r"\{[0-9]+\}|%02d",key)) != sorted(re.findall(r"\{[0-9]+\}|%02d",value)):
            errors.append(f"Placeholder mismatch {language}: {key}")
if errors:
    raise SystemExit("\n".join(errors))
print(f"PASS: {len(keys)} source messages have complete English/Japanese translations and matching placeholders")

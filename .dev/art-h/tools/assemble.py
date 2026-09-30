#!/usr/bin/env python3
# 把 styles/*.swift 拼成交付的 HairStyles.swift
import os,sys
SP=os.environ['SP']
order=['ponytail','bun','twinBuns','long','messy','buzz','curly']
out=open(SP+'/styles/_header.swift').read()
for n in order:
    t=open(SP+f'/styles/{n}.swift').read()
    if not t.endswith('\n'): t+='\n'
    out+=t
out+='}\n'
dst=os.environ['SRC']
open(dst,'w').write(out)
print('assembled ->',dst,len(out.splitlines()),'lines')

#!/usr/bin/env python3
import os,sys
from long_gen import *
SP=os.environ['SP']

def paint(edges, sheen, strands, crown=None, rim=True, shade=True, extra=None, rimx=None):
    inner=interior_rows(edges)
    p={}
    for y,xs in inner.items():
        if not xs: continue
        xmin,xmax=min(xs),max(xs)
        for x in xs:
            c='H'
            if rim and x==xmin and y>=2: c='h'
            if shade and x==xmax and y>=1: c='g'
            p[(x,y)]=c
    # 高光带
    for (x0,x1,y0,y1) in sheen:
        for y in range(y0,y1+1):
            for x in range(x0,x1+1):
                if (x,y) in p and p[(x,y)] not in 'g': p[(x,y)]='h'
    # 发丝线
    for (x,y0,y1) in strands:
        for y in range(y0,y1+1):
            if (x,y) in p and p[(x,y)]!='g': p[(x,y)]='g'
    if crown:
        for (x,y,c) in crown:
            if (x,y) in p: p[(x,y)]=c
    if extra:
        for (x,y,c) in extra: 
            if (x,y) in p: p[(x,y)]=c
    return p

LNOTES={'back':'背面：发盖住整个后脑，披到肩背，中间一道高光带 + 发丝线；从脖子起一级一级内收，下端微微内收、发梢有个缺口',
 'threeQuarterBack':'3/4 背面：同背面，高光带偏左；右侧第 10–11 列第 8–10 行留给耳朵和脸颊',
 'side':'侧面：长发垂在脑后（盖住耳朵），发丝从头顶分线处顺着往后往下流',
 'threeQuarterFront':'3/4 正面：中分刘海，近侧（左）一缕长发垂到肩前，远侧（右）稍窄',
 'front':'正面：中分刘海，两缕长发垂在脸两侧一直到肩前（3 格宽，带一格高光）'}
def block(facing, edges, notches, det):
    return f'''        // {LNOTES[facing]}
        addHairFull(book, "long", .{facing}, mask: """
{mask_text(edges,notches)}
        """, detail: """
{detail_text(det)}
        """)
'''
E={}
# ---- 背面 ----
back={0:(3,8),1:(2,9),2:(1,10)}
for y in range(3,13): back[y]=(0,11)
for y in (13,14): back[y]=(1,10)
for y in (15,16): back[y]=(2,9)
crown=[(3,1,'h'),(4,1,'r'),(5,1,'r'),(6,1,'H'),(7,1,'H'),(8,1,'g'),(2,2,'h'),(3,2,'h'),(4,2,'h'),(5,2,'H'),(9,2,'g')]
sheen=[(4,5,3,11),(4,4,12,13)]
strands=[(7,6,10),(8,11,14),(3,9,12),(2,13,14)]
det=paint(back,sheen,strands,crown=crown)
det[(4,0)]='r'; det[(5,0)]='r'
E['back']=block('back',back,{16:[5,6]},det)
# ---- 3/4 背面 ----
q=dict(back)
q[7]=(0,10)
for y in (8,9,10): q[y]=(0,9)
for y in (11,12): q[y]=(0,10)
sheen=[(3,4,3,11),(3,3,12,13)]
strands=[(6,6,10),(7,11,14),(2,9,12)]
det=paint(q,sheen,strands,crown=[(3,1,'h'),(4,1,'r'),(5,1,'r'),(6,1,'H'),(7,1,'H'),(8,1,'g'),(2,2,'h'),(3,2,'h'),(4,2,'H'),(9,2,'g')])
det[(4,0)]='r'; det[(5,0)]='r'
E['threeQuarterBack']=block('threeQuarterBack',q,{16:[5,6]},det)
open(SP+'/styles/_long_back.txt','w').write(E['back']+E['threeQuarterBack'])
print(E['back'])

# ---- 侧面（朝右）----
side={0:(3,8),1:(2,9),2:(1,10),3:(-1,10),4:(-1,10),5:(-1,8),6:(-1,6),7:(-1,6),8:(-1,5),9:(-1,5),10:(-1,4),11:(-1,4),12:(-1,3),13:(-1,3),14:(-1,3),15:(-1,2),16:(-1,1)}
sheen=[(0,1,8,13)]
strands=[(7,3,3),(6,4,4),(5,5,5),(4,6,6),(3,7,8),(2,9,10),(1,11,12),(9,4,4),(8,5,5),(7,6,6)]
crownS=[(3,1,'h'),(4,1,'h'),(5,1,'h'),(6,1,'H'),(7,1,'H'),(8,1,'g'),(2,2,'h'),(3,2,'h'),(4,2,'h'),(9,2,'g'),(0,3,'h'),(1,3,'h'),(2,3,'h'),(3,3,'h')]
det=paint(side,sheen,strands,crown=crownS)
E['side']=block('side',side,None,det)
# ---- 3/4 正面 ----
qf={0:(3,8),1:(2,9),2:(1,10),3:[(0,5),(8,11)],4:[(0,5),(8,11)],5:[(-1,4),(8,12)]}
for y in range(6,16): qf[y]=[(-1,2),(10,12)]
qf[16]=[(0,1)]
det=paint(qf,[(0,0,6,13)],[(1,8,10),(1,12,13),(11,9,12)],crown=[(3,1,'h'),(4,1,'h'),(5,1,'h'),(6,1,'H'),(7,1,'H'),(8,1,'g'),(2,2,'h'),(3,2,'h'),(4,2,'h'),(6,2,'g'),(7,2,'g'),(9,2,'g')],rim=False)
det[(5,5)]='j'; det[(6,5)]='j'; det[(7,5)]='j'
E['threeQuarterFront']=block('threeQuarterFront',qf,None,det)
# ---- 正面 ----
fr={0:(3,8),1:(2,9),2:(1,10),3:[(0,4),(7,11)],4:[(0,4),(7,11)],5:[(-1,3),(8,12)]}
for y in range(6,16): fr[y]=[(-1,1),(10,12)]
fr[16]=[(0,1),(10,11)]
det=paint(fr,[(0,0,6,13)],[(2,3,4),(9,3,4)],crown=[(3,1,'h'),(4,1,'h'),(5,1,'h'),(6,1,'H'),(7,1,'H'),(8,1,'g'),(2,2,'h'),(3,2,'h'),(4,2,'h'),(5,2,'g'),(6,2,'g'),(9,2,'g')],rim=False)
det[(4,5)]='j'; det[(7,5)]='j'
E['front']=block('front',fr,None,det)
out='    // ============ 长直发 long ============\n    static func buildLong(_ book: SpriteBook) {\n'
out+=E['back']+E['threeQuarterBack']+E['side']+E['threeQuarterFront']+E['front']+'    }\n'
open(SP+'/styles/long.swift','w').write(out)
print('written')

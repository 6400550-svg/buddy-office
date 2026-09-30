#!/usr/bin/env python3
import os, random
from hp import *
SP=os.environ['SP']

SKULL={3:(3,8),4:(2,9),5:(1,10),6:(1,10),7:(1,10),8:(1,10),9:(1,10),10:(1,10),11:(2,9),12:(3,8)}
def skull(x,y):
    r=SKULL.get(y)
    return r is not None and r[0]<=x<=r[1]

def stubble(s, seed, g_density=0.20, h_density=0.05):
    rnd=random.Random(seed)
    cells=sorted(s.mask, key=lambda p:(p[1],p[0]))
    taken=set()
    def near(p, group):
        x,y=p
        return any(((x+dx,y+dy) in group) for dx in (-1,0,1) for dy in (-1,0,1) if (dx,dy)!=(0,0))
    gs=set(); hs=set()
    # 先涂满 H
    for (x,y) in cells:
        if s.boundary(x,y): continue
        s.paint[(x,y)]='H'
    # 亮点：偏左上；暗点：偏右下
    xs=[x for x,_ in cells]; ys=[y for _,y in cells]
    cx=(min(xs)+max(xs))/2; cy=(min(ys)+max(ys))/2
    for (x,y) in cells:
        if s.boundary(x,y): continue
        u=((x-cx)+(y-cy))/8.0   # 负=左上 正=右下
        pg=g_density*(1.0+0.9*u)
        ph=h_density*(1.0-1.1*u)
        r=rnd.random()
        if r<pg and not near((x,y),gs) : gs.add((x,y))
        elif r<pg+ph and not near((x,y),hs) and not near((x,y),gs): hs.add((x,y))
    for p in gs: s.paint[p]='g'
    for p in hs: s.paint[p]='h'

def hairline(s, seed, fuzz=0.35, ok=lambda p: True):
    """贴着头皮的那一圈（下面是皮肤）：不描深色边，改成 H/g 交错；再往皮肤上撒几颗发茬"""
    rnd=random.Random(seed)
    extra=[]
    for (x,y) in sorted(s.mask):
        if not s.boundary(x,y): continue
        skin_below=False
        for dx,dy in ((0,1),(1,0),(-1,0),(0,-1)):
            q=(x+dx,y+dy)
            if q not in s.mask and skull(*q): skin_below=True
        if skin_below:
            s.paint[(x,y)]='g' if (x+y)%2==0 else 'H'
            q=(x,y+1)
            if q not in s.mask and skull(*q) and rnd.random()<fuzz and ok(q): extra.append(q)
    return extra

def add_fuzz(s, pts):
    for p in pts:
        s.mask.add(p); s.paint[p]='g'
        s.mask_text+=f'\n{p[1]}@{p[0]}| #'

NOTES={'back':'背面：贴着头皮的极短发（H 为主，零星 g 做发茬、少量 h），只盖到第 9 行，发际线用 H/g 交错 + 几颗散落的发茬；耳朵和后颈露出来',
 'q34back':'3/4 背面：同背面；右侧第 10–11 列第 8–10 行留给耳朵和脸颊',
 'side':'侧面：发盖住头顶和后脑上半，耳朵 (3–4, 8–10) 露出来',
 'q34front':'3/4 正面：发际线在额头上，鬓角一小截',
 'front':'正面：平整的发际线，鬓角短，耳朵露出来'}
def build(facing, mask, seed, crescent=None, ok=lambda p: True):
    s=Spr('buzz',facing,mask,note=NOTES[facing])
    stubble(s,seed)
    ex=hairline(s,seed+7,ok=ok)
    if crescent: s.stamp(crescent)
    if facing in ('back','q34back'): s.stamp('2@4| rr',force=True)
    add_fuzz(s,ex)
    return s

sprites=[]
backok=lambda p: p[1]>=8 and 1<=p[0]<=10
frontok=lambda p: p[1]<=5
sideok=lambda p: p[1]>=8 and p[0] in (1,2)
sprites.append(build('back','''2@3| ######
3@2| ########
4@1| ##########
5@1| ##########
6@1| ##########
7@1| ##########
8@2| ########
9@3| ######''',3,'''3@3| rr
4@2| hh
5@2| h''',backok))
sprites.append(build('q34back','''2@3| ######
3@2| ########
4@1| ##########
5@1| ##########
6@1| ##########
7@1| ##########
8@2| #######
9@3| #####''',4,'''3@3| rr
4@2| hh
5@2| h''',backok))
sprites.append(build('side','''2@3| ######
3@2| ########
4@1| #########
5@1| ########
6@1| ######
7@1| #####
8@1| ##
9@1| ##''',5,'''3@3| hh
4@2| hh''',frontok))
sprites.append(build('q34front','''2@3| ######
3@2| ########
4@1| ##########
5@1| ####.##.##
6@1| ##.......#
7@1| ##''',6,'''3@3| hh
4@2| hh''',frontok))
sprites.append(build('front','''2@3| ######
3@2| ########
4@1| ##########
5@1| ###.##.###
6@1| #........#
7@1| #........#''',7,'''3@3| hh
4@2| hh''',frontok))
write_style(SP+'/styles/buzz.swift','buildBuzz','寸头 buzz',sprites)
print('buzz written')

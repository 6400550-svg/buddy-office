#!/usr/bin/env python3
import os,sys,math,random
from curly_gen import *
from curly_design import BACK,Q34BACK,SIDE,FRONT,Q34FRONT,Y0
from curly_var3 import paint3
SP=os.environ['SP']
N=int(sys.argv[1]) if len(sys.argv)>1 else 12
SEED=int(sys.argv[2]) if len(sys.argv)>2 else 7
DROP=float(sys.argv[3]) if len(sys.argv)>3 else 0.4
DS=int(sys.argv[4]) if len(sys.argv)>4 else 3
CNOTES={'back':'背面：比头大一圈（x=−2…13），顶到第 −2 行，圆滚滚的波浪形轮廓；内部用小团的高光/阴影表现卷的质感',
 'threeQuarterBack':'3/4 背面：同背面；右侧第 10–11 列第 8–10 行咬出一个缺口留给耳朵和脸颊',
 'side':'侧面：卷发包住后脑和头顶，前面留出脸的开口，额前一圈卷刘海',
 'threeQuarterFront':'3/4 正面：脸的开口偏右，近侧（左）的卷发更厚',
 'front':'正面：留出脸的开口，两侧和头顶蓬松，额前一排卷刘海'}
def block(facing,rows,seeds):
    m=parse(rows,Y0); det=paint3(m,seeds,drop=DROP,seed=DS)
    if facing in ('back','threeQuarterBack'):
        for k,v in list(det.items()):
            if v=='h' and k[1]<=1: det[k]='r'
    if facing in ('back','threeQuarterBack'):
        det[(4,-2)]='r'; det[(5,-2)]='r'
    if facing in ('front','threeQuarterFront'):
        det[(4,5)]='j'; det[(7,5)]='j'
    return f'''        // {CNOTES[facing]}
        addHairFull(book, "curly", .{facing}, mask: """
{emit_mask(rows,Y0)}
        """, detail: """
{emit_detail(det,m)}
        """)
'''
mb=parse(BACK,Y0)
seeds=voronoi_seeds(mb,N,SEED)
out='    // ============ 蓬松卷发 curly ============\n    static func buildCurly(_ book: SpriteBook) {\n'
out+=block('back',BACK,seeds)+block('threeQuarterBack',Q34BACK,seeds)+block('side',SIDE,seeds)+block('threeQuarterFront',Q34FRONT,seeds)+block('front',FRONT,seeds)
out+='    }\n'
open(SP+'/styles/curly.swift','w').write(out)
print('curly written')

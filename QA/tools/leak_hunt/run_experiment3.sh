#!/bin/bash
# 文字缓存饱和实验：演示数据加速 20 倍（计时器文字 / 标题变得飞快，缓存很快被填满），看物理占用是不是在某个值停下来
D=/private/tmp/claude-501/-Users-USER-Desktop/20c4bcc8-f611-4701-b1d3-f910aaa5248d/scratchpad
rm -f $D/leak/sat-series.txt
"$D/leak/apps/leak-B.app/Contents/MacOS/BuddyOffice" --demo --demo-mode busy6 --speed 20 --show --force-render > $D/leak/sat-B.log 2>&1 &
PB=$!
"$D/leak/apps/leak-C.app/Contents/MacOS/BuddyOffice" --demo --demo-mode crowd12 --speed 20 --show --force-render > $D/leak/sat-C.log 2>&1 &
PC=$!
for i in $(seq 0 13); do
  sleep 60
  for V in B C; do P=$([ $V = B ] && echo $PB || echo $PC)
    footprint -p $P > $D/leak/sat-fp-$V-$i.txt 2>&1
    echo "$((i+1))min $V $(grep -m1 'Footprint:' $D/leak/sat-fp-$V-$i.txt | sed 's/.*Footprint: //; s/ (.*//') rasterData=$(grep 'CG Raster Data' $D/leak/sat-fp-$V-$i.txt | awk '{print $1,$2}')" >> $D/leak/sat-series.txt
  done
done
kill $PB $PC
echo DONE >> $D/leak/sat-series.txt

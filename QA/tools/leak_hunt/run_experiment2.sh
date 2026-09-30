#!/bin/bash
# 文字缓存装满实验：更快的 replay（--stress：工具调用 0.4–3 秒一次，12 个会话）让不同的文字快速出现，看物理占用是不是停在某个值
D=/private/tmp/claude-501/-Users-USER-Desktop/20c4bcc8-f611-4701-b1d3-f910aaa5248d/scratchpad
R=~/Desktop/编程项目/Buddy办公室; cd $R || exit 1
rm -rf /private/tmp/leakexp/hF; rm -f $D/leak/fill-series.txt
python3 QA/tools/replay_soak.py --root /private/tmp/leakexp/hF --minutes 26 --sessions 12 --seed 21 --stress --report $D/leak/gen-F.json > $D/leak/gen-F.log 2>&1 &
G=$!
sleep 4
"$D/leak/apps/leak-B.app/Contents/MacOS/BuddyOffice" --data-root /private/tmp/leakexp/hF --show --force-render > $D/leak/app-F.log 2>&1 &
P=$!
for i in $(seq 1 24); do
  sleep 60
  footprint -p $P > $D/leak/fill-fp-$i.txt 2>&1
  echo "${i}min $(grep -m1 'Footprint:' $D/leak/fill-fp-$i.txt | sed 's/.*Footprint: //; s/ (.*//') rasterData=$(grep 'CG Raster Data' $D/leak/fill-fp-$i.txt | awk '{print $1,$2, $5,$6,$7}')" >> $D/leak/fill-series.txt
done
kill $P $G
echo DONE >> $D/leak/fill-series.txt

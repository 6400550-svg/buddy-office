#!/bin/bash
# 泄漏实验：B = 压力 replay（有提醒、静音）；C = 同样的数据量但没有「等批准」（没有提醒）
D=/private/tmp/claude-501/-Users-USER-Desktop/20c4bcc8-f611-4701-b1d3-f910aaa5248d/scratchpad
R=~/Desktop/编程项目/Buddy办公室
cd $R || exit 1
MIN=${1:-16}
python3 QA/tools/replay_soak.py --root /private/tmp/leakexp/hB --minutes $((MIN+2)) --sessions 8 --seed 12 --report $D/leak/gen-B.json > $D/leak/gen-B.log 2>&1 &
G1=$!
python3 QA/tools/replay_soak.py --root /private/tmp/leakexp/hC --minutes $((MIN+2)) --sessions 8 --seed 12 --wait-prob 0 --report $D/leak/gen-C.json > $D/leak/gen-C.log 2>&1 &
G2=$!
sleep 4
"$D/leak/apps/leak-B.app/Contents/MacOS/BuddyOffice" --data-root /private/tmp/leakexp/hB --show --force-render > $D/leak/app-B.log 2>&1 &
PB=$!
"$D/leak/apps/leak-C.app/Contents/MacOS/BuddyOffice" --data-root /private/tmp/leakexp/hC --show --force-render > $D/leak/app-C.log 2>&1 &
PC=$!
echo "pids B=$PB C=$PC" > $D/leak/pids.txt
sleep 150   # 预热
i=0
while [ $i -le $((MIN*60/90)) ]; do
  t=$(( 150 + i*90 ))
  for V in B C; do P=$([ $V = B ] && echo $PB || echo $PC); kill -0 $P 2>/dev/null || continue
    footprint -p $P > $D/leak/fp-$V-$t.txt 2>&1
    echo "$t $V $(grep -m1 'Footprint:' $D/leak/fp-$V-$t.txt | sed 's/.*Footprint: //')" >> $D/leak/series.txt
    if [ $i -eq 0 ] || [ $t -ge $((MIN*60)) ]; then heap $P > $D/leak/heap-$V-$t.txt 2>&1; fi
  done
  i=$((i+1)); sleep 90
done
kill $PB $PC $G1 $G2 2>/dev/null
echo DONE >> $D/leak/series.txt

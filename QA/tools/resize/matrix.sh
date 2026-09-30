#!/bin/bash
cd "$(dirname "$0")" || exit 1
: > matrix.out
run() { V=$1; TAG=$2; shift 2; ./fp_run.sh $V $TAG "$@" > /dev/null 2>&1; echo "## $V $TAG $*" >> matrix.out; grep -E "开始|做完后|RESULT" run-$V-$TAG.log | sed 's/^resize-test: //' >> matrix.out; awk -F'占用 ' '/轮做完/{split($2,a," MB"); if(a[1]+0>m)m=a[1]+0} END{print "  峰值(每轮末) " m " MB"}' run-$V-$TAG.log >> matrix.out; }
run B still1 --test-resize 300 --resize-rounds 5 --resize-still
for rep in 1 2; do for V in A B C; do run $V m$rep --test-resize 300 --resize-rounds 5; done; done
echo DONE >> matrix.out

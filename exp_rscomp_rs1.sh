#!/bin/bash

TEST="$(ls test/*.ml) $(ls test_fpat/*.ml)"

LIMIT=100
OPTION="-no-exparam -exp2 -limit $LIMIT"
FPAT_OPTION="-hccs rs1"
LOG=.rs1.log
for i in $TEST
do
echo $i
./mochi.opt $OPTION -fpat "$FPAT_OPTION" $i &> $i$LOG
echo
done

#!/bin/bash

TEST="$(echo test_esop2017/{sum_add,harmonic,fold_div,risers,various,colwheel,queen,queen_simple,soli,spir,various-e,queen-simple-e}.ml)"

if [ "$1" = "" ];then
    LIMIT=60s
else
    LIMIT=$1
fi

cat COMMIT
echo Timeout $LIMIT

#OPTION=" -only-result -ignore-conf -modular -horsat2 -base-to-int -fpat '-wp-max 2'"
OPTION="-base-to-int -abst-list-literal 1 -modular -fpat '-wp-max 2' -no-exparam -bool-init-empty -only-result -ignore-conf"
for i in $TEST
do
    echo
    printf "%0.s=" $(seq $(tput cols))
    echo
    echo
    echo $i
    echo
    echo $OPTION | xargs timeout $LIMIT ./mochi.opt $i || echo 'TIMEOUT OR ERROR'
done

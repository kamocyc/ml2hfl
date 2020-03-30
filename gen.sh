#!/bin/sh

set -eu



BENCHS=`cat "../hfl-benchmark/lists/test_safe_2019"`
for bench in $BENCHS
do
    echo $bench
    DIR="bench/`dirname $bench`"
    mkdir -p $DIR
    ./x "../hfl-benchmark/inputs/ml/$bench.ml" > "bench/$bench.in"
done

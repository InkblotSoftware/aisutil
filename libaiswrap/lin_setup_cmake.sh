#!/bin/bash
set -e

mkdir -p lin_build
cd lin_build
cmake ../libaiswrap -DCMAKE_BUILD_TYPE=Release
cd ..

#!/bin/bash
set -e

cd lin_build
cmake ../libaiswrap -DCMAKE_BUILD_TYPE=Release
cd ..

#!/bin/sh
# Rebuild bin/audioxctl.dex from src/OplusAudiox.java.
# Needs JDK 17+ and r8 (com.android.tools:r8). The class uses reflection only, so no android.jar.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
javac --release 8 -d "$OUT" src/OplusAudiox.java
if [ ! -f tools/r8.jar ]; then
    curl -sfL -o tools/r8.jar https://maven.google.com/com/android/tools/r8/8.3.37/r8-8.3.37.jar
fi
java -cp tools/r8.jar com.android.tools.r8.D8 --min-api 29 --output "$OUT" "$OUT/OplusAudiox.class"
cp "$OUT/classes.dex" bin/audioxctl.dex
echo "bin/audioxctl.dex: $(wc -c < bin/audioxctl.dex) bytes"

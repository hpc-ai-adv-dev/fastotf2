#!/bin/bash
set -e

app_dir=/workspace/apps/FastOTF2Converter
app_bin="$app_dir/target/release/FastOTF2Converter"
real_bin="${app_bin}_real"

case "${1:-}" in
  bash|sh|/bin/bash|/bin/sh)
    exec "$@"
    ;;
esac

cd "$app_dir"

if [ -x "$real_bin" ]; then
  exec "$real_bin" "$@"
fi

if [ -x "$app_bin" ]; then
  exec "$app_bin" "$@"
fi

echo "error: could not find an executable FastOTF2Converter binary in $app_dir/target/release" >&2
exit 1

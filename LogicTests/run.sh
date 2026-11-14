#!/bin/zsh
# Runs the logic tests. The build folder lives outside ~/Desktop: Finder metadata
# there breaks codesign ("detritus not allowed").
cd "$(dirname "$0")" || exit 1
exec swift test --scratch-path "$HOME/Library/Developer/Xcode/DerivedData/Atoll-logic-tests" "$@"

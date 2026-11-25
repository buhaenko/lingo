#!/bin/zsh
# Unit + integration tests (real keyboard-layout switching). Non-zero exit if anything fails.
set -e
cd "${0:A:h}/.."
bin=$(mktemp -d)/lingo-tests
swiftc -D TESTING Sources/*.swift Tests/*.swift -o "$bin"
"$bin"

#!/usr/bin/env bash
set -eu
. "$(dirname "$0")/../code-reviewer-fixes-on-top/fixture.sh"
git reset -q HEAD~1

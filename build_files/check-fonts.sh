#!/usr/bin/bash
# Check resolved faces, not just whether the font files were installed.
set -euo pipefail

check_font() {
	local pattern=$1 expected=$2 actual
	actual=$(fc-match --format '%{family}' "$pattern")
	if [ "$actual" != "$expected" ]; then
		printf 'font mismatch for %s: expected %s, got %s\n' "$pattern" "$expected" "$actual" >&2
		exit 1
	fi
}

check_font 'sans-serif' Alexandria
check_font 'sans-serif:lang=ar' Alexandria
check_font 'sans-serif:lang=ar-eg' Alexandria
check_font 'sans-serif:lang=ar:weight=bold' Alexandria
check_font 'system\-ui:lang=ar' Alexandria
check_font 'sans-serif:lang=en' Alexandria
check_font 'system\-ui:lang=en' Alexandria
check_font 'monospace:lang=en' 'JetBrains Mono'
check_font 'Inter Variable:lang=en' 'Inter Variable'
check_font 'sans-serif:charset=0627' Alexandria
check_font 'Inter:charset=0627' Alexandria
check_font 'monospace:charset=0627' Alexandria
check_font 'Alexandria:lang=ar' Alexandria
check_font 'Cairo:lang=ar' Cairo

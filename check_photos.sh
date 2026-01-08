#!/bin/bash
USED_IMAGES=$(grep -oE "photos/P_[0-9_]+\.jpg" LISTING.md | sed 's|photos/||' | sort -u)
ALL_IMAGES=$(ls photos/ | grep -E "^P_[0-9_]+\.jpg$" | sort)
comm -23 <(echo "$ALL_IMAGES") <(echo "$USED_IMAGES")
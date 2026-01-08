#!/bin/bash
# Optimize all images in photos/ that are larger than 1920x1080 or uncompressed

for img in photos/*.jpg; do
  [ -e "$img" ] || continue

  # Get dimensions
  DIM=$(identify -format "%w %h" "$img")
  WIDTH=$(echo $DIM | cut -d' ' -f1)
  HEIGHT=$(echo $DIM | cut -d' ' -f2)

  # Check if resize is needed or if we should just compress
  # The '>' flag in convert already handles "only if larger", 
  # but we check here to be explicit as requested.
  if [ "$WIDTH" -gt 1920 ] || [ "$HEIGHT" -gt 1080 ]; then
    echo "Optimizing $img ($WIDTH"x"$HEIGHT)..."
    convert "$img" -resize "1920x1080>" pnm:- | /usr/bin/mozjpeg -quality 75 > "${img}.tmp" && mv "${img}.tmp" "$img"
  fi
done

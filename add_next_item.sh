#!/bin/bash
PHOTO=$(./check_photos.sh | head -n 1)

if [ -z "$PHOTO" ]; then
  echo "No missing photos found."
  exit 0
fi

FULL_PATH="photos/$PHOTO"
echo "Optimizing $FULL_PATH..."

# Optimize: Resize if larger than 1920x1080 and compress with mozjpeg
# We use convert to resize (if needed) and output to ppm, then pipe to mozjpeg
convert "$FULL_PATH" -resize "1920x1080>" pnm:- | /usr/bin/mozjpeg -quality 75 > "${FULL_PATH}.tmp" && mv "${FULL_PATH}.tmp" "$FULL_PATH"

echo "Processing $FULL_PATH with Gemini..."

# Execute gemini interactively with the generated prompt in YOLO mode
gemini -m gemini-3-flash-preview -y -i "$(sed "s|{{PHOTO}}|$FULL_PATH|g" PROMPT_ADD_ITEM.md)" "@LISTING.md" "@facturas/itens_compilados.csv" "@$FULL_PATH"
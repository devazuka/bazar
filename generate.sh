#!/bin/bash

# Regenerate index.html from LISTING.md using pandoc
pandoc LISTING.md -o index.html -c styles.css --standalone --metadata title="Bazar Alan - Itens e Memórias"

echo "index.html regenerated successfully."

#!/bin/bash
set -euo pipefail

# Regenerate index.html from LISTING.md using pandoc
pandoc LISTING.md -o index.html -c styles.css --standalone --metadata title="Bazar Alan - Itens e Memórias"

# Insert category index after the header and first paragraph.
tmp_fragment="$(mktemp)"
tmp_index="$(mktemp)"
tmp_map="$(mktemp)"
cleanup() {
  rm -f "$tmp_fragment" "$tmp_index" "$tmp_map"
}
trap cleanup EXIT

# Build a title -> id/price map from the generated HTML.
awk '
  match($0, /<h3 id="([^"]+)">([^<]+)<\/h3>/, m) { cur_title=m[2]; cur_id=m[1]; next }
  /À Venda por/ {
    if (cur_title != "" && cur_id != "") {
      price=""
      if (match($0, /À Venda por:<\/strong>[[:space:]]*<strong>([^<]+)<\/strong>/, p)) {
        price=p[1]
      }
      printf "%s\t%s\t%s\n", cur_title, cur_id, price
      cur_title=""; cur_id=""
    }
  }
' index.html > "$tmp_map"

normalize() {
  printf '%s' "$1" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/ /g; s/^ +| +$//g'
}

titles=()
ids=()
prices=()
norm_titles=()
while IFS=$'\t' read -r title id price; do
  titles+=("$title")
  ids+=("$id")
  prices+=("$price")
  norm_titles+=("$(normalize "$title")")
done < "$tmp_map"

unmatched=()
in_category=0
echo "<section class=\"index\">" >> "$tmp_fragment"
echo "<h2>Index</h2>" >> "$tmp_fragment"
while IFS= read -r line; do
  if [[ "$line" =~ ^##\  ]]; then
    if (( in_category )); then
      echo "</ul>" >> "$tmp_fragment"
    fi
    category="${line#\#\# }"
    echo "<h3>${category}</h3>" >> "$tmp_fragment"
    echo "<ul>" >> "$tmp_fragment"
    in_category=1
    continue
  fi

  if [[ "$line" =~ ^-\  ]]; then
    item="${line#- }"
    item="${item%% (tags:*}"
    norm_item="$(normalize "$item")"
    best_idx=-1
    best_score=0
    for i in "${!titles[@]}"; do
      norm_title="${norm_titles[$i]}"
      score=0
      if [[ "$norm_title" == *"$norm_item"* ]] || [[ "$norm_item" == *"$norm_title"* ]]; then
        score=${#norm_item}
      else
        for word in $norm_item; do
          if (( ${#word} > 3 )) && [[ "$norm_title" == *"$word"* ]]; then
            score=$((score + ${#word}))
          fi
        done
      fi
      if (( score > best_score )); then
        best_score=$score
        best_idx=$i
      fi
    done

    if (( best_idx >= 0 )); then
      id="${ids[$best_idx]}"
      price="${prices[$best_idx]}"
      if [[ -n "$price" ]]; then
        echo "<li><a href=\"#${id}\">${item}</a> — ${price}</li>" >> "$tmp_fragment"
      else
        echo "<li><a href=\"#${id}\">${item}</a></li>" >> "$tmp_fragment"
      fi
    else
      unmatched+=("$item")
    fi
  fi
done < LISTING_CATEGORIAS.md

if (( in_category )); then
  echo "</ul>" >> "$tmp_fragment"
fi
echo "</section>" >> "$tmp_fragment"

if (( ${#unmatched[@]} > 0 )); then
  printf "Unmatched items in LISTING_CATEGORIAS.md:\n" >&2
  printf " - %s\n" "${unmatched[@]}" >&2
  exit 1
fi

awk '
  NR==FNR { frag = frag $0 ORS; next }
  {
    print
    if (!inserted && seen_header && /<\/p>/) {
      printf "%s", frag
      inserted = 1
    }
    if (/<\/header>/) {
      seen_header = 1
    }
  }
  END {
    if (!seen_header) {
      print "Header not found in index.html" > "/dev/stderr"
      exit 1
    }
    if (!inserted) {
      print "First paragraph not found in index.html" > "/dev/stderr"
      exit 1
    }
  }
' "$tmp_fragment" index.html > "$tmp_index"
mv "$tmp_index" index.html

echo "index.html regenerated successfully."

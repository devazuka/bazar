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

sold_titles=()
sold_norm_titles=()
while IFS= read -r sold_title; do
  [[ -z "$sold_title" ]] && continue
  sold_titles+=("$sold_title")
  sold_norm_titles+=("$(normalize "$sold_title")")
done < <(
  awk '
    BEGIN { in_comment=0 }
    {
      line=$0
      if (match(line, /<!--/)) { in_comment=1 }
      if (in_comment && match(line, /^### /)) {
        title=line
        sub(/^### /, "", title)
        print title
      }
      if (match(line, /-->/)) { in_comment=0 }
    }
  ' LISTING.md
)

titles=()
ids=()
prices=()
norm_titles=()
declare -A matched_ids
while IFS=$'\t' read -r title id price; do
  titles+=("$title")
  ids+=("$id")
  prices+=("$price")
  norm_titles+=("$(normalize "$title")")
done < "$tmp_map"

unmatched=()
in_category=0
echo "<section class=\"index\">" >> "$tmp_fragment"
echo "<h2 id=\"index\">Index</h2>" >> "$tmp_fragment"
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
      matched_ids["$id"]=1
      if [[ -n "$price" ]]; then
        echo "<li><a href=\"#${id}\">${item}</a> — ${price}</li>" >> "$tmp_fragment"
      else
        echo "<li><a href=\"#${id}\">${item}</a></li>" >> "$tmp_fragment"
      fi
    else
      is_sold=0
      for sold_norm in "${sold_norm_titles[@]}"; do
        if [[ "$sold_norm" == *"$norm_item"* ]] || [[ "$norm_item" == *"$sold_norm"* ]]; then
          is_sold=1
          break
        fi
      done
      if (( is_sold )); then
        continue
      fi
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

missing=()
for i in "${!titles[@]}"; do
  title="${titles[$i]}"
  id="${ids[$i]}"
  norm_title="$(normalize "$title")"
  if [[ "$norm_title" == "e muito mais" ]]; then
    continue
  fi
  for sold_norm in "${sold_norm_titles[@]}"; do
    if [[ "$sold_norm" == "$norm_title" ]]; then
      continue 2
    fi
  done
  if [[ -z "${matched_ids[$id]+x}" ]]; then
    missing+=("$title")
  fi
done

awk '
  NR==FNR { frag = frag $0 ORS; next }
  {
    print
    if (!inserted && /<\/header>/) {
      printf "%s", frag
      inserted = 1
      seen_header = 1
    } else if (/<\/header>/) {
      seen_header = 1
    }
  }
  END {
    if (!seen_header) {
      print "Header not found in index.html" > "/dev/stderr"
      exit 1
    }
    if (!inserted) {
      print "Index insertion point not found in index.html" > "/dev/stderr"
      exit 1
    }
  }
' "$tmp_fragment" index.html > "$tmp_index"
mv "$tmp_index" index.html

# Add back-to-index links inside item headers.
tmp_top="$(mktemp)"
awk '
  {
    line=$0
    if (match(line, /<h3 id="[^"]+">/)) {
      sub(/<h3 id="[^"]+">/, "&<a class=\"back-to-index\" href=\"#index\">⬆️</a> ", line)
    }
    print line
  }
' index.html > "$tmp_top"
mv "$tmp_top" index.html

echo "index.html regenerated successfully."

if (( ${#missing[@]} > 0 )); then
  printf "Items in LISTING.md missing from LISTING_CATEGORIAS.md:\n" >&2
  printf " - %s\n" "${missing[@]}" >&2
  exit 1
fi

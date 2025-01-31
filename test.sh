#! /usr/bin/env bash
set -eu

. ./utils.sh

apparel_colors="SOL,#fccf6e
ARÇONS,#fff766
ANNEAUX,#df5e9d
BARRES PARALLÈLES,#a2debe
BARRE FIXE,#5fbfdc"

extract_page() {
    local PAGE="$1"

    local FULL_EPS="build/full.eps"
    pdftocairo -f "$PAGE" -l "$PAGE" -eps brochure_GAM.pdf "$FULL_EPS"
    echo "$FULL_EPS"
}

extract_text() {
    awk '/^BT$/ { p=1 ;} /^ET$/ { p=0 ;} p' < build/full.eps > build/text.txt

    sed -e 's/\\$//g' < build/text.txt | \
        tr -d '\n' | \
        sed -Ee 's/\)[0-9]+\(//g' \
            -e 's/\\205/…/g' \
            -e 's/\\222/'"'"'/g' \
            -e 's/\\22[4|3]/"/g' \
            -e 's/\\253/«/g' \
            -e 's/\\260/°/g' \
            -e 's/\\273/»/g' \
            -e 's/\\275/1\/2/g' \
            -e 's/\\307/Ç/g' \
            -e 's/\\310/È/g' \
            -e 's/\\311/É/g' \
            -e 's/\\340/à/g' \
            -e 's/\\342/â/g' \
            -e 's/\\347/ç/g' \
            -e 's/\\350/è/g' \
            -e 's/\\351/é/g' \
            -e 's/\\352/ê/g' \
            -e 's/\\356/î/g' \
            -e 's/\\364/ô/g' \
            -e 's/\\366/ö/g' | \
        sed -Ee 's/\)Tj/_/g' -e 's/\)\]TJ/__/g' | \
        sed -Ee 's/\(([^]+)_/\n{{ \1 }}\n/g' \
            -e 's/\[\(([^]+)__/\n{{ \1 }}\n/g' | \
        grep -e '^{{.*}}$' | \
        sed -Ee 's/^\{\{ *(.*) +\}\}$/\1/' \
            -e 's/\\(\(|\))/\1/g' \
        > build/cleaned.txt

    apparels="$(echo "$apparel_colors" | cut -d, -f1 | paste -sd '|' -)"
    agres="$(sed -n -Ee 's/^('"$apparels"').*$/\1/p' < build/cleaned.txt)"
    group="$(grep -A1 "$agres" < build/cleaned.txt | tail -n1 | sed -Ee 's/"/\\"/g' -e 's/ [0-9]+$//')"

    grep -A5 -Ee '^[0-9]+ *- *' < build/cleaned.txt | \
        sed -Ee '/^--$/d' | \
        tr '\n' ' ' | \
        sed -Ee 's/ ?([0-9]+ *- *)/\n\1 /g' \
            -e 's/( ?[0-9]+,[0-9]+ ?)+//' | \
        sed -Ee '/^$/d' -e 's/  +/ /g' | \
        sort -n > build/description.txt

    grep -Ee '^[0-9],[0-9]$' < build/cleaned.txt | \
        sed -Ee 's/,/./g' | \
        sort -g > build/value.txt

    local ELEMENTS_LIST="build/elements.jsonl"
    paste --delimiters '' build/description.txt build/value.txt | \
        sed -Ee 's/"/\\"/g' | \
        sed -Ee 's/^([0-9]+) - ([^]+)(.*)$/{"agres": "'"$agres"'", "group": "'"$group"'", "id": \1, "description": "\2", "value": \3}/' > "$ELEMENTS_LIST"
    echo "$ELEMENTS_LIST"
}


extract_images() {
    local FULL_EPS="$1"
    local ELEMENTS_LIST="$2"

    # Extract the images
    sed '/^BT$/,/^ET$/ d' < "$FULL_EPS" > build/image.eps
    inkscape --actions 'mcepl.ungroup-deep.noprefs:1;select-all:all;path-split:1;com.klowner.filter.apply-transform.noprefs:1;' \
        -o build/applied.svg \
        -n 1 \
        build/image.eps
    inkscape --vacuum-defs -o build/final.svg build/applied.svg

    # Get bounding boxes of all objects
    inkscape --query-all build/final.svg > build/bboxes.txt

    get_page_grid grid.txt build/bboxes.txt > build/page_grid.txt

    # Iterate over the elements and extract images
    while IFS="" read -r p || [ -n "$p" ]
    do
        extract_image "$p" build/bboxes.txt build/page_grid.txt build/final.svg
    done < "$ELEMENTS_LIST"
}

extract_image() {
    local ELEMENT="$1"
    local BBOXES="$2"
    local CELL_FILE="$3"
    local IMAGE_SVG="$4"

    e_id=$(echo "$ELEMENT" | jq -r '.id')
    agres=$(echo "$ELEMENT" | jq -r '.agres')
    echo "$agres - $e_id"
    mkdir -p "out/sym/$agres/" "out/drawings/$agres/"
    cell_ix=$(( (e_id - 1) % 12 + 1 ))
    cell_bbox="$(sed "$cell_ix"'q;d' < "$CELL_FILE")"

    cell_ids="$(\
        contained_bboxes "$cell_bbox" < "$BBOXES" | \
        cut -d, -f1 | \
        tr '\n' ',' | \
        sed 's/,$//' \
    )"

    crop_svg "$cell_ids" "$IMAGE_SVG" build/cell.svg

    inkscape --query-all build/cell.svg > build/cell_bbox.txt
    apparel_color="$(echo "$apparel_colors" | grep "$agres" | cut -d, -f2)"
    sym_container_id=$(grep -A2 -Ee 'style=.*fill:'"$apparel_color" < build/cell.svg | grep 'id=' | sed -Ee 's/.*id="([^"]+)".*/\1/')
    sym_container_bbox=$(grep "$sym_container_id" < build/cell_bbox.txt | awk -F, '{print $2 "," $3 "," $2 + $4 "," $3 + $5}')
    sym_ids="$(contained_bboxes "$sym_container_bbox" < build/cell_bbox.txt | cut -d, -f1 | grep -v "$sym_container_id"| tr '\n' ',' | sed 's/,$//')"
    crop_svg "$sym_ids" build/cell.svg "out/sym/$agres/$e_id.svg"

    value_ids="$(intersecting_bboxes "$sym_container_bbox" < build/cell_bbox.txt | cut -d, -f1 | grep -v 'svg1' | tr '\n' ',' | sed 's/,$//')"
    crop_svg "$value_ids" build/cell.svg "out/drawings/$agres/$e_id.svg" -invert=true
}


#for PAGE in $(seq 28 92); do
for PAGE in $(seq 80 92); do
    # set -x
    # extract_image '{"agres": "ANNEAUX", "group": "établissement à lappui en élan ou en force", "id": 10, "description": "Bascule dorsale bras échis à lappui", "value": 0.4}' \
    #     build/bboxes.txt \
    #     build/page_grid.txt \
    #     build/final.svg
    # break
    echo "PAGE $PAGE"
    FULL_EPS=$(extract_page "$PAGE")
    # ELEMENTS_LIST=build/elements.jsonl
    ELEMENTS_LIST=$(extract_text)
    cp "$ELEMENTS_LIST" "$(printf 'out/%03d.jsonl' "$PAGE")"
    extract_images "$FULL_EPS" "$ELEMENTS_LIST"
done

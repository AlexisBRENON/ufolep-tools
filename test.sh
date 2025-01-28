#! /usr/bin/env bash
set -eux

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
            -e 's/\\222/'"'"'/g' \
            -e 's/\\22[4|3]/"/g' \
            -e 's/\\340/à/g' \
            -e 's/\\351/é/g' | \
        sed -Ee 's/\(([^)]+)\)Tj/\n{{ \1 }}\n/g' \
            -e 's/\[\(([^)]+)\)\]TJ/\n{{ \1 }}\n/g' | \
        grep -e '^{{.*}}$' | \
        sed -Ee 's/^\{\{ *(.*) +\}\}$/\1/' \
        > build/cleaned.txt

    agres="$(sed -n -Ee 's/^(SOL|ARÇONS|ANNEAUX|BARRES PARALLELES|BARRE FIXE).*$/\1/p' < build/cleaned.txt)"
    group="$(grep -A1 "$agres" < build/cleaned.txt | tail -n1 | sed -Ee 's/"/\\"/g' -e 's/ [0-9]+$//')"

    grep -A5 -Ee '^[0-9]+ - ' < build/cleaned.txt | \
        tr '\n' ' ' | \
        sed -Ee 's/ ?([0-9]+ - )/\n\1/g' \
            -e 's/( ?[0-9]+,[0-9]+ ?)+//' | \
        sed '/^$/d' | \
        sort > build/description.txt

    grep -Ee '^[0-9],[0-9]$' < build/cleaned.txt | \
        sed -Ee 's/,/./g' | \
        sort -g > build/value.txt

    local ELEMENTS_LIST="build/elements.jsonl"
    paste --delimiters '' build/description.txt build/value.txt | \
        sed -Ee 's/"/\\"/g' | \
        sed -Ee 's/^([0-9]+) - ([^]+)(.*)$/{"agres": "'"$agres"'", "group": "'"$group"'", "id": \1, "description": "\2", "value": \3}/' > "$ELEMENTS_LIST"
    echo "$ELEMENTS_LIST"
}

identify_grid() {
    local IMAGE_SVG="$1"

    inkscape --query-all "$IMAGE_SVG" > build/bboxes.txt
    min_x="$(grep 'svg1,' < build/bboxes.txt | cut -d, -f2)"
    min_x="$( \
        grep -v -Ee '[^,]*,'"${min_x}"',.*' < build/bboxes.txt | \
        sort -n -t, -k2 | \
        head -n1 | \
        cut -d, -f2 \
    )"
    grep -Ee '[^,]*,'"${min_x}"',.*' < build/bboxes.txt > build/v_separators.txt
    max_x="$(head -n1 < build/v_separators.txt | awk -F, '{print $2 + $4}')"

    min_y="$(grep 'svg1,' < build/bboxes.txt | cut -d, -f3)"
    min_y="$( \
        grep -v -Ee '[^,]*,[^,]*,'"${min_y}"',.*' < build/bboxes.txt | \
        sort -n -t, -k3 | \
        head -n1 | \
        cut -d, -f3 \
    )"
    grep -Ee '[^,]*,[^,]*,'"${min_y}"',.*' < build/bboxes.txt > build/h_separators.txt
    max_y="$(head -n1 < build/h_separators.txt | awk -F, '{print $3 + $5}')"

    latest_v_sep="$(tail -n1 < build/v_separators.txt | awk -F, '{print "virtual," $2 "," '"$max_y"' "," $4 "," $5}')"
    echo "$latest_v_sep" >> build/v_separators.txt
    latest_h_sep="$(tail -n1 < build/h_separators.txt | awk -F, '{print "virtual," '"$max_x"' "," $3 "," $4 "," $5}')"
    echo "$latest_h_sep" >> build/h_separators.txt


    CELL_FILE="build/cells.txt"
    rm -f "$CELL_FILE"
    y0="$min_y"
    while IFS="" read -r v_sep || [ -n "$v_sep" ]
    do
        x0="$min_x"
        while IFS="" read -r h_sep || [ -n "$h_sep" ]
        do
            echo "$x0,$y0,$(echo "$h_sep" | cut -d, -f2),$(echo "$v_sep" | cut -d, -f3)" >> "$CELL_FILE"
            sep_width="$(echo "$h_sep" | cut -d, -f4)"
            x0="$(echo "$h_sep" | cut -d, -f2)"
            x0="$(echo "$x0" "$sep_width" | awk '{print $1 + $2}')"
        done < build/h_separators.txt
        sep_height="$(echo "$v_sep" | cut -d, -f5)"
        y0="$(echo "$v_sep" | cut -d, -f3)"
        y0="$(echo "$y0" "$sep_height" | awk '{print $1 + $2}')"
    done < build/v_separators.txt

    echo "$CELL_FILE"
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

    cell_file="$(identify_grid build/final.svg)"

    # Iterate over the elements and extract images
    while IFS="" read -r p || [ -n "$p" ]
    do
        extract_image "$p" "$cell_file" build/final.svg
    done < "$ELEMENTS_LIST"
}

extract_image() {
    local ELEMENT="$1"
    local CELL_FILE="$2"
    local IMAGE_SVG="$3"

    e_id=$(echo "$ELEMENT" | jq -r '.id')
    cell_ix=$(( e_id % 12 ))
    cell_bbox="$(sed "$cell_ix"'q;d' < "$CELL_FILE")"

    # inkscape --actions 'export-area:'"$area"';export-type:svg;export-filename:build/cell.svg;export-do:;' "$IMAGE_SVG"
}


for PAGE in $(seq 30 30); do
    FULL_EPS=build/full.eps # FULL_EPS=$(extract_page "$PAGE")
    ELEMENTS_LIST=build/elements.jsonl # ELEMENTS_LIST=$(extract_text)
    extract_image '{"agres": "SOL", "group": "appui, maintien ou force", "id": 35, "description": "De l'\''appui facial horizontal jambes serrées tenu 2\" s'\''élever à l'\''ATR", "value": 0.6}' build/cells.txt build/final.svg
    # extract_images "$FULL_EPS" "$ELEMENTS_LIST"
done

#! /usr/bin/env bash
set -eu

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
            -e 's/\\260/°/g' \
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
    local BBOXES="$1"

    min_x="$(grep 'svg1,' < "$BBOXES" | cut -d, -f2)"
    min_x="$( \
        grep -v -Ee '[^,]*,'"${min_x}"',.*' < "$BBOXES" | \
        sort -n -t, -k2 | \
        head -n1 | \
        cut -d, -f2 \
    )"
    grep -Ee '[^,]*,'"${min_x}"',.*' < "$BBOXES" > build/v_separators.txt
    max_x="$(head -n1 < build/v_separators.txt | awk -F, '{print $2 + $4}')"

    min_y="$(grep 'svg1,' < "$BBOXES" | cut -d, -f3)"
    min_y="$( \
        grep -v -Ee '[^,]*,[^,]*,'"${min_y}"',.*' < "$BBOXES" | \
        sort -n -t, -k3 | \
        head -n1 | \
        cut -d, -f3 \
    )"
    grep -Ee '[^,]*,[^,]*,'"${min_y}"',.*' < "$BBOXES" > build/h_separators.txt
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
        sep_height="$(echo "$v_sep" | cut -d, -f5)"
        y1="$(echo "$v_sep" | awk -F, -v sep_height="$sep_height" '{print $3 + sep_height}')"
        x0="$min_x"
        while IFS="" read -r h_sep || [ -n "$h_sep" ]
        do
            sep_width="$(echo "$h_sep" | cut -d, -f4)"
            x1="$(echo "$h_sep" | awk -F, -v sep_width="$sep_width" '{print $2 + sep_width}')"

            echo "$x0,$y0,$x1,$y1" >> "$CELL_FILE"
            x0="$(echo "$h_sep" | cut -d, -f2)"
        done < build/h_separators.txt
        y0="$(echo "$v_sep" | cut -d, -f3)"
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

    inkscape --query-all build/final.svg > build/bboxes.txt
    cell_file="$(identify_grid build/bboxes.txt)"

    # Iterate over the elements and extract images
    while IFS="" read -r p || [ -n "$p" ]
    do
        extract_image "$p" build/bboxes.txt "$cell_file" build/final.svg
    done < "$ELEMENTS_LIST"
}

contained_bboxes () {
    container="$1"
    awk -F, -v container="$container" '
BEGIN {
    split(container, coords, ",");
    x0 = coords[1];
    y0 = coords[2];
    x1 = coords[3];
    y1 = coords[4];
}
{
    x = $2;
    y = $3;
    w = $4;
    h = $5;
    if (x0 <= x && y0 <= y && (x + w) <= x1 && (y + h) <= y1) {
        print $0;
    }
}'
}

intersecting_bboxes () {
    box1="$1"
    awk -F, -v box1="$box1" '
BEGIN {
    split(box1, coords, ",");
    b0_x0 = coords[1];
    b0_y0 = coords[2];
    b0_x1 = coords[3];
    b0_y1 = coords[4];
}
{
    x = $2;
    y = $3;
    w = $4;
    h = $5;
    if (! (x > b0_x1 || (x + w) < b0_x0 || y > b0_y1 || (y + h) < b0_y0 )) {
        print $0;
    }
}'
}

crop_svg () {
    local ids="$1"
    local IMAGE_SVG="$2"
    local output="$3"
    shift 3

    actions="select-by-id:$ids;"
    if [ "${1:-""}" = "-invert=true" ]; then
        actions="${actions}select-invert:;"
        shift
    fi
    inkscape --actions "${actions}\
select-invert:;
delete-selection:;\
page-fit-to-selection:;\
export-filename:$output;\
export-type:svg;\
export-do;" "$IMAGE_SVG"
}

extract_image() {
    local ELEMENT="$1"
    local BBOXES="$2"
    local CELL_FILE="$3"
    local IMAGE_SVG="$4"

    e_id=$(echo "$ELEMENT" | jq -r '.id')
    agres=$(echo "$ELEMENT" | jq -r '.agres')
    mkdir -p "out/sym/$agres/" "out/drawings/$agres/"
    cell_ix=$(( e_id % 12 ))
    cell_bbox="$(sed "$cell_ix"'q;d' < "$CELL_FILE")"

    cell_ids="$(\
        contained_bboxes "$cell_bbox" < "$BBOXES" | \
        cut -d, -f1 | \
        tr '\n' ',' | \
        sed 's/,$//' \
    )"

    crop_svg "$cell_ids" "$IMAGE_SVG" build/cell.svg

    inkscape --query-all build/cell.svg > build/cell_bbox.txt
    sym_container_id=$(grep -A2 -Ee 'style=.*fill:#fccf6e' < build/cell.svg | grep 'id=' | sed -Ee 's/.*id="([^"]+)".*/\1/')
    sym_container_bbox=$(grep "$sym_container_id" < build/cell_bbox.txt | awk -F, '{print $2 "," $3 "," $2 + $4 "," $3 + $5}')
    sym_ids="$(contained_bboxes "$sym_container_bbox" < build/cell_bbox.txt | cut -d, -f1 | grep -v "$sym_container_id"| tr '\n' ',' | sed 's/,$//')"
    crop_svg "$sym_ids" build/cell.svg "out/sym/$agres/$e_id.svg"

    value_ids="$(intersecting_bboxes "$sym_container_bbox" < build/cell_bbox.txt | cut -d, -f1 | grep -v 'svg1' | tr '\n' ',' | sed 's/,$//')"
    crop_svg "$value_ids" build/cell.svg "out/drawings/$agres/$e_id.svg" -invert=true
}


for PAGE in $(seq 29 29); do
    FULL_EPS=$(extract_page "$PAGE")
    ELEMENTS_LIST=$(extract_text)
    extract_images "$FULL_EPS" "$ELEMENTS_LIST"
done

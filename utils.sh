#! /usr/bin/env bash
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

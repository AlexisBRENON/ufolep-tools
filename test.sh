#! /usr/bin/env bash
set -eux

for PAGE in $(seq 30 30); do
    # Extract a page
    pdftocairo -f "$PAGE" -l "$PAGE" -eps brochure_GAM.pdf build/full.eps

    # Extract the images
    sed '/^BT$/,/^ET$/ d' < build/full.eps > build/image.eps
    inkscape --actions 'mcepl.ungroup-deep.noprefs:1;select-all:all;path-split:1;com.klowner.filter.apply-transform.noprefs:1;' \
        -o build/applied.svg \
        -n 1 \
        build/image.eps
    inkscape --vacuum-defs -o build/final.svg build/applied.svg

    # Extract the texts
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

    grep -A5 -Ee '^[0-9]+ - ' < build/cleaned.txt | \
        tr '\n' ' ' | \
        sed -Ee 's/ ?([0-9]+ - )/\n\1/g' \
            -e 's/( ?[0-9]+,[0-9]+ ?)+//' | \
        sed '/^$/d' | \
        sort > build/description.txt

    grep -Ee '^[0-9],[0-9]$' < build/cleaned.txt | \
        sed -Ee 's/,/./g' | \
        sort -g > build/value.txt
done

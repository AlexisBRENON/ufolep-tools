---
---

document.addEventListener('DOMContentLoaded', function () {
    // filter functions
    var filterFns = {
        all: function (itemElem) {
            return true;
        },
        {% for item in site.data.db['levels'] %}
        {{ item[0] }}: function (itemElem) {
            if (itemElem.attributes['data-ufolep-level'] && (itemElem.attributes['data-ufolep-level'].value == "{{ item[0] }}")) {
                return true;
            }
            var value = parseFloat(itemElem.attributes['data-ufolep-value'] && itemElem.attributes['data-ufolep-value'].value);
            return {{ item[1].value_range[0] }} <= value && value <= {{ item[1].value_range[1] }};
        },
        {% endfor %}
    };

collapseElementList = [...document.querySelectorAll('*[data-ufolep-level], *[data-ufolep-value]')].map(collapseEl => new bootstrap.Collapse(collapseEl, { toggle: false }));


    // bind filter button click
    var filtersElem = document.querySelectorAll('#level-button-group > input');
    filtersElem.forEach(function (btn) {
        btn.addEventListener('click', function (event) {
            var filterValue = event.target.getAttribute('data-filter');
            // use matching filter function
            filterValue = filterFns[filterValue];
            collapseElementList.forEach(function (collapse) {
                if (filterValue(collapse._element)) {
                    collapse.show()
                } else {
                    collapse.hide()
                }
            });
        });
    });
});

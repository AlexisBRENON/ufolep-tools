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
            if (itemElem.getAttribute('data-ufolep-level') == "{{ item[0] }}") {
                return true;
            }
            var value = parseFloat(itemElem.getAttribute('data-ufolep-value'));
            return {{ item[1].value_range[0] }} <= value && value <= {{ item[1].value_range[1] }};
        },
        {% endfor %}
    };

collapseElementList = [...document.querySelectorAll('*[data-ufolep-level], *[data-ufolep-value]')].map(collapseEl => new bootstrap.Collapse(collapseEl, { toggle: false }));


    // bind filter button click
    var filtersElem = document.querySelectorAll('a[data-filter]');
    filtersElem.forEach(function (btn) {
        btn.addEventListener('click', function (event) {
            event.target.closest("article").classList.toggle("d-print-none");
            var activeFilters = Array.from(filtersElem).filter(elem => !! (elem.getAttribute("aria-pressed") == "true") ).map(elem => filterFns[elem.getAttribute('data-filter')])
            collapseElementList.forEach(function (collapse) {
                if (activeFilters.some(fn => fn(collapse._element))) {
                    collapse.show()
                } else {
                    collapse.hide()
                }
            });
        });
    });
});

document.addEventListener('DOMContentLoaded', function () {
    // filter functions
    var filterFns = {
        all: function (itemElem) {
            return true;
        },
        n6: function (itemElem) {
            value = parseFloat(itemElem.attributes['data-ufolep-value'] && itemElem.attributes['data-ufolep-value'].value)
            return value < 0.4
        },
        n5: function (itemElem) {
            value = parseFloat(itemElem.attributes['data-ufolep-value'] && itemElem.attributes['data-ufolep-value'].value)
            return value > 0.1 && value < 0.5
        }
    };

    collapseElementList = [...document.querySelectorAll('.element[data-ufolep-value')].map(collapseEl => new bootstrap.Collapse(collapseEl, { toggle: false }));


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

document.addEventListener('DOMContentLoaded', function () {

    // Create the query list.
    const mediaQueryList = window.matchMedia("print");

    // Define a callback function for the event listener.
    function printRequest(mql) {
        document.querySelectorAll('[data-colcade]').forEach(function (elem) {
            var attr = elem.attributes['data-colcade'].value;
            var attrParts = attr.split(',');
            var options = {};
            attrParts.forEach(function (part) {
                var pair = part.split(':');
                var key = pair[0].trim();
                var value = pair[1].trim();
                options[key] = value;
            });
            var colc = new Colcade(elem, options);
            colc.onDebouncedResize()
        });
    }

    // Run the orientation change handler once.
    printRequest(mediaQueryList);

    // Add the callback function as a listener to the query list.
    mediaQueryList.addEventListener("change", printRequest);
});

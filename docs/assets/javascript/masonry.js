document.addEventListener('DOMContentLoaded', function () {

    const containers = document.querySelectorAll('.apparel-groups');
    console.log(containers);
    containers.forEach((elem) => {
        var msnry = new Masonry(elem, {
            percentPosition: true
        });
    })

    document.querySelectorAll('#apparel-tab > *, #apparel-pill > *').forEach(function (elem) {
        elem.addEventListener('shown.bs.tab', function () {
            containers.forEach((elem) => {
                var msnry = new Masonry(elem, {
                    percentPosition: true
                });
            })
        }, false);
    });
}, false);

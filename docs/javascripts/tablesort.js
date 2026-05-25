// Enable table sorting on all tables
document$.subscribe(function () {
  var tables = document.querySelectorAll("article table:not(.highlight)");
  tables.forEach(function (table) {
    new Tablesort(table);
  });
});

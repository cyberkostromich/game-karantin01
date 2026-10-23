/* Overpass QL — Хамовники/Лужники с запасом вокруг bbox_mvp. Запуск: см. docs/04_map_moscow.md §4.
   Зеркала: overpass-api.de, maps.mail.ru/osm/tools/overpass (при 504 — повторить) */
[out:json][timeout:300];
(
  way["building"](55.704,37.534,55.732,37.598);
  relation["building"](55.704,37.534,55.732,37.598);
  way["highway"](55.704,37.534,55.732,37.598);
  way["natural"="water"](55.704,37.534,55.732,37.598);
  relation["natural"="water"](55.704,37.534,55.732,37.598);
  way["waterway"="riverbank"](55.704,37.534,55.732,37.598);
  way["leisure"~"park|garden|stadium|pitch"](55.704,37.534,55.732,37.598);
  relation["leisure"~"park|garden"](55.704,37.534,55.732,37.598);
  way["landuse"~"grass|forest|meadow|recreation_ground"](55.704,37.534,55.732,37.598);
  way["natural"~"wood|scrub"](55.704,37.534,55.732,37.598);
  way["railway"~"rail|subway"](55.704,37.534,55.732,37.598);
  node["natural"="tree"](55.704,37.534,55.732,37.598);
  node["shop"](55.704,37.534,55.732,37.598);
  node["railway"~"station|subway_entrance"](55.704,37.534,55.732,37.598);
  node["amenity"~"pharmacy|fuel|school|hospital"](55.704,37.534,55.732,37.598);
);
out body;
>;
out skel qt;

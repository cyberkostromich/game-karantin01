/* Доп. выгрузка: стены Новодевичьего, стадион, станции метро, подстанции, мачты (для привязки POI) */
[out:json][timeout:120];
(
  way["barrier"~"wall|city_wall"](55.7225,37.5500,55.7290,37.5620);
  way["historic"](55.7225,37.5500,55.7290,37.5620);
  way["amenity"="place_of_worship"](55.7225,37.5500,55.7290,37.5620);
  way["leisure"="stadium"](55.710,37.545,55.722,37.562);
  way["building"="stadium"](55.710,37.545,55.722,37.562);
  node["railway"="station"](55.700,37.530,55.735,37.605);
  node["station"="subway"](55.700,37.530,55.735,37.605);
  way["power"~"substation|plant"](55.704,37.534,55.732,37.598);
  node["man_made"~"tower|mast"](55.704,37.534,55.732,37.598);
);
out body;
>;
out skel qt;

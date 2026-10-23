#!/usr/bin/env python3
"""onepager.py — собирает 00_onepager.html (самодостаточный) и рендерит 00_onepager.png через headless Chromium."""
import base64
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
D = {p.stem: json.loads(p.read_text()) for p in (ROOT / "data").glob("*.json")}
ICON = lambda i: (ROOT / "assets/icons/svg" / f"{i}.svg").read_text()
IMG = lambda n: "data:image/png;base64," + base64.b64encode((ROOT / "previews/models" / f"{n}.png").read_bytes()).decode()

u = D["units"]; z = D["zombies"]


def unit_row(k):
    x = u[k]; a = x["attack"]
    c = x["cost"]
    return (f'<div class="row"><div class="ic">{ICON("unit_" + k)}</div><div class="nm"><b>{x["name_ru"]}</b><span>{x["role"]}</span></div>'
            f'<div class="st"><i>HP</i>{x["hp"]}</div><div class="st"><i>DPS</i>{a["damage"] * a["rof"]:g}</div>'
            f'<div class="st"><i>рекр.</i>{x["recruits"]}</div><div class="st"><i>шум</i>{x["noise_attack"]}</div>'
            f'<div class="st w"><i>еда·дер·жел</i>{c["food"]}·{c["wood"]}·{c["iron"]}</div></div>')


def zmb_card(k, icon):
    x = z[k]
    return (f'<div class="zc"><div class="ic">{ICON(icon)}</div><b>{x["name_ru"].split(" (")[0]}</b>'
            f'<span>ночь {x.get("first_night", "—")} · HP {x["hp"]}</span></div>')


units_html = "".join(unit_row(k) for k in ("assault", "sniper", "medic", "scout", "bmp", "tank", "heli"))
zmb_html = "".join(zmb_card(k, i) for k, i in (("walker", "zmb_walker"), ("runner", "zmb_runner"), ("screamer", "zmb_screamer"),
                                                ("brute", "zmb_brute"), ("spitter", "zmb_spitter"), ("nest", "zmb_nest")))
res = [("res_food", "Еда", "Теплица, рейды → списание на рассвете"), ("res_power", "Энергия", "Баланс сети, ночью — прожекторы"),
       ("res_wood", "Дерево", "Парки Лужников и Нескучный сад"), ("res_iron", "Железо", "Остовы машин на проспектах"),
       ("res_people", "Люди", "Спасение и рождение → рабочие и рекруты"), ("res_morale", "Мораль", "Скорость работы, рождаемость")]
res_html = "".join(f'<div class="rc"><div class="ic">{ICON(i)}</div><b>{n}</b><span>{t}</span></div>' for i, n, t in res)
gallery = "".join(f'<figure><img src="{IMG(n)}"/><figcaption>{c}</figcaption></figure>' for n, c in (
    ("unit_assault", "Штурмовик"), ("unit_medic", "Медик"), ("civ_adult_b", "Мирный"), ("zmb_walker", "Ходок"),
    ("zmb_brute", "Громила"), ("veh_tank", "Танк"), ("veh_bmp", "БМП"), ("bld_hq", "Штаб"), ("bld_tower", "Вышка"),
    ("city_panel_9fl", "Панелька 9 эт.")))

html = f"""<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Карантин: Москва</title>
<style>
:root{{--bg:#EEECE6;--card:#FAF9F6;--ink:#22262C;--mut:#6B6F75;--line:#DDD9CF;--acc:#FF6A1F;--ol:#4E5A35;--gr:#9BE564;--dk:#2E333B}}
*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:var(--bg);color:var(--ink);font:15px/1.45 Inter,system-ui,sans-serif;padding:40px;width:1440px}}
h1{{font-size:64px;letter-spacing:-1.5px;line-height:1;font-weight:800}} h1 em{{color:var(--acc);font-style:normal}}
h2{{font-size:13px;letter-spacing:2px;text-transform:uppercase;color:var(--mut);font-weight:700;margin-bottom:14px}}
.top{{display:grid;grid-template-columns:1.4fr 1fr;gap:28px;align-items:end;margin-bottom:28px}}
.lead{{font-size:19px;color:#3A3F46;max-width:760px;margin-top:16px}}
.tags{{display:flex;gap:8px;flex-wrap:wrap;margin-top:18px}} .tags span{{background:var(--dk);color:#fff;border-radius:99px;padding:6px 14px;font-size:13px;font-weight:600}}
.tags span.a{{background:var(--acc)}}
.kpi{{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}}
.k{{background:var(--card);border-radius:18px;padding:18px}} .k b{{font-size:40px;font-weight:800;display:block;letter-spacing:-1px}} .k span{{color:var(--mut);font-size:13px}}
.grid{{display:grid;grid-template-columns:repeat(12,1fr);gap:18px}}
.card{{background:var(--card);border-radius:22px;padding:24px}}
.c4{{grid-column:span 4}} .c5{{grid-column:span 5}} .c7{{grid-column:span 7}} .c8{{grid-column:span 8}} .c6{{grid-column:span 6}} .c12{{grid-column:span 12}}
.pill{{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}}
.pl{{border-left:4px solid var(--acc);padding:4px 0 4px 14px}} .pl b{{display:block;font-size:17px}} .pl span{{color:var(--mut);font-size:13.5px}}
.loop{{display:flex;align-items:center;gap:10px;flex-wrap:wrap;font-weight:600}}
.loop .s{{background:#fff;border:1.5px solid var(--line);border-radius:12px;padding:10px 14px}} .loop .ar{{color:var(--acc);font-size:20px}}
.loop .s.n{{background:var(--dk);color:#fff;border-color:var(--dk)}} .loop .s.g{{background:#E9F7DD;border-color:#BFE6A0}}
.cycle{{display:grid;grid-template-columns:20fr 240fr 20fr 150fr;height:46px;border-radius:12px;overflow:hidden;margin:16px 0 8px;font-size:12px;font-weight:700}}
.cycle div{{display:flex;align-items:center;justify-content:center}}
.row{{display:grid;grid-template-columns:44px 1fr 62px 62px 52px 52px 104px;gap:8px;align-items:center;padding:8px 0;border-bottom:1px solid var(--line)}}
.row:last-child{{border:0}} .row .ic svg,.zc .ic svg,.rc .ic svg{{width:40px;height:40px}}
.nm b{{display:block}} .nm span{{color:var(--mut);font-size:12.5px}}
.st{{font-weight:700;font-variant-numeric:tabular-nums;font-size:15px}} .st i{{display:block;font-style:normal;font-weight:500;color:var(--mut);font-size:10.5px;text-transform:uppercase;letter-spacing:.5px}}
.zg{{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}}
.zc{{background:var(--dk);color:#fff;border-radius:14px;padding:12px;display:grid;grid-template-columns:44px 1fr;column-gap:8px}} .zc .ic{{grid-row:span 2}}
.zc span{{color:#AEB4BB;font-size:12px}}
.inf{{margin-top:14px;background:#E9F7DD;border-radius:14px;padding:14px;font-size:14px}} .inf b{{color:#2F6B12}}
.rg{{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}}
.rc{{display:grid;grid-template-columns:44px 1fr;column-gap:10px;align-items:center}} .rc .ic{{grid-row:span 2}} .rc span{{color:var(--mut);font-size:12.5px;line-height:1.3}}
.gal{{display:grid;grid-template-columns:repeat(10,1fr);gap:8px}} figure{{background:#fff;border-radius:14px;padding:6px;text-align:center}}
figure img{{width:100%;display:block}} figcaption{{font-size:12px;font-weight:600;color:var(--mut);padding-bottom:4px}}
.map{{font:12.5px/1.35 'DejaVu Sans Mono',monospace;background:#1F2A36;color:#CFE3F0;border-radius:14px;padding:16px;white-space:pre;overflow:hidden}}
.map b{{color:var(--acc)}} .map i{{color:var(--gr);font-style:normal}}
.rm{{display:grid;grid-template-columns:repeat(7,1fr);gap:8px}} .rm div{{background:#fff;border-radius:12px;padding:12px;border-top:4px solid var(--ol)}}
.rm b{{display:block;font-size:13px}} .rm span{{font-size:12px;color:var(--mut)}} .rm div.t{{border-top-color:var(--acc);background:#FFF1E8}}
.foot{{margin-top:20px;color:var(--mut);font-size:12.5px;display:flex;justify-content:space-between}}
</style></head><body>
<div class="top"><div>
<h2>Game concept · v0.1 · 2026-10-23</h2>
<h1>КАРАНТИН:<br><em>МОСКВА</em></h1>
<p class="lead">Кооперативная RTS-выживалка. 1–4 командира держат арену «Лужники», днём вытаскивают людей из заражённых Хамовников, ночью отбивают орду. Каждый солдат — бывший мирный. Каждый укушенный — будущий враг.</p>
<div class="tags"><span class="a">Co-op 1–4</span><span>RTS + колони-сим</span><span>2.5D low-poly</span><span>Godot 4.6</span><span>Москва из OpenStreetMap</span><span>PC</span></div>
</div><div class="kpi">
<div class="k"><b>12</b><span>игровых дней ≈ 80 мин</span></div><div class="k"><b>7</b><span>военных юнитов</span></div><div class="k"><b>945</b><span>зомби в финальной волне (4 игр.)</span></div>
<div class="k"><b>25</b><span>построек</span></div><div class="k"><b>13</b><span>технологий</span></div><div class="k"><b>4</b><span>доктрины для коопа</span></div>
</div></div>

<div class="grid">
<div class="card c12"><h2>Столпы</h2><div class="pill">
<div class="pl"><b>Люди — главный ресурс</b><span>Солдат = минус рабочий. Танк = минус три. Потеря человека бьёт по экономике и порождает зомби.</span></div>
<div class="pl"><b>Шум — это угроза</b><span>Выстрелы, двигатели и стройка зовут орду. Танк решает проблему и создаёт новую.</span></div>
<div class="pl"><b>День — экспансия, ночь — оборона</b><span>Разведка, спасение, добыча днём. Стены, прожекторы и волна ночью.</span></div>
<div class="pl"><b>Кооп через специализацию</b><span>Мотострелки · Бронетехника · Авиация · Гражданская оборона.</span></div>
</div></div>

<div class="card c7"><h2>Игровой цикл</h2>
<div class="loop"><div class="s">Разведчик находит «?»</div><div class="ar">→</div><div class="s">Мирные идут за юнитом</div><div class="ar">→</div><div class="s g">КПП: заражён?</div><div class="ar">→</div><div class="s">Работа · стройка · рекрут</div><div class="ar">→</div><div class="s n">Ночь: держать стены</div></div>
<div class="cycle"><div style="background:#F6C9A9">рассвет</div><div style="background:#F4E6B8">ДЕНЬ 240 с — рейды, спасение, добыча, стройка</div><div style="background:#C9B9D9">сумерки</div><div style="background:#26334A;color:#fff">НОЧЬ 150 с — орда</div></div>
<p style="color:var(--mut);font-size:13px">Рассвет: списание еды, мораль, рождение детей. Сумерки: объявлено направление волны. Победа — пережить 12 ночей и эвакуировать ≥ 30 человек с поля арены.</p>
</div>
<div class="card c5"><h2>Ресурсы</h2><div class="rg">{res_html}</div></div>

<div class="card c7"><h2>Армия · каждый юнит стоит рекрутов из мирных</h2>{units_html}</div>
<div class="card c5"><h2>Заражённые</h2><div class="zg">{zmb_html}</div>
<div class="inf"><b>Заражение — центральная механика.</b> Любой укус мирного → инкубация 20–40 с → зомби на месте, в том числе внутри базы. Солдат — шанс 15%. Видно только после КПП, осмотра медиком или симптомов. Лечат антидот медика и Медпункт; Карантин гасит вспышку.</div></div>

<div class="card c12"><h2>Плейсхолдер-ассеты в пакете · 75 моделей .glb · 67 иконок</h2><div class="gal">{gallery}</div></div>

<div class="card c6"><h2>Карта MVP: Хамовники / Лужники (~3.4 × 2.7 км, из OSM)</h2>
<div class="map">          N ▲ Комсомольский пр-т  <b>← орда дня 7</b>
 Новодевичий ◆           │          м. Фрунзенская <i>⬣</i>
                          │  Радиовышка ⌖
 Лужнецкий ═╗  м.Спортивная <i>⬣</i>   Подстанция ⚡   Андреевский ═╗
 мост       ║  ═══ ТТК ═══                         мост          ║ Нескучный 🌲
   ≈≈≈≈≈≈≈≈ ║  ╔════════════╗   парк Лужников 🌲               ≈≈≈
   ≈ Москва-река ║  <b>АРЕНА ★</b>   ║                             ≈≈≈≈
   ≈≈≈≈≈≈≈≈≈≈≈≈  ╚════════════╝  ≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈
        ≈≈≈≈≈≈≈≈≈≈≈ метромост ═══ м. Воробьёвы горы <i>⬣</i> ≈≈≈≈
                     Воробьёвы горы ▲ высота снайперам</div>
<p style="color:var(--mut);font-size:13px;margin-top:10px">Река с трёх сторон → мосты = узкие места. 3 станции метро = 3 гнезда. Москва, а не Лондон: OSM одинаково прост, но Москва даёт идентичность и готовый левел-дизайн.</p></div>
<div class="card c6"><h2>Техстек и роадмап MVP (~12–13 недель)</h2>
<p style="font-size:14px;margin-bottom:12px"><b>Godot 4.6 · GDScript</b> · зомби = массивы + MultiMesh (1000+ на экране) · flow-field для орды · host-authoritative ENet, снапшоты 10 Гц · весь баланс в JSON · город: OSM → Python → чанки .glb</p>
<div class="rm"><div><b>M0</b><span>Скелет, камера, выделение</span></div><div><b>M1</b><span>Орда, шум, бой, заражение</span></div><div><b>M2</b><span>Мирные, стройка, экономика, волны</span></div>
<div><b>M3</b><span>7 юнитов, способности, техно</span></div><div><b>M4</b><span>Лужники из OSM, события</span></div><div><b>M5</b><span>Кооп 4 игрока, доктрины</span></div><div class="t"><b>M6</b><span>Звук, VFX, баланс, релиз</span></div></div>
</div>
</div>
<div class="foot"><span>Пакет: docs/ (GDD, tech spec, баланс, карта, арт-библия, ассеты, UI, задачи) · data/*.json · assets/ · tools/ · CLAUDE.md</span><span>Рабочее название · все цифры — data/*.json</span></div>
</body></html>"""
out = ROOT / "00_onepager.html"
out.write_text(html)
from playwright.sync_api import sync_playwright  # noqa: E402
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={"width": 1520, "height": 1200}, device_scale_factor=1)
    pg.goto(out.as_uri()); pg.wait_for_timeout(300)
    pg.screenshot(path=str(ROOT / "00_onepager.png"), full_page=True); b.close()
print("onepager ok")

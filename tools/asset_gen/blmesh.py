"""
blmesh.py — мост к Blender: детали со скруглением/сглаживанием описываются спекой (см. bl_worker.py),
мешируются одним запуском Blender и кешируются по хешу спеки в .cache/bl_pieces.json.gz (кеш в git —
пересборка моделей без изменений деталей работает и без Blender).
"""
from __future__ import annotations

import gzip
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import trimesh

HERE = Path(__file__).resolve().parent
CACHE = HERE / ".cache" / "bl_pieces.json.gz"
WORKER = HERE / "bl_worker.py"
_PENDING: list = []  # (key, spec, part)


def _key(spec: dict) -> str:
    return hashlib.sha1(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:16]


def request(spec: dict, part) -> None:
    spec = json.loads(json.dumps(spec))  # кортежи → списки, иначе хеш нестабилен
    _PENDING.append((_key(spec), spec, part))


def _load_cache() -> dict:
    if CACHE.exists():
        return json.loads(gzip.decompress(CACHE.read_bytes()))
    return {}


def _run_blender(specs: dict) -> dict:
    exe = shutil.which("blender")
    if not exe:
        raise SystemExit(f"нужен Blender (apt install blender): {len(specs)} новых деталей нет в кеше {CACHE.name}")
    with tempfile.TemporaryDirectory() as td:
        src, dst = Path(td) / "in.json", Path(td) / "out.json"
        src.write_text(json.dumps(specs))
        subprocess.run([exe, "-b", "--factory-startup", "-P", str(WORKER), "--", str(src), str(dst)],
                       check=True, stdout=subprocess.DEVNULL)
        return json.loads(dst.read_text())


def resolve() -> None:
    """Меширует все запрошенные детали (недостающие — через Blender) и подставляет их в Part."""
    if not _PENDING:
        return
    cache = _load_cache()
    missing = {k: s for k, s, _ in _PENDING if k not in cache}
    if missing:
        print(f"blender: {len(missing)} деталей")
        cache.update(_run_blender(missing))
    used = {k for k, _, _ in _PENDING}
    CACHE.parent.mkdir(exist_ok=True)
    data = json.dumps({k: v for k, v in sorted(cache.items()) if k in used}, separators=(",", ":"))
    CACHE.write_bytes(gzip.compress(data.encode(), mtime=0))
    for k, _, part in _PENDING:
        r = cache[k]
        v = np.asarray(r["v"], dtype=float).reshape(-1, 3)
        n = np.asarray(r["n"], dtype=float).reshape(-1, 3, 3)
        part.mesh = trimesh.Trimesh(v, np.arange(len(v)).reshape(-1, 3), process=False)
        part.normals = n
    _PENDING.clear()

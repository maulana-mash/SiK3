#!/usr/bin/env python3
"""Prepare transparent and adaptive full-bleed SiK3 logo PNGs from source JPG.

Outputs:
  - assets/icons/logo_sik3_transparent.png (1024x1024 RGBA, alpha=0 outside squircle)
  - assets/icons/logo_sik3_adaptive_fullbleed.png (1024x1024 RGBA, full-bleed navy/amber)
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
import sys

from PIL import Image, ImageFilter

DEFAULT_SOURCE = (
    r"C:/Users/Mash_Maulana/.gemini/antigravity/brain/"
    r"a00fd2a1-092a-4cf9-b0be-8af2076be78b/.user_uploaded/"
    r"media_1795488885180_abdea873.jpg"
)
TARGET_SIZE = (1024, 1024)


def _is_outer_white(r: int, g: int, b: int) -> bool:
    """Strict near-white predicate so BFS stops cleanly at the dark/amber perimeter."""
    return min(r, g, b) >= 234 and (max(r, g, b) - min(r, g, b)) <= 24


def _is_pale_fringe(r: int, g: int, b: int) -> bool:
    """Detects light anti-aliasing / JPEG halo pixels right along the outer border."""
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    return lum >= 205 and min(r, g, b) >= 160


def _flood_outer_background(img: Image.Image) -> list[list[bool]]:
    """Flood-fills only from the 4 canvas corners so inner white graphics stay opaque."""
    w, h = img.size
    px = img.load()
    visited = [[False] * w for _ in range(h)]
    q: deque[tuple[int, int]] = deque()

    for sx, sy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        r, g, b = px[sx, sy]
        if _is_outer_white(r, g, b):
            visited[sy][sx] = True
            q.append((sx, sy))

    while q:
        x, y = q.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                r, g, b = px[nx, ny]
                if _is_outer_white(r, g, b):
                    visited[ny][nx] = True
                    q.append((nx, ny))

    return visited


def _distance_from_mask(mask: list[list[bool]], max_dist: int) -> list[list[int]]:
    """Computes BFS distance up to max_dist from True pixels in mask."""
    h = len(mask)
    w = len(mask[0])
    dist = [[max_dist + 1] * w for _ in range(h)]
    q: deque[tuple[int, int]] = deque()

    for y in range(h):
        for x in range(w):
            if mask[y][x]:
                dist[y][x] = 0
                q.append((x, y))

    while q:
        x, y = q.popleft()
        d = dist[y][x]
        if d >= max_dist:
            continue
        nd = d + 1
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and dist[ny][nx] > nd:
                dist[ny][nx] = nd
                q.append((nx, ny))

    return dist


def _unblend_white(r: int, g: int, b: int, alpha_norm: float) -> tuple[int, int, int]:
    """Removes white background bleed from semi-transparent edge pixels."""
    if alpha_norm <= 0.05:
        return r, g, b
    inv = 1.0 - alpha_norm
    nr = int(max(0, min(255, round((r - 255.0 * inv) / alpha_norm))))
    ng = int(max(0, min(255, round((g - 255.0 * inv) / alpha_norm))))
    nb = int(max(0, min(255, round((b - 255.0 * inv) / alpha_norm))))
    return nr, ng, nb


def build_transparent_logo(src_rgb: Image.Image) -> tuple[Image.Image, list[list[bool]]]:
    """Produces 1024x1024 RGBA transparent logo with smooth anti-aliased perimeter."""
    w, h = src_rgb.size
    outer_bg = _flood_outer_background(src_rgb)

    px = src_rgb.load()
    dist_outer = _distance_from_mask(outer_bg, max_dist=4)
    expanded_bg = [[outer_bg[y][x] for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            if not expanded_bg[y][x] and dist_outer[y][x] <= 2:
                r, g, b = px[x, y]
                if _is_pale_fringe(r, g, b):
                    expanded_bg[y][x] = True

    alpha_mask = Image.new("L", (w, h), 255)
    apx = alpha_mask.load()
    for y in range(h):
        for x in range(w):
            if expanded_bg[y][x]:
                apx[x, y] = 0

    blurred_alpha = alpha_mask.filter(ImageFilter.GaussianBlur(radius=0.85))
    bapx = blurred_alpha.load()

    dist_expanded = _distance_from_mask(expanded_bg, max_dist=5)
    out = Image.new("RGBA", (w, h))
    opx = out.load()

    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if expanded_bg[y][x]:
                a = (
                    bapx[x, y]
                    if dist_expanded[y][x] == 0
                    and any(
                        0 <= nx < w and 0 <= ny < h and not expanded_bg[ny][nx]
                        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                    )
                    else 0
                )
                if a < 16:
                    opx[x, y] = (0, 0, 0, 0)
                else:
                    ur, ug, ub = _unblend_white(r, g, b, a / 255.0)
                    opx[x, y] = (ur, ug, ub, a)
            elif dist_expanded[y][x] <= 2:
                a = max(bapx[x, y], 220 if dist_expanded[y][x] == 2 else 140)
                if dist_expanded[y][x] == 1:
                    a = min(255, max(0, bapx[x, y]))
                ur, ug, ub = _unblend_white(r, g, b, max(a, 32) / 255.0)
                opx[x, y] = (ur, ug, ub, a)
            else:
                opx[x, y] = (r, g, b, 255)

    for sx, sy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        opx[sx, sy] = (0, 0, 0, 0)

    return out, expanded_bg


def _sample_patch_mean(
    px: object, cx: int, cy: int, radius: int = 8
) -> tuple[float, float, float]:
    sr = sg = sb = 0.0
    n = 0
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            r, g, b = px[x, y]
            sr += r
            sg += g
            sb += b
            n += 1
    return sr / n, sg / n, sb / n


def _lerp_rgb(
    c0: tuple[float, float, float],
    c1: tuple[float, float, float],
    t: float,
) -> tuple[float, float, float]:
    t = max(0.0, min(1.0, t))
    return (
        c0[0] + (c1[0] - c0[0]) * t,
        c0[1] + (c1[1] - c0[1]) * t,
        c0[2] + (c1[2] - c0[2]) * t,
    )


def _detect_horizon_curve(
    src_rgb: Image.Image, outer_bg: list[list[bool]]
) -> tuple[list[float], float, float]:
    """Measures the curved navy/amber horizon inside the squircle and extends it outward."""
    w, h = src_rgb.size
    px = src_rgb.load()
    xs_vals: list[tuple[int, float]] = []

    for x in range(160, w - 160, 4):
        if outer_bg[h // 2][x]:
            continue
        for y in range(490, 585):
            if outer_bg[y][x]:
                continue
            r, g, b = px[x, y]
            if r > 180 and g > 100 and b < 110:
                xs_vals.append((x, float(y)))
                break

    # Left & right edge points and slopes for smooth linear/quadratic extension
    left_pts = [p for p in xs_vals if p[0] <= 215]
    right_pts = [p for p in xs_vals if p[0] >= w - 215]

    x_l, y_l = left_pts[0] if left_pts else (160, 563.0)
    x_l2, y_l2 = left_pts[-1] if len(left_pts) > 1 else (210, 551.0)
    slope_l = (y_l2 - y_l) / max(1, (x_l2 - x_l))

    x_r, y_r = right_pts[-1] if right_pts else (w - 160, 563.0)
    x_r2, y_r2 = right_pts[0] if len(right_pts) > 1 else (w - 210, 552.0)
    slope_r = (y_r - y_r2) / max(1, (x_r - x_r2))

    # Build continuous horizon y(x) across full canvas [0..w-1]
    by_x = {x: y for x, y in xs_vals}
    horizon = [563.0] * w
    for x in range(w):
        if x < x_l:
            horizon[x] = y_l + slope_l * (x - x_l)
        elif x > x_r:
            horizon[x] = y_r + slope_r * (x - x_r)
        else:
            # Interpolate nearest measured points
            nearest = min(xs_vals, key=lambda p: abs(p[0] - x)) if xs_vals else (x, 540.0)
            horizon[x] = by_x.get(x, nearest[1])

    # Smooth horizon slightly to remove single-pixel JPEG jitter
    smoothed = horizon[:]
    for x in range(2, w - 2):
        smoothed[x] = sum(horizon[x - 2 : x + 3]) / 5.0
    return smoothed, y_l, y_r


def build_adaptive_fullbleed_logo(
    src_rgb: Image.Image, outer_bg: list[list[bool]]
) -> Image.Image:
    """Extends clean navy top & amber bottom gradients to all 4 corners with zero seam."""
    w, h = src_rgb.size
    px = src_rgb.load()
    horizon, _, _ = _detect_horizon_curve(src_rgb, outer_bg)

    # Sample clean interior colors from the squircle (away from white shield & rim)
    navy_tl = _sample_patch_mean(px, 240, 200)
    navy_tr = _sample_patch_mean(px, 784, 200)
    navy_ml = _sample_patch_mean(px, 175, 535)
    navy_mr = _sample_patch_mean(px, 845, 535)

    amber_ml = _sample_patch_mean(px, 175, 585)
    amber_mr = _sample_patch_mean(px, 845, 585)
    amber_bl = _sample_patch_mean(px, 260, 820)
    amber_br = _sample_patch_mean(px, 760, 820)

    # Generate clean, streak-free full-bleed background matching original lighting
    bg = Image.new("RGBA", (w, h))
    bpx = bg.load()
    for y in range(h):
        for x in range(w):
            tx = (x - 175.0) / (845.0 - 175.0)
            hy = horizon[x]
            if y < hy - 1.0:
                ty = (y - 200.0) / max(1.0, hy - 200.0)
                top = _lerp_rgb(navy_tl, navy_tr, tx)
                bot = _lerp_rgb(navy_ml, navy_mr, tx)
                c = _lerp_rgb(top, bot, ty)
            elif y > hy + 1.0:
                ty = (y - hy) / max(1.0, 820.0 - hy)
                top = _lerp_rgb(amber_ml, amber_mr, tx)
                bot = _lerp_rgb(amber_bl, amber_br, tx)
                c = _lerp_rgb(top, bot, ty)
            else:
                # 2px anti-aliased transition across the horizon curve
                alpha_b = (y - (hy - 1.0)) / 2.0
                n_col = _lerp_rgb(navy_ml, navy_mr, tx)
                a_col = _lerp_rgb(amber_ml, amber_mr, tx)
                c = _lerp_rgb(n_col, a_col, alpha_b)
            bpx[x, y] = (
                int(max(0, min(255, round(c[0])))),
                int(max(0, min(255, round(c[1])))),
                int(max(0, min(255, round(c[2])))),
                255,
            )

    # Feather the outer 18px rim of the original squircle into the clean full-bleed bg
    # so the squircle border & drop shadow vanish completely while the shield stays 100% intact.
    dist_outer = _distance_from_mask(outer_bg, max_dist=20)
    out = bg.copy()
    opx = out.load()

    for y in range(h):
        for x in range(w):
            d = dist_outer[y][x]
            if d >= 18:
                r, g, b = px[x, y]
                opx[x, y] = (r, g, b, 255)
            elif d > 4 and not outer_bg[y][x]:
                t = (d - 4) / 14.0
                r, g, b = px[x, y]
                br, bg_c, bb, _ = bpx[x, y]
                opx[x, y] = (
                    int(round(br * (1.0 - t) + r * t)),
                    int(round(bg_c * (1.0 - t) + g * t)),
                    int(round(bb * (1.0 - t) + b * t)),
                    255,
                )

    return out


def verify_outputs(transparent_path: Path, fullbleed_path: Path) -> None:
    """Asserts corner transparency and full-bleed non-white corners."""
    t_img = Image.open(transparent_path).convert("RGBA")
    f_img = Image.open(fullbleed_path).convert("RGBA")

    assert t_img.size == TARGET_SIZE, f"Unexpected transparent size: {t_img.size}"
    assert f_img.size == TARGET_SIZE, f"Unexpected fullbleed size: {f_img.size}"

    w, h = TARGET_SIZE
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]

    for cx, cy in corners:
        ta = t_img.getpixel((cx, cy))[3]
        assert ta == 0, f"Transparent corner ({cx},{cy}) has alpha={ta}, expected 0"
        fr, fg, fb, fa = f_img.getpixel((cx, cy))
        assert fa == 255, f"Fullbleed corner ({cx},{cy}) has alpha={fa}, expected 255"
        assert min(fr, fg, fb) < 200, (
            f"Fullbleed corner ({cx},{cy}) appears white/pale: {(fr, fg, fb)}"
        )

    sr, sg, sb, sa = t_img.getpixel((512, 224))
    assert sa == 255 and sr > 230 and sg > 230 and sb > 230, (
        f"Inner shield pixel (512,224) corrupted: {(sr, sg, sb, sa)}"
    )

    print("VERIFIED: transparent 4 corners alpha == 0, inner shield opaque white.")
    print("VERIFIED: fullbleed 4 corners opaque & non-white:")
    for cx, cy in corners:
        print(f"  corner ({cx},{cy}) -> {f_img.getpixel((cx, cy))}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare SiK3 logo assets.")
    parser.add_argument("--source", default=DEFAULT_SOURCE, help="Path to source JPG")
    parser.add_argument(
        "--out-dir",
        default="assets/icons",
        help="Output directory for generated PNG assets",
    )
    args = parser.parse_args()

    src_path = Path(args.source)
    if not src_path.is_file():
        print(f"ERROR: Source image not found: {src_path}", file=sys.stderr)
        return 1

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    src_rgb = Image.open(src_path).convert("RGB")
    if src_rgb.size != TARGET_SIZE:
        src_rgb = src_rgb.resize(TARGET_SIZE, Image.Resampling.LANCZOS)

    transparent_img, outer_bg = build_transparent_logo(src_rgb)
    transparent_path = out_dir / "logo_sik3_transparent.png"
    transparent_img.save(transparent_path, format="PNG")

    fullbleed_img = build_adaptive_fullbleed_logo(src_rgb, outer_bg)
    fullbleed_path = out_dir / "logo_sik3_adaptive_fullbleed.png"
    fullbleed_img.save(fullbleed_path, format="PNG")

    verify_outputs(transparent_path, fullbleed_path)
    print(f"Saved: {transparent_path}")
    print(f"Saved: {fullbleed_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

from collections import Counter, deque
from collections.abc import Iterable

from PIL import Image, ImageDraw


Box = tuple[int, int, int, int]

DEFAULT_TALK_REGIONS: tuple[Box, ...] = ((38, 56, 59, 72),)
DEFAULT_BLINK_REGIONS: tuple[Box, ...] = (
    (28, 38, 45, 53),
    (51, 38, 68, 53),
)

# These are deliberately smaller than DEFAULT_BLINK_REGIONS. They cover the
# eye apertures without reaching eyebrows, glasses rims, hair, or the nose.
DEFAULT_HUMAN_EYE_REGIONS: tuple[Box, ...] = (
    (28, 37, 43, 51),
    (53, 37, 68, 51),
)


def snap_channel(value: int) -> int:
    return max(0, min(255, round(value / 17) * 17))


def quantize_master(image: Image.Image, colors: int = 15) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda value: 255 if int(value) >= 96 else 0)
    matte = Image.new("RGB", rgba.size, (0, 0, 0))
    matte.paste(rgba.convert("RGB"), mask=alpha)
    quantized = matte.quantize(colors=colors, dither=Image.Dither.NONE).convert("RGB")
    quantized = quantized.point(lambda value: snap_channel(int(value)))
    out = quantized.convert("RGBA")
    out.putalpha(alpha)
    return out


def visible_palette(image: Image.Image) -> tuple[tuple[int, int, int], ...]:
    colors = {
        pixel[:3]
        for pixel in image.convert("RGBA").get_flattened_data()
        if pixel[3] > 0
    }
    if not colors:
        raise ValueError("Neutral sprite has no visible colors")
    return tuple(sorted(colors))


def nearest_color(
    color: tuple[int, int, int],
    palette: tuple[tuple[int, int, int], ...],
) -> tuple[int, int, int]:
    return min(
        palette,
        key=lambda candidate: sum((int(color[index]) - int(candidate[index])) ** 2 for index in range(3)),
    )


def _clamp_box(box: Box, size: tuple[int, int]) -> Box:
    width, height = size
    left, top, right, bottom = box
    left = max(0, min(width, left))
    top = max(0, min(height, top))
    right = max(left, min(width, right))
    bottom = max(top, min(height, bottom))
    return left, top, right, bottom


def _luma(color: tuple[int, int, int]) -> float:
    return color[0] * 0.2126 + color[1] * 0.7152 + color[2] * 0.0722


def _most_common_opaque_color(image: Image.Image, box: Box) -> tuple[int, int, int] | None:
    rgba = image.convert("RGBA")
    left, top, right, bottom = _clamp_box(box, rgba.size)
    counts: Counter[tuple[int, int, int]] = Counter()
    for y in range(top, bottom):
        for x in range(left, right):
            r, g, b, a = rgba.getpixel((x, y))
            if a:
                counts[(r, g, b)] += 1
    return counts.most_common(1)[0][0] if counts else None


def derive_human_blink(
    master: Image.Image,
    *,
    eye_regions: Iterable[Box],
    skin_points: Iterable[tuple[int, int]],
) -> Image.Image:
    """Derive a subtle closed-eyelid frame from one locked neutral master.

    The edit is constrained to compact eye apertures. Skin and line colors are
    sampled from the already-quantized master, so the result cannot introduce a
    new palette, alter alpha, move glasses, or redraw the face.
    """

    source_alpha = master.convert("RGBA").getchannel("A")
    out = master.convert("RGBA").copy()
    pixels = out.load()
    if pixels is None:
        return out

    regions = list(eye_regions)
    skins = list(skin_points)
    if not regions or len(regions) != len(skins):
        raise ValueError("Human blink requires one authored skin point per eye region")

    for raw_box, skin_point in zip(regions, skins, strict=True):
        left, top, right, bottom = _clamp_box(raw_box, out.size)
        if right - left < 5 or bottom - top < 5:
            raise ValueError(f"Human blink eye region is too small: {raw_box}")
        if right - left > 18 or bottom - top > 14:
            raise ValueError(f"Human blink eye region is too large: {raw_box}")

        skin_x, skin_y = skin_point
        if not (0 <= skin_x < out.width and 0 <= skin_y < out.height):
            raise ValueError(f"Human blink skin point is outside the sprite: {skin_point}")
        skin_pixel = pixels[skin_x, skin_y]
        skin = skin_pixel[:3] if skin_pixel[3] else None
        eye_colors = [
            pixels[x, y][:3]
            for y in range(top, bottom)
            for x in range(left, right)
            if pixels[x, y][3]
        ]
        if skin is None or not eye_colors:
            continue
        line = min(eye_colors, key=_luma)

        # Replace only an eye-shaped aperture. Corners stay untouched, which
        # protects glasses rims and hair even when they overlap the box.
        cx = (left + right - 1) / 2.0
        cy = (top + bottom - 1) / 2.0
        # Use the full authored aperture radius so lower iris pixels cannot
        # survive beneath the eyelid as a false half-open eye. Tight boxes and
        # the rounded equation still protect the corners/glasses frame.
        rx = max(1.0, (right - left) / 2.0)
        ry = max(1.0, (bottom - top) / 2.0)
        for y in range(top, bottom):
            for x in range(left, right):
                if pixels[x, y][3] == 0:
                    continue
                dx = (x - cx) / rx
                dy = (y - cy) / ry
                if dx * dx + dy * dy <= 1.0:
                    pixels[x, y] = (*skin, pixels[x, y][3])

        # A one-pixel shallow arc reads as an eyelid at native 1x. The former
        # two-pixel full-width bars looked like damaged face patches.
        mid_y = top + (bottom - top) // 2
        inset = max(1, (right - left) // 5)
        arc = [
            (left + inset, mid_y),
            ((left + right) // 2, min(bottom - 2, mid_y + 1)),
            (right - inset - 1, mid_y),
        ]
        draw = ImageDraw.Draw(out)
        draw.line(arc, fill=(*line, 255), width=1)

    out.putalpha(source_alpha)
    return out


def derive_mechanical_blink(
    master: Image.Image,
    *,
    eye_regions: Iterable[Box],
    sensor_points: Iterable[tuple[int, int]],
    socket_points: Iterable[tuple[int, int]],
    shutter_points: Iterable[tuple[int, int]],
    shutter_segments: Iterable[tuple[int, int, int, int]],
    sensor_tolerance: int = 76,
) -> Image.Image:
    """Close authored camera/sensor apertures with a readable shutter slit.

    Each region must tightly bound an actual eye, mono-eye, or visor. The open
    sensor component is first folded into an existing socket color, then a
    short one-pixel shutter line is drawn in another existing palette color.
    This reads as mechanical closure at native size instead of making the eye
    disappear like a power-off effect. Helmet and face pixels outside the
    explicit mask remain byte-identical to the master.
    """

    return _derive_mechanical_component_frame(
        master,
        regions=eye_regions,
        sensor_points=sensor_points,
        target_points=socket_points,
        shutter_points=shutter_points,
        shutter_segments=shutter_segments,
        sensor_tolerance=sensor_tolerance,
        action="blink",
        target_name="socket",
    )


def derive_mechanical_talk(
    master: Image.Image,
    *,
    sensor_regions: Iterable[Box],
    sensor_points: Iterable[tuple[int, int]],
    pulse_points: Iterable[tuple[int, int]],
    sensor_tolerance: int = 76,
) -> Image.Image:
    """Pulse only authored mechanical sensor components for a talk frame.

    The talk frame is sampled from the locked neutral master. Each seed grows
    through one color-connected sensor component inside a tight authored box,
    then receives an existing palette color sampled at the matching pulse
    point. This prevents the former whole-face inversion bars while allowing a
    mono-eye, visor glint, camera pair, or tiny comm light to visibly respond.
    """

    return _derive_mechanical_component_frame(
        master,
        regions=sensor_regions,
        sensor_points=sensor_points,
        target_points=pulse_points,
        shutter_points=None,
        shutter_segments=None,
        sensor_tolerance=sensor_tolerance,
        action="talk",
        target_name="pulse",
    )


def _derive_mechanical_component_frame(
    master: Image.Image,
    *,
    regions: Iterable[Box],
    sensor_points: Iterable[tuple[int, int]],
    target_points: Iterable[tuple[int, int]],
    shutter_points: Iterable[tuple[int, int]] | None,
    shutter_segments: Iterable[tuple[int, int, int, int]] | None,
    sensor_tolerance: int,
    action: str,
    target_name: str,
) -> Image.Image:
    source = master.convert("RGBA")
    out = source.copy()
    source_pixels = source.load()
    out_pixels = out.load()
    if source_pixels is None or out_pixels is None:
        return out

    authored_regions = list(regions)
    sensors = list(sensor_points)
    targets = list(target_points)
    shutters = list(shutter_points) if shutter_points is not None else []
    segments = list(shutter_segments) if shutter_segments is not None else []
    if not authored_regions or len(authored_regions) != len(sensors) or len(authored_regions) != len(targets):
        raise ValueError(
            f"Mechanical {action} requires one sensor and {target_name} point per authored region"
        )
    if bool(shutters) != bool(segments) or (shutters and len(authored_regions) != len(shutters)) or (
        segments and len(authored_regions) != len(segments)
    ):
        raise ValueError(
            f"Mechanical {action} requires one shutter point and segment per authored region"
        )

    maximum_distance = sensor_tolerance * sensor_tolerance
    for index, (raw_box, sensor_point, target_point) in enumerate(
        zip(authored_regions, sensors, targets, strict=True)
    ):
        left, top, right, bottom = _clamp_box(raw_box, source.size)
        if right <= left or bottom <= top:
            raise ValueError(f"Mechanical {action} sensor region is empty: {raw_box}")
        sx, sy = sensor_point
        tx, ty = target_point
        if not (left <= sx < right and top <= sy < bottom):
            raise ValueError(f"Mechanical {action} sensor point {sensor_point} is outside {raw_box}")
        if not (0 <= tx < source.width and 0 <= ty < source.height):
            raise ValueError(f"Mechanical {action} {target_name} point is outside the sprite: {target_point}")
        sensor = source_pixels[sx, sy]
        target = source_pixels[tx, ty]
        if not sensor[3] or not target[3]:
            raise ValueError(f"Mechanical {action} sensor/{target_name} points must be opaque")

        seed_rgb = sensor[:3]
        target_rgb = target[:3]
        pending: deque[tuple[int, int]] = deque([(sx, sy)])
        component: set[tuple[int, int]] = set()
        while pending:
            x, y = pending.popleft()
            if (x, y) in component or not (left <= x < right and top <= y < bottom):
                continue
            r, g, b, a = source_pixels[x, y]
            distance = (r - seed_rgb[0]) ** 2 + (g - seed_rgb[1]) ** 2 + (b - seed_rgb[2]) ** 2
            if not a or distance > maximum_distance:
                continue
            component.add((x, y))
            pending.extend(((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))
        if not component:
            raise ValueError(f"Mechanical {action} sensor component is empty at {sensor_point}")
        for x, y in component:
            out_pixels[x, y] = (*target_rgb, source_pixels[x, y][3])

        if shutters:
            shutter_x, shutter_y = shutters[index]
            if not (0 <= shutter_x < source.width and 0 <= shutter_y < source.height):
                raise ValueError(
                    f"Mechanical {action} shutter point is outside the sprite: {shutters[index]}"
                )
            shutter = source_pixels[shutter_x, shutter_y]
            if not shutter[3]:
                raise ValueError(f"Mechanical {action} shutter point must be opaque")
            shutter_rgb = shutter[:3]
            if shutter_rgb == target_rgb or _luma(shutter_rgb) <= _luma(target_rgb) + 8:
                raise ValueError(
                    f"Mechanical {action} shutter must remain visibly distinct from the socket"
                )

            x1, y1, x2, y2 = segments[index]
            if y1 != y2 or x2 < x1:
                raise ValueError(
                    f"Mechanical {action} shutter segment must be a left-to-right one-pixel line"
                )
            if not (left <= x1 <= x2 < right and top <= y1 < bottom):
                raise ValueError(
                    f"Mechanical {action} shutter segment {segments[index]} is outside {raw_box}"
                )
            if x2 - x1 + 1 < 3 or x2 - x1 + 1 > 8:
                raise ValueError(
                    f"Mechanical {action} shutter segment must be 3-8 pixels long"
                )
            for x in range(x1, x2 + 1):
                if source_pixels[x, y1][3]:
                    out_pixels[x, y1] = (*shutter_rgb, source_pixels[x, y1][3])

    changed = {
        (x, y)
        for y in range(source.height)
        for x in range(source.width)
        if source_pixels[x, y] != out_pixels[x, y]
    }
    if not changed:
        raise ValueError(f"Mechanical {action} does not change any sensor pixels")
    if len(changed) > 240:
        raise ValueError(f"Mechanical {action} changes too many sensor pixels: {len(changed)} > 240")
    return out


def copy_regions_with_locked_palette(
    master: Image.Image,
    variant: Image.Image,
    regions: Iterable[Box],
) -> Image.Image:
    if master.size != variant.size:
        raise ValueError(f"Sprite family size mismatch: {master.size} != {variant.size}")

    width, height = master.size
    master_pixels = list(master.convert("RGBA").get_flattened_data())
    variant_pixels = list(variant.convert("RGBA").get_flattened_data())
    palette = visible_palette(master)
    color_cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}

    for left, top, right, bottom in regions:
        left = max(0, min(width, left))
        top = max(0, min(height, top))
        right = max(left, min(width, right))
        bottom = max(top, min(height, bottom))
        for y in range(top, bottom):
            for x in range(left, right):
                index = y * width + x
                base = master_pixels[index]
                source = variant_pixels[index]
                if base[3] == 0 or source[3] == 0:
                    continue
                source_rgb = source[:3]
                mapped = color_cache.get(source_rgb)
                if mapped is None:
                    mapped = nearest_color(source_rgb, palette)
                    color_cache[source_rgb] = mapped
                master_pixels[index] = (*mapped, base[3])

    out = Image.new("RGBA", master.size, (0, 0, 0, 0))
    out.putdata(master_pixels)
    return out


def build_locked_sprite_family(
    neutral: Image.Image,
    talk: Image.Image,
    blink: Image.Image,
    *,
    colors: int = 15,
    talk_regions: Iterable[Box] = DEFAULT_TALK_REGIONS,
    blink_regions: Iterable[Box] = DEFAULT_BLINK_REGIONS,
) -> dict[str, Image.Image]:
    if neutral.size != talk.size or neutral.size != blink.size:
        raise ValueError(
            f"Sprite family source size mismatch: neutral={neutral.size}, talk={talk.size}, blink={blink.size}"
        )
    master = quantize_master(neutral, colors=colors)
    return {
        "neutral": master,
        "talk": copy_regions_with_locked_palette(master, talk, talk_regions),
        "blink": copy_regions_with_locked_palette(master, blink, blink_regions),
    }

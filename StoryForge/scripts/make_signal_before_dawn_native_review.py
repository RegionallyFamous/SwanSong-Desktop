#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
SOURCE_STORYBOARD = ROOT / "assets" / "signal-before-dawn-slice" / "storyboard_sheet.png"
OUTPUT_IMAGE = ROOT / "assets" / "signal-before-dawn-slice" / "native-scene-review-sheet.png"
OUTPUT_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "native-scene-review-report.json"

SCREEN_SIZE = (224, 144)
EXPECTED_SCENE_COUNT = 35

SOURCE_SCALE = 2
SOURCE_COLUMNS = 2
SOURCE_LABEL_HEIGHT = 18
SOURCE_GAP = 14
SOURCE_MARGIN = 12

OUTPUT_COLUMNS = 5
OUTPUT_LABEL_HEIGHT = 18
OUTPUT_COLUMN_GAP = 14
OUTPUT_ROW_GAP = 14
OUTPUT_MARGIN = 18

SHEET_BACKGROUND = (12, 16, 24, 255)
SOURCE_BACKGROUND = (20, 24, 32, 255)
LABEL_COLOR = (230, 240, 255, 255)
FRAME_COLOR = (96, 112, 136, 255)

MIN_UNIQUE_COLORS = 16
MIN_LUMA_RANGE = 32
MIN_LUMA_ENTROPY = 2.0
MIN_NEAREST_PIXEL_DIFFERENCE_RATIO = 0.01


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def relative_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_pixels(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def expected_source_size(scene_count: int) -> tuple[int, int]:
    source_cell_w = SCREEN_SIZE[0] * SOURCE_SCALE
    source_cell_h = SCREEN_SIZE[1] * SOURCE_SCALE
    rows = math.ceil(scene_count / SOURCE_COLUMNS)
    return (
        SOURCE_MARGIN * 2 + SOURCE_COLUMNS * source_cell_w + (SOURCE_COLUMNS - 1) * SOURCE_GAP,
        SOURCE_MARGIN * 2
        + rows * (SOURCE_LABEL_HEIGHT + source_cell_h)
        + max(0, rows - 1) * SOURCE_GAP,
    )


def expected_source_label(index: int, node: dict[str, Any]) -> str:
    label = (
        f"{index + 1:02d} {node.get('id', '')}  {node.get('charPos', 'center')}  "
        f"{node.get('charId') or 'no-char'}"
    )
    return label[:70]


def source_boxes(index: int) -> tuple[tuple[int, int, int, int], tuple[int, int, int, int]]:
    source_cell_w = SCREEN_SIZE[0] * SOURCE_SCALE
    source_cell_h = SCREEN_SIZE[1] * SOURCE_SCALE
    column = index % SOURCE_COLUMNS
    row = index // SOURCE_COLUMNS
    x = SOURCE_MARGIN + column * (source_cell_w + SOURCE_GAP)
    label_y = SOURCE_MARGIN + row * (SOURCE_LABEL_HEIGHT + source_cell_h + SOURCE_GAP)
    label_box = (x, label_y, x + source_cell_w, label_y + SOURCE_LABEL_HEIGHT)
    frame_y = label_y + SOURCE_LABEL_HEIGHT
    frame_box = (x, frame_y, x + source_cell_w, frame_y + source_cell_h)
    return label_box, frame_box


def source_label_matches(
    storyboard: Image.Image,
    label_box: tuple[int, int, int, int],
    label: str,
) -> bool:
    actual = storyboard.crop(label_box)
    expected = Image.new("RGBA", actual.size, SOURCE_BACKGROUND)
    ImageDraw.Draw(expected).text((0, 0), label, fill=LABEL_COLOR)
    return ImageChops.difference(actual, expected).getbbox() is None


def native_from_source(source_cell: Image.Image) -> tuple[Image.Image, bool]:
    native = source_cell.resize(SCREEN_SIZE, Image.Resampling.NEAREST)
    restored = native.resize(source_cell.size, Image.Resampling.NEAREST)
    exact_nearest_scale = ImageChops.difference(source_cell, restored).getbbox() is None
    return native, exact_nearest_scale


def image_metrics(image: Image.Image) -> dict[str, Any]:
    rgba = image.convert("RGBA")
    colors = rgba.getcolors(maxcolors=rgba.width * rgba.height)
    grayscale = rgba.convert("L")
    luma_min, luma_max = grayscale.getextrema()
    unique_color_count = len(colors) if colors is not None else rgba.width * rgba.height
    luma_range = luma_max - luma_min
    luma_entropy = grayscale.entropy()
    opaque_pixels = sum(count for count, color in colors or [] if color[3] == 255)
    opaque_pixel_ratio = opaque_pixels / (rgba.width * rgba.height) if colors is not None else 0.0
    nonblank = (
        unique_color_count >= MIN_UNIQUE_COLORS
        and luma_range >= MIN_LUMA_RANGE
        and luma_entropy >= MIN_LUMA_ENTROPY
    )
    return {
        "pixel_sha256": sha256_pixels(rgba),
        "unique_color_count": unique_color_count,
        "luma_min": luma_min,
        "luma_max": luma_max,
        "luma_range": luma_range,
        "luma_entropy": round(luma_entropy, 6),
        "opaque_pixel_ratio": round(opaque_pixel_ratio, 6),
        "nonblank": nonblank,
    }


def pixel_difference_ratio(left: Image.Image, right: Image.Image) -> float:
    difference = ImageChops.difference(left.convert("RGBA"), right.convert("RGBA"))
    bands = difference.split()
    changed = bands[0]
    for band in bands[1:]:
        changed = ImageChops.lighter(changed, band)
    unchanged_pixels = changed.histogram()[0]
    return 1.0 - unchanged_pixels / (left.width * left.height)


def nearest_scene_differences(cells: list[Image.Image], scene_ids: list[str]) -> list[dict[str, Any]]:
    nearest: list[tuple[float, str] | None] = [None] * len(cells)
    for left_index in range(len(cells)):
        for right_index in range(left_index + 1, len(cells)):
            ratio = pixel_difference_ratio(cells[left_index], cells[right_index])
            left_best = nearest[left_index]
            if left_best is None or ratio < left_best[0]:
                nearest[left_index] = (ratio, scene_ids[right_index])
            right_best = nearest[right_index]
            if right_best is None or ratio < right_best[0]:
                nearest[right_index] = (ratio, scene_ids[left_index])

    result: list[dict[str, Any]] = []
    for entry in nearest:
        if entry is None:
            raise ValueError("At least two scene cells are required for uniqueness checks")
        result.append(
            {
                "scene_id": entry[1],
                "pixel_difference_ratio": round(entry[0], 8),
            }
        )
    return result


def output_size(scene_count: int) -> tuple[int, int]:
    rows = math.ceil(scene_count / OUTPUT_COLUMNS)
    return (
        OUTPUT_MARGIN * 2
        + OUTPUT_COLUMNS * SCREEN_SIZE[0]
        + (OUTPUT_COLUMNS - 1) * OUTPUT_COLUMN_GAP,
        OUTPUT_MARGIN * 2
        + rows * (OUTPUT_LABEL_HEIGHT + SCREEN_SIZE[1])
        + max(0, rows - 1) * OUTPUT_ROW_GAP,
    )


def output_boxes(index: int) -> tuple[tuple[int, int, int, int], tuple[int, int, int, int]]:
    column = index % OUTPUT_COLUMNS
    row = index // OUTPUT_COLUMNS
    x = OUTPUT_MARGIN + column * (SCREEN_SIZE[0] + OUTPUT_COLUMN_GAP)
    label_y = OUTPUT_MARGIN + row * (OUTPUT_LABEL_HEIGHT + SCREEN_SIZE[1] + OUTPUT_ROW_GAP)
    label_box = (x, label_y, x + SCREEN_SIZE[0], label_y + OUTPUT_LABEL_HEIGHT)
    frame_y = label_y + OUTPUT_LABEL_HEIGHT
    frame_box = (x, frame_y, x + SCREEN_SIZE[0], frame_y + SCREEN_SIZE[1])
    return label_box, frame_box


def make_sheet(cells: list[Image.Image], scene_ids: list[str]) -> tuple[Image.Image, list[dict[str, Any]]]:
    sheet = Image.new("RGBA", output_size(len(cells)), SHEET_BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    placements: list[dict[str, Any]] = []

    for index, (cell, scene_id) in enumerate(zip(cells, scene_ids)):
        label_box, frame_box = output_boxes(index)
        label = f"{index + 1:02d} {scene_id}"
        text_box = draw.textbbox((label_box[0], label_box[1]), label)
        if text_box[2] > label_box[2] or text_box[3] > label_box[3]:
            raise ValueError(f"Output label does not fit its gutter: {label}")

        draw.rectangle(
            (frame_box[0] - 1, frame_box[1] - 1, frame_box[2], frame_box[3]),
            outline=FRAME_COLOR,
        )
        draw.text((label_box[0], label_box[1]), label, fill=LABEL_COLOR)
        sheet.alpha_composite(cell, (frame_box[0], frame_box[1]))
        placements.append(
            {
                "label": label,
                "label_box": list(label_box),
                "frame_box": list(frame_box),
                "label_outside_frame": label_box[3] <= frame_box[1],
            }
        )

    return sheet, placements


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def require(check: bool, message: str) -> None:
    if not check:
        raise ValueError(message)


def main() -> None:
    project = load_json(PROJECT)
    scene_nodes = [node for node in project.get("nodes") or [] if node.get("type") == "scene"]
    scene_ids = [str(node.get("id") or "") for node in scene_nodes]

    require(len(scene_nodes) == EXPECTED_SCENE_COUNT, f"Expected {EXPECTED_SCENE_COUNT} scene nodes, found {len(scene_nodes)}")
    require(all(scene_ids), "Every scene node must have a non-empty ID")
    require(len(set(scene_ids)) == len(scene_ids), "Scene node IDs must be unique")

    with Image.open(SOURCE_STORYBOARD) as source_image:
        source_mode = source_image.mode
        source_dimensions = source_image.size
        storyboard = source_image.convert("RGBA")

    required_source_dimensions = expected_source_size(len(scene_nodes))
    require(
        source_dimensions == required_source_dimensions,
        f"Source storyboard is {source_dimensions}, expected {required_source_dimensions}",
    )

    cells: list[Image.Image] = []
    scene_records: list[dict[str, Any]] = []
    all_source_labels_match = True
    all_source_cells_exact_nearest_scale = True

    for index, node in enumerate(scene_nodes):
        label_box, frame_box = source_boxes(index)
        label = expected_source_label(index, node)
        label_matches = source_label_matches(storyboard, label_box, label)
        source_cell = storyboard.crop(frame_box)
        native, exact_nearest_scale = native_from_source(source_cell)
        metrics = image_metrics(native)

        all_source_labels_match = all_source_labels_match and label_matches
        all_source_cells_exact_nearest_scale = all_source_cells_exact_nearest_scale and exact_nearest_scale
        cells.append(native)
        scene_records.append(
            {
                "index": index + 1,
                "id": scene_ids[index],
                "source_label": label,
                "source_label_box": list(label_box),
                "source_label_matches_project": label_matches,
                "source_frame_box": list(frame_box),
                "source_frame_dimensions": list(source_cell.size),
                "source_is_exact_nearest_2x": exact_nearest_scale,
                "native_dimensions": list(native.size),
                **metrics,
            }
        )

    require(all_source_labels_match, "Source storyboard labels do not match the current project scene order")
    require(all_source_cells_exact_nearest_scale, "One or more source frames are not exact nearest-neighbor 2x cells")

    pixel_hashes = [record["pixel_sha256"] for record in scene_records]
    nearest = nearest_scene_differences(cells, scene_ids)
    for record, nearest_entry in zip(scene_records, nearest):
        record["nearest_scene"] = nearest_entry
        record["unique_pixel_hash"] = pixel_hashes.count(record["pixel_sha256"]) == 1
        record["nearest_difference_passes"] = (
            nearest_entry["pixel_difference_ratio"] >= MIN_NEAREST_PIXEL_DIFFERENCE_RATIO
        )

    all_cells_native_size = all(cell.size == SCREEN_SIZE for cell in cells)
    all_cells_nonblank = all(bool(record["nonblank"]) for record in scene_records)
    all_cell_hashes_unique = len(set(pixel_hashes)) == len(pixel_hashes)
    all_cells_different_enough = all(bool(record["nearest_difference_passes"]) for record in scene_records)

    require(all_cells_native_size, "One or more output cells are not exactly 224x144")
    require(all_cells_nonblank, "One or more output cells failed nonblank checks")
    require(all_cell_hashes_unique, "One or more scene cells have duplicate pixel hashes")
    require(all_cells_different_enough, "One or more scene cells are too similar to their nearest neighbor")

    sheet, placements = make_sheet(cells, scene_ids)
    for record, placement in zip(scene_records, placements):
        record["output_label"] = placement["label"]
        record["output_label_box"] = placement["label_box"]
        record["output_frame_box"] = placement["frame_box"]
        record["output_label_outside_frame"] = placement["label_outside_frame"]

    placed_scene_ids = [str(record["id"]) for record in scene_records]
    all_scene_nodes_appear_once = (
        len(placements) == len(scene_ids)
        and placed_scene_ids == scene_ids
        and len(set(placed_scene_ids)) == len(placed_scene_ids)
    )
    all_labels_outside_frames = all(bool(record["output_label_outside_frame"]) for record in scene_records)
    require(all_scene_nodes_appear_once, "Every project scene node must appear exactly once in project order")
    require(all_labels_outside_frames, "One or more labels overlap their native content frame")

    save_png(sheet, OUTPUT_IMAGE)
    with Image.open(OUTPUT_IMAGE) as output_image:
        output_mode = output_image.mode
        output_dimensions = output_image.size
        saved_sheet = output_image.convert("RGBA")

    output_cells_match = True
    for cell, record in zip(cells, scene_records):
        output_cell = saved_sheet.crop(tuple(record["output_frame_box"]))
        matches = sha256_pixels(output_cell) == record["pixel_sha256"]
        record["output_pixels_match_source_cell"] = matches
        output_cells_match = output_cells_match and matches

    require(output_dimensions == output_size(len(scene_nodes)), "Saved output sheet dimensions changed unexpectedly")
    require(output_cells_match, "One or more saved output frames differ from their source cells")

    checks = {
        "project_scene_count_is_35": len(scene_nodes) == EXPECTED_SCENE_COUNT,
        "project_scene_ids_are_unique": len(set(scene_ids)) == len(scene_ids),
        "source_storyboard_dimensions_match": source_dimensions == required_source_dimensions,
        "source_labels_match_project_order": all_source_labels_match,
        "source_cells_are_exact_nearest_2x": all_source_cells_exact_nearest_scale,
        "all_cells_are_exactly_224x144": all_cells_native_size,
        "all_cells_are_nonblank": all_cells_nonblank,
        "all_cell_pixel_hashes_are_unique": all_cell_hashes_unique,
        "all_cells_meet_nearest_difference_threshold": all_cells_different_enough,
        "all_scene_nodes_appear_once": all_scene_nodes_appear_once,
        "all_labels_are_outside_frames": all_labels_outside_frames,
        "saved_output_cells_match_source_cells": output_cells_match,
    }

    report = {
        "schema_version": 1,
        "status": "pass" if all(checks.values()) else "fail",
        "generator": {
            "path": relative_path(Path(__file__).resolve()),
            "sha256": sha256_file(Path(__file__).resolve()),
            "method": "crop storyboard 2x cells and restore exact native pixels with nearest-neighbor",
            "timestamps_included": False,
        },
        "project": {
            "path": relative_path(PROJECT),
            "sha256": sha256_file(PROJECT),
            "bytes": PROJECT.stat().st_size,
            "name": project.get("name"),
            "version": project.get("version"),
            "start_node_id": project.get("startNodeId"),
            "total_node_count": len(project.get("nodes") or []),
            "scene_node_count": len(scene_nodes),
            "scene_node_ids": scene_ids,
        },
        "source_storyboard": {
            "path": relative_path(SOURCE_STORYBOARD),
            "sha256": sha256_file(SOURCE_STORYBOARD),
            "pixel_sha256": sha256_pixels(storyboard),
            "bytes": SOURCE_STORYBOARD.stat().st_size,
            "dimensions": list(source_dimensions),
            "expected_dimensions": list(required_source_dimensions),
            "mode": source_mode,
            "columns": SOURCE_COLUMNS,
            "rendered_cell_dimensions": [SCREEN_SIZE[0] * SOURCE_SCALE, SCREEN_SIZE[1] * SOURCE_SCALE],
            "render_scale": SOURCE_SCALE,
        },
        "output": {
            "image_path": relative_path(OUTPUT_IMAGE),
            "report_path": relative_path(OUTPUT_REPORT),
            "sha256": sha256_file(OUTPUT_IMAGE),
            "pixel_sha256": sha256_pixels(saved_sheet),
            "bytes": OUTPUT_IMAGE.stat().st_size,
            "dimensions": list(output_dimensions),
            "mode": output_mode,
            "columns": OUTPUT_COLUMNS,
            "rows": math.ceil(len(scene_nodes) / OUTPUT_COLUMNS),
            "native_content_dimensions": list(SCREEN_SIZE),
            "scene_count": len(scene_nodes),
            "scene_ids": placed_scene_ids,
        },
        "verification": {
            "passed": all(checks.values()),
            "checks": checks,
            "thresholds": {
                "minimum_unique_colors": MIN_UNIQUE_COLORS,
                "minimum_luma_range": MIN_LUMA_RANGE,
                "minimum_luma_entropy": MIN_LUMA_ENTROPY,
                "minimum_nearest_pixel_difference_ratio": MIN_NEAREST_PIXEL_DIFFERENCE_RATIO,
            },
            "summary": {
                "nonblank_scene_count": sum(bool(record["nonblank"]) for record in scene_records),
                "placed_scene_count": len(placed_scene_ids),
                "unique_pixel_hash_count": len(set(pixel_hashes)),
                "minimum_unique_color_count": min(int(record["unique_color_count"]) for record in scene_records),
                "minimum_luma_range": min(int(record["luma_range"]) for record in scene_records),
                "minimum_luma_entropy": min(float(record["luma_entropy"]) for record in scene_records),
                "minimum_nearest_pixel_difference_ratio": min(
                    float(record["nearest_scene"]["pixel_difference_ratio"]) for record in scene_records
                ),
            },
            "scenes": scene_records,
        },
    }

    OUTPUT_REPORT.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        f"wrote {relative_path(OUTPUT_IMAGE)} ({output_dimensions[0]}x{output_dimensions[1]}) "
        f"and {relative_path(OUTPUT_REPORT)} for {len(scene_nodes)} scenes"
    )


if __name__ == "__main__":
    main()

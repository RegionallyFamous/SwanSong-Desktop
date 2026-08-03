#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any
from xml.etree import ElementTree


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import clean_markdown, load_manifest, manuscript_files, manuscript_sections, manuscript_sha256, project_path, sha256, write_json


VALIDATOR = SCRIPT_DIR / "check_light_novel_project.py"
ZIP_TIME = (1980, 1, 1, 0, 0, 0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build deterministic EPUB and polished PDF light-novel releases.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--only", choices=("both", "epub", "pdf"), default="both")
    parser.add_argument("--output-root", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--proof-dir", type=Path)
    parser.add_argument("--skip-gate", action="store_true", help=argparse.SUPPRESS)
    return parser.parse_args()


def ensure_reportlab() -> None:
    if importlib.util.find_spec("reportlab") is not None:
        return
    if os.environ.get("FORGE_NOVEL_PDF_REEXEC") == "1":
        raise RuntimeError("ReportLab is unavailable after interpreter fallback")
    candidates = [
        Path("/Users/nick/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"),
        Path("/usr/bin/python3"),
        Path("/opt/homebrew/bin/python3"),
        Path(sys.executable),
    ]
    for candidate in candidates:
        if not candidate.is_file() or str(candidate) == sys.executable:
            continue
        check = subprocess.run(
            [str(candidate), "-c", "import reportlab"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if check.returncode == 0:
            env = os.environ.copy()
            env["FORGE_NOVEL_PDF_REEXEC"] = "1"
            os.execve(str(candidate), [str(candidate), str(Path(__file__).resolve()), *sys.argv[1:]], env)
    raise RuntimeError("PDF output requires ReportLab; install reportlab for the active Python interpreter")


def zip_write(zf: zipfile.ZipFile, name: str, data: bytes, *, compress: bool = True) -> None:
    info = zipfile.ZipInfo(name, ZIP_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED if compress else zipfile.ZIP_STORED
    info.external_attr = 0o644 << 16
    zf.writestr(info, data)


def paragraphs(text: str) -> list[str]:
    cleaned = clean_markdown(text)
    result: list[str] = []
    for item in cleaned.split("\n\n"):
        value = " ".join(line.strip() for line in item.splitlines() if not line.lstrip().startswith("#"))
        if value:
            result.append(value)
    return result


def xhtml_text(value: str) -> str:
    escaped = html.escape(value, quote=False)
    escaped = escaped.replace("—", "&#8212;").replace("–", "&#8211;")
    return escaped


def parity_text(value: str) -> str:
    return " ".join("".join(character.lower() if character.isalnum() else " " for character in value).split())


def text_parity_missing(expected: list[str], extracted: str) -> list[str]:
    haystack = parity_text(extracted)
    return [item[:160] for item in expected if parity_text(item) not in haystack]


def illustration_assets(root: Path, publication: dict[str, Any]) -> dict[str, Path]:
    result: dict[str, Path] = {}
    cover = publication.get("cover") or {}
    if isinstance(cover.get("asset_path"), str) and cover["asset_path"]:
        result["cover"] = project_path(root, cover["asset_path"])
    for placement in publication.get("illustration_placements") or []:
        if isinstance(placement, dict) and placement.get("asset_path"):
            result[str(placement.get("id") or placement.get("scene_id"))] = project_path(root, str(placement["asset_path"]))
    return result


def build_epub(
    path: Path,
    manifest: dict[str, Any],
    sections: dict[str, str],
    assets: dict[str, Path],
) -> dict[str, Any]:
    identity = manifest.get("identity") or {}
    publication = manifest.get("publication") or {}
    chapters = [item for item in manifest.get("chapters") or [] if isinstance(item, dict)]
    placements = {
        str(item.get("scene_id")): item
        for item in publication.get("illustration_placements") or []
        if isinstance(item, dict)
    }
    chapter_docs: list[tuple[str, str, str]] = []
    for index, chapter in enumerate(chapters, start=1):
        filename = f"chapter-{index:02d}.xhtml"
        body = [f"<h1>{xhtml_text(str(chapter.get('title') or f'Chapter {index}'))}</h1>"]
        for scene_index, scene_id in enumerate(chapter.get("scene_ids") or []):
            if scene_index:
                body.append(f"<div class=\"scene-break\">{xhtml_text(str(publication.get('scene_break_glyph') or '* * *'))}</div>")
            for paragraph in paragraphs(sections.get(str(scene_id), "")):
                body.append(f"<p>{xhtml_text(paragraph)}</p>")
            placement = placements.get(str(scene_id))
            if placement:
                key = str(placement.get("id") or scene_id)
                asset = assets.get(key)
                if asset:
                    body.append(
                        f"<figure><img src=\"images/{key}{asset.suffix.lower()}\" alt=\"{html.escape(str(placement.get('alt_text') or ''), quote=True)}\"/>"
                        f"<figcaption>{xhtml_text(str(placement.get('caption') or ''))}</figcaption></figure>"
                    )
        document = (
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head>"
            f"<title>{xhtml_text(str(chapter.get('title') or 'Chapter'))}</title>"
            "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/></head><body>"
            + "".join(body)
            + "</body></html>"
        )
        chapter_docs.append((filename, str(chapter.get("title") or f"Chapter {index}"), document))
    nav_items = "".join(
        f"<li><a href=\"{filename}\">{xhtml_text(title)}</a></li>" for filename, title, _ in chapter_docs
    )
    nav = (
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
        "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\">"
        f"<head><title>Contents</title></head><body><nav epub:type=\"toc\"><h1>Contents</h1><ol>{nav_items}</ol></nav></body></html>"
    )
    image_items: list[str] = []
    for key, asset in sorted(assets.items()):
        media = "image/png" if asset.suffix.lower() == ".png" else "image/jpeg"
        properties = " properties=\"cover-image\"" if key == "cover" else ""
        image_items.append(f"<item id=\"img-{key}\" href=\"images/{key}{asset.suffix.lower()}\" media-type=\"{media}\"{properties}/>")
    manifest_items = "".join(
        f"<item id=\"chapter-{index}\" href=\"{filename}\" media-type=\"application/xhtml+xml\"/>"
        for index, (filename, _, _) in enumerate(chapter_docs, start=1)
    )
    spine = "".join(f"<itemref idref=\"chapter-{index}\"/>" for index in range(1, len(chapter_docs) + 1))
    identifier = str(publication.get("identifier") or identity.get("slug"))
    accessibility = publication.get("accessibility") or {}
    access_features = "".join(
        f"<meta property=\"schema:accessibilityFeature\">{xhtml_text(str(item))}</meta>"
        for item in accessibility.get("features") or []
    )
    access_hazards = "".join(
        f"<meta property=\"schema:accessibilityHazard\">{xhtml_text(str(item))}</meta>"
        for item in accessibility.get("hazards") or []
    )
    access_summary = xhtml_text(str(accessibility.get("summary") or ""))
    opf = (
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
        "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"book-id\" prefix=\"schema: http://schema.org/\">"
        "<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
        f"<dc:identifier id=\"book-id\">{xhtml_text(identifier)}</dc:identifier>"
        f"<dc:title>{xhtml_text(str(identity.get('title') or 'Untitled'))}</dc:title>"
        f"<dc:creator>{xhtml_text(str(publication.get('author') or 'Unknown'))}</dc:creator>"
        f"<dc:language>{xhtml_text(str(publication.get('language') or 'en'))}</dc:language>"
        "<meta property=\"dcterms:modified\">1980-01-01T00:00:00Z</meta>"
        f"<meta property=\"schema:accessibilitySummary\">{access_summary}</meta>"
        f"{access_features}{access_hazards}"
        "</metadata><manifest><item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>"
        "<item id=\"css\" href=\"style.css\" media-type=\"text/css\"/>"
        f"{manifest_items}{''.join(image_items)}</manifest><spine>{spine}</spine></package>"
    )
    container = (
        "<?xml version=\"1.0\"?>"
        "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">"
        "<rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>"
        "</rootfiles></container>"
    )
    css = (
        "body{font-family:serif;line-height:1.55;margin:5%;}h1{text-align:center;margin:2em 0;}"
        "p{text-indent:1.2em;margin:0;}p:first-of-type{text-indent:0;}"
        ".scene-break{text-align:center;margin:1.5em;}figure{margin:1.5em 0;text-align:center;}"
        "img{max-width:100%;height:auto;}figcaption{font-size:.8em;font-style:italic;}"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as zf:
        zip_write(zf, "mimetype", b"application/epub+zip", compress=False)
        zip_write(zf, "META-INF/container.xml", container.encode("utf-8"))
        zip_write(zf, "OEBPS/content.opf", opf.encode("utf-8"))
        zip_write(zf, "OEBPS/nav.xhtml", nav.encode("utf-8"))
        zip_write(zf, "OEBPS/style.css", css.encode("utf-8"))
        for filename, _, document in chapter_docs:
            zip_write(zf, f"OEBPS/{filename}", document.encode("utf-8"))
        for key, asset in sorted(assets.items()):
            zip_write(zf, f"OEBPS/images/{key}{asset.suffix.lower()}", asset.read_bytes())
    errors: list[str] = []
    extracted = ""
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        if not names or names[0] != "mimetype" or zf.getinfo("mimetype").compress_type != zipfile.ZIP_STORED:
            errors.append("EPUB mimetype must be the first uncompressed member")
        for required in ("META-INF/container.xml", "OEBPS/content.opf", "OEBPS/nav.xhtml"):
            if required not in names:
                errors.append(f"EPUB is missing {required}")
            elif required.endswith((".xml", ".opf", ".xhtml")):
                ElementTree.fromstring(zf.read(required))
        if zf.testzip():
            errors.append("EPUB zip CRC validation failed")
        extracted = " ".join(
            " ".join(ElementTree.fromstring(zf.read(name)).itertext())
            for name in names
            if name.startswith("OEBPS/chapter-") and name.endswith(".xhtml")
        )
    expected = [paragraph for scene in sections.values() for paragraph in paragraphs(scene)]
    missing_text = text_parity_missing(expected, extracted)
    if missing_text:
        errors.append(f"EPUB text extraction is missing {len(missing_text)} manuscript paragraph(s)")
    epubcheck = shutil.which("epubcheck")
    external = {"available": bool(epubcheck), "required": bool(publication.get("require_external_epubcheck")), "ok": None, "output": ""}
    if epubcheck:
        result = subprocess.run([epubcheck, str(path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        external.update({"ok": result.returncode == 0, "output": result.stdout[-12000:]})
        if result.returncode != 0:
            errors.append("External EPUBCheck reported errors")
    elif external["required"]:
        errors.append("External EPUBCheck is required but not installed")
    return {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "ok": not errors,
        "errors": errors,
        "text_parity": {"expected_paragraphs": len(expected), "missing": missing_text},
        "epubcheck": external,
    }


def build_pdf(
    path: Path,
    manifest: dict[str, Any],
    sections: dict[str, str],
    assets: dict[str, Path],
) -> None:
    from reportlab import __path__ as reportlab_paths
    from reportlab import rl_config
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.pagesizes import A5, LETTER
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
    from reportlab.lib.units import inch
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.platypus import Image, PageBreak, Paragraph, SimpleDocTemplate, Spacer

    font_root = Path(reportlab_paths[0]) / "fonts"
    pdfmetrics.registerFont(TTFont("ForgeSerif", str(font_root / "Vera.ttf")))
    pdfmetrics.registerFont(TTFont("ForgeSerif-Bold", str(font_root / "VeraBd.ttf")))
    pdfmetrics.registerFont(TTFont("ForgeSerif-Italic", str(font_root / "VeraIt.ttf")))
    rl_config.defaultFontName = "ForgeSerif"
    rl_config.canvas_basefontname = "ForgeSerif"
    identity = manifest.get("identity") or {}
    publication = manifest.get("publication") or {}
    typography = publication.get("typography") or {}
    trim = str(typography.get("trim_profile") or "trade-5x8")
    pages = {"trade-5x8": (5 * inch, 8 * inch), "trade-6x9": (6 * inch, 9 * inch), "a5": A5, "letter": LETTER}
    page_size = pages.get(trim, pages["trade-5x8"])
    margin = float(typography.get("margin_inches") or 0.65) * inch
    path.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(path),
        pagesize=page_size,
        leftMargin=margin,
        rightMargin=margin,
        topMargin=margin,
        bottomMargin=margin,
        title=str(identity.get("title") or "Untitled"),
        author=str(publication.get("author") or "Unknown"),
        subject=str(identity.get("one_sentence_promise") or ""),
    )
    styles = getSampleStyleSheet()
    body = ParagraphStyle(
        "ForgeBody",
        parent=styles["BodyText"],
        fontName="ForgeSerif",
        fontSize=float(typography.get("body_size") or 10.5),
        leading=float(typography.get("leading") or 15),
        spaceAfter=7,
        orphans=2,
        widows=2,
    )
    title_style = ParagraphStyle(
        "ForgeTitle",
        parent=styles["Title"],
        fontName="ForgeSerif-Bold",
        fontSize=24,
        leading=29,
        alignment=TA_CENTER,
        textColor=colors.HexColor("#20242b"),
        spaceAfter=18,
    )
    subtitle_style = ParagraphStyle("ForgeSubtitle", parent=body, fontName="ForgeSerif-Italic", alignment=TA_CENTER, fontSize=11)
    chapter_style = ParagraphStyle(
        "ForgeChapter",
        parent=styles["Heading1"],
        fontName="ForgeSerif-Bold",
        fontSize=18,
        leading=22,
        alignment=TA_CENTER,
        spaceAfter=24,
    )
    caption_style = ParagraphStyle("ForgeCaption", parent=body, fontName="ForgeSerif-Italic", fontSize=8.5, alignment=TA_CENTER)
    break_style = ParagraphStyle("ForgeBreak", parent=body, alignment=TA_CENTER, spaceBefore=12, spaceAfter=12)
    story: list[Any] = []
    cover = assets.get("cover")
    if cover:
        image = Image(str(cover))
        max_w = page_size[0] - 2 * margin
        max_h = page_size[1] * 0.52
        scale = min(max_w / image.imageWidth, max_h / image.imageHeight)
        image.drawWidth = image.imageWidth * scale
        image.drawHeight = image.imageHeight * scale
        image.hAlign = "CENTER"
        story.extend([image, Spacer(1, 18)])
    story.append(Paragraph(html.escape(str(identity.get("title") or "Untitled")), title_style))
    if publication.get("subtitle"):
        story.append(Paragraph(html.escape(str(publication["subtitle"])), subtitle_style))
    story.extend([Spacer(1, 12), Paragraph(html.escape(str(publication.get("author") or "Unknown")), subtitle_style), PageBreak()])
    for item in publication.get("front_matter") or []:
        story.append(Paragraph(html.escape(str(item)), body))
    if publication.get("front_matter"):
        story.append(PageBreak())
    placements = {
        str(item.get("scene_id")): item
        for item in publication.get("illustration_placements") or []
        if isinstance(item, dict)
    }
    for chapter_index, chapter in enumerate(manifest.get("chapters") or [], start=1):
        if not isinstance(chapter, dict):
            continue
        if chapter_index > 1:
            story.append(PageBreak())
        story.append(Paragraph(html.escape(str(chapter.get("title") or f"Chapter {chapter_index}")), chapter_style))
        for scene_index, scene_id in enumerate(chapter.get("scene_ids") or []):
            if scene_index:
                story.append(Paragraph(html.escape(str(publication.get("scene_break_glyph") or "* * *")), break_style))
            for item in paragraphs(sections.get(str(scene_id), "")):
                story.append(Paragraph(html.escape(item), body))
            placement = placements.get(str(scene_id))
            if placement:
                key = str(placement.get("id") or scene_id)
                asset = assets.get(key)
                if asset:
                    image = Image(str(asset))
                    max_w = page_size[0] - 2 * margin
                    max_h = page_size[1] * 0.55
                    scale = min(max_w / image.imageWidth, max_h / image.imageHeight)
                    image.drawWidth = image.imageWidth * scale
                    image.drawHeight = image.imageHeight * scale
                    image.hAlign = "CENTER"
                    story.extend([Spacer(1, 10), image])
                    if placement.get("caption"):
                        story.append(Paragraph(html.escape(str(placement["caption"])), caption_style))
    if publication.get("back_matter"):
        story.append(PageBreak())
        for item in publication.get("back_matter") or []:
            story.append(Paragraph(html.escape(str(item)), body))

    def footer(canvas, document):
        canvas.saveState()
        canvas.setFont("ForgeSerif", 8)
        canvas.setFillColor(colors.HexColor("#62666d"))
        canvas.drawCentredString(page_size[0] / 2, margin * 0.45, str(document.page))
        canvas.restoreState()

    doc.build(story, onFirstPage=footer, onLaterPages=footer)


def make_pdf_contact_sheet(proofs: list[Path], out: Path) -> None:
    from PIL import Image, ImageDraw, ImageFont

    tile_w, tile_h, label_h, pad, cols = 260, 360, 28, 12, 4
    rows = max(1, (len(proofs) + cols - 1) // cols)
    canvas = Image.new("RGB", (cols * tile_w + (cols + 1) * pad, rows * (tile_h + label_h) + (rows + 1) * pad), (239, 237, 231))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    for index, proof in enumerate(proofs):
        with Image.open(proof) as source:
            image = source.convert("RGB")
            image.thumbnail((tile_w, tile_h), Image.Resampling.LANCZOS)
        x = pad + (index % cols) * (tile_w + pad)
        y = pad + (index // cols) * (tile_h + label_h + pad)
        tile = Image.new("RGB", (tile_w, tile_h), "white")
        tile.paste(image, ((tile_w - image.width) // 2, (tile_h - image.height) // 2))
        canvas.paste(tile, (x, y))
        draw.text((x + 4, y + tile_h + 7), f"Page {index + 1}", fill=(30, 30, 30), font=font)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, "PNG", dpi=(144, 144))


def verify_pdf(path: Path, proof_dir: Path, expected: list[str], publication: dict[str, Any]) -> dict[str, Any]:
    pdfinfo = shutil.which("pdfinfo")
    pdftoppm = shutil.which("pdftoppm")
    pdftotext = shutil.which("pdftotext")
    pdffonts = shutil.which("pdffonts")
    errors: list[str] = []
    pages = None
    info_output = ""
    if not pdfinfo:
        errors.append("pdfinfo was not found")
    else:
        result = subprocess.run([pdfinfo, str(path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        info_output = result.stdout
        if result.returncode != 0:
            errors.append("pdfinfo could not inspect the PDF")
        for line in result.stdout.splitlines():
            if line.startswith("Pages:"):
                pages = int(line.split(":", 1)[1].strip())
    proof_paths: list[Path] = []
    if not pdftoppm:
        errors.append("pdftoppm was not found")
    elif pages:
        proof_dir.mkdir(parents=True, exist_ok=True)
        current_proof_dir = proof_dir / sha256(path)[:12]
        current_proof_dir.mkdir(parents=True, exist_ok=True)
        prefix = current_proof_dir / "page"
        result = subprocess.run(
            [pdftoppm, "-r", "96", "-png", str(path), str(prefix)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        proof_paths = sorted(current_proof_dir.glob("page-*.png"))
        if result.returncode != 0 or len(proof_paths) != pages:
            errors.append(f"Rendered {len(proof_paths)} of {pages} PDF pages")
    contact_sheet = proof_dir / "all-pages-contact-sheet.png"
    if proof_paths:
        make_pdf_contact_sheet(proof_paths, contact_sheet)

    extracted = ""
    if not pdftotext:
        errors.append("pdftotext was not found")
    else:
        result = subprocess.run([pdftotext, str(path), "-"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        if result.returncode != 0:
            errors.append("pdftotext could not extract the PDF")
        else:
            extracted = re.sub(r"(?m)^\s*\d+\s*$", "", result.stdout)
    missing_text = text_parity_missing(expected, extracted)
    if missing_text:
        errors.append(f"PDF text extraction is missing {len(missing_text)} manuscript paragraph(s)")

    fonts_output = ""
    font_rows: list[dict[str, Any]] = []
    if not pdffonts:
        errors.append("pdffonts was not found")
    else:
        result = subprocess.run([pdffonts, str(path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        fonts_output = result.stdout
        if result.returncode != 0:
            errors.append("pdffonts could not inspect embedded fonts")
        else:
            for line in result.stdout.splitlines()[2:]:
                columns = line.split()
                if len(columns) >= 7:
                    embedded = columns[-5].lower() == "yes"
                    font_rows.append({"name": columns[0], "embedded": embedded})
                    if not embedded:
                        errors.append(f"PDF font is not embedded: {columns[0]}")

    print_settings = publication.get("print") or {}
    print_check = {"enabled": print_settings.get("enabled") is True, "trim_profile": print_settings.get("trim_profile"), "bleed_inches": print_settings.get("bleed_inches")}
    if print_check["enabled"] and print_settings.get("trim_profile") != (publication.get("typography") or {}).get("trim_profile"):
        errors.append("Print trim profile differs from the typeset PDF trim profile")
    return {
        "ok": not errors,
        "errors": errors,
        "pages": pages,
        "pdfinfo": info_output,
        "proofs": [str(item) for item in proof_paths],
        "contact_sheet": str(contact_sheet) if contact_sheet.is_file() else None,
        "text_parity": {"expected_paragraphs": len(expected), "missing": missing_text},
        "fonts": {"rows": font_rows, "raw": fonts_output},
        "print": print_check,
    }


def run_release_gate(manifest_path: Path) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="novel-release-gate-") as tmp:
        report = Path(tmp) / "gate.json"
        result = subprocess.run(
            [sys.executable, str(VALIDATOR), str(manifest_path), "--stage", "release", "--out", str(report)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        payload = json.loads(report.read_text(encoding="utf-8")) if report.is_file() else {"ok": False, "errors": [result.stdout]}
        payload["command_output"] = result.stdout
        return payload


def main() -> int:
    args = parse_args()
    manifest_path = args.manifest.expanduser().resolve()
    if args.only in {"both", "pdf"}:
        ensure_reportlab()
    manifest = load_manifest(manifest_path)
    gate = {"ok": True, "skipped": True} if args.skip_gate else run_release_gate(manifest_path)
    if gate.get("ok") is not True:
        print("Release gate failed; no publication artifacts were built")
        for error in gate.get("errors") or []:
            print(f"  [x] {error}")
        return 1
    root = manifest_path.parent
    files = manuscript_files(manifest_path, manifest)
    sections, _ = manuscript_sections(files)
    publication = manifest.get("publication") or {}
    assets = illustration_assets(root, publication)
    slug = str((manifest.get("identity") or {}).get("slug") or "novel")
    output_root = (args.output_root or root / "output").resolve()
    proof_dir = (args.proof_dir or root / "reports" / "publication-proof").resolve()
    errors: list[str] = []
    warnings: list[str] = []
    artifacts: dict[str, Any] = {}
    if args.only in {"both", "epub"}:
        epub = build_epub(output_root / "epub" / f"{slug}.epub", manifest, sections, assets)
        artifacts["epub"] = epub
        errors.extend(epub.get("errors") or [])
        if not (epub.get("epubcheck") or {}).get("available"):
            warnings.append("External EPUBCheck was not installed; internal EPUB validation and text parity still ran")
    if args.only in {"both", "pdf"}:
        pdf_path = output_root / "pdf" / f"{slug}.pdf"
        build_pdf(pdf_path, manifest, sections, assets)
        expected = [paragraph for scene in sections.values() for paragraph in paragraphs(scene)]
        verification = verify_pdf(pdf_path, proof_dir, expected, publication)
        artifacts["pdf"] = {
            "path": str(pdf_path),
            "bytes": pdf_path.stat().st_size,
            "sha256": sha256(pdf_path),
            "verification": verification,
        }
        errors.extend(verification.get("errors") or [])
    payload = {
        "schema_version": 1,
        "tool": "novel-release-builder",
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "manifest": {"path": str(manifest_path), "sha256": sha256(manifest_path)},
        "manuscript_sha256": manuscript_sha256(files),
        "release_gate": {"ok": gate.get("ok"), "requested_stage": gate.get("requested_stage")},
        "artifacts": artifacts,
    }
    report = args.report or root / "reports" / "novel-release-report.json"
    write_json(report, payload)
    print(f"Novel release report: {report}")
    for name, artifact in artifacts.items():
        print(f"{name.upper()}: {artifact['path']}")
    for warning in warnings:
        print(f"  [!] {warning}")
    for error in errors:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

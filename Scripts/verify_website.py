#!/usr/bin/env python3
"""Check the dependency-free bilingual website before publishing."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re

ROOT = Path(__file__).resolve().parent.parent / "docs"


class Page(HTMLParser):
    def __init__(self, name):
        super().__init__()
        self.name = name
        self.nodes = []
        self.text = []
        self.feed((ROOT / name).read_text())

    def handle_starttag(self, tag, attrs):
        self.nodes.append((tag, dict(attrs)))

    def handle_data(self, data):
        self.text.append(data)

    def matching(self, tag):
        return [attrs for node, attrs in self.nodes if node == tag]


pages = [Page("index.html"), Page("en.html")]
for page, language, destination in zip(pages, ["zh-CN", "en"], ["en.html", "index.html"]):
    assert page.matching("html")[0]["lang"] == language
    ids = [attrs["id"] for _, attrs in page.nodes if "id" in attrs]
    assert len(ids) == len(set(ids)), f"{page.name}: duplicate IDs"
    for tag, attrs in page.nodes:
        for key in ["href", "src"]:
            value = attrs.get(key)
            if not value:
                continue
            url = urlsplit(value)
            if url.scheme or url.netloc:
                continue
            if url.path:
                target = (ROOT / unquote(url.path)).resolve()
                assert target.is_relative_to(ROOT.resolve()) and target.is_file(), (page.name, value)
            if not url.path and url.fragment:
                assert unquote(url.fragment) in ids, (page.name, value)
        if tag == "img":
            assert "alt" in attrs and int(attrs["width"]) > 0 and int(attrs["height"]) > 0
        for key in ["aria-controls", "aria-labelledby"]:
            assert all(ref in ids for ref in attrs.get(key, "").split())
    language_links = [a for a in page.matching("a") if "data-language-link" in a]
    assert len(language_links) == 1 and language_links[0]["href"] == destination
    tabs = [a for _, a in page.nodes if a.get("role") == "tab"]
    panels = [a for _, a in page.nodes if a.get("role") == "tabpanel"]
    assert len(tabs) == len(panels) == 3
    assert sum(a.get("aria-selected") == "true" for a in tabs) == 1
    assert sum("hidden" not in a for a in panels) == 1
    assert {a["hreflang"] for a in page.matching("link") if a.get("rel") == "alternate"} == {"zh-CN", "en"}
    if language == "en":
        visible = "".join(page.text).replace("中文", "")
        assert not re.search(r"[\u4e00-\u9fff]", visible), "Untranslated English page text"
        for _, attrs in page.nodes:
            assert not re.search(r"[\u4e00-\u9fff]", "".join(attrs.get(k, "") for k in ["alt", "aria-label", "content"]))
    print(f"PASS {page.name}: language, links, accessibility, image dimensions, and tabs")

assert [a["src"] for a in pages[0].matching("img")] == [a["src"] for a in pages[1].matching("img")]
assert [a["id"] for _, a in pages[0].nodes if "id" in a] == [a["id"] for _, a in pages[1].nodes if "id" in a]
images = list((ROOT / "assets/screenshots").glob("*.webp"))
assert len(images) == 6
for image in images:
    data = image.read_bytes()
    assert data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    offset = 12
    while offset + 8 <= len(data):
        kind = data[offset:offset + 4]
        size = int.from_bytes(data[offset + 4:offset + 8], "little")
        assert kind not in [b"EXIF", b"XMP "], f"{image.name}: unexpected private metadata"
        offset += 8 + size + size % 2
print("PASS bilingual structure and six privacy-checked WebP assets")

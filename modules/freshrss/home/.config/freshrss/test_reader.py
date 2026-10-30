"""Content boundaries that must survive feed extraction and cache migration."""

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from bs4 import BeautifulSoup

import reader


class ReaderContentTests(unittest.TestCase):
    def test_active_html_and_unsafe_urls_do_not_reach_the_reader(self):
        content = '<script>alert(1)</script><p onclick="alert(2)">中文正文</p><a href="javascript:alert(3)">链接</a><img src="file:///etc/passwd" onerror="alert(4)"><iframe src="https://example.org"></iframe>'
        soup = BeautifulSoup(reader.sanitize_html(content, 'https://example.org/article'), 'html.parser')
        self.assertEqual(soup.p.get_text(), '中文正文')
        self.assertIsNone(soup.find(['script', 'iframe']))
        self.assertNotIn('onclick', soup.p.attrs)
        self.assertNotIn('href', soup.a.attrs)
        self.assertNotIn('src', soup.img.attrs)
        self.assertNotIn('onerror', soup.img.attrs)

    def test_imported_image_uses_authenticated_route_not_a_mac_path(self):
        with tempfile.TemporaryDirectory() as directory:
            images = Path(directory)
            filename = 'a' * 40 + '.png'
            (images / filename).write_bytes(b'cached-image')
            with patch.object(reader, 'IMAGES', images):
                html = reader.html_from_markdown(f'![图片](/old/cache/images/{filename})', 'https://example.org/a')
        soup = BeautifulSoup(html, 'html.parser')
        self.assertEqual(soup.img['src'], './?c=localReader&a=image&file=' + filename)
        self.assertNotIn('/old/cache', html)

    def test_split_image_link_recovers_preview_and_empty_video_gets_a_label(self):
        body = '[\n\n![预览](https://example.org/preview.png)\n\n](https://example.org/video.mp4)\n\n[](https://example.org/other.mp4)'
        soup = BeautifulSoup(reader.html_from_markdown(body, 'https://example.org/a'), 'html.parser')
        self.assertEqual(soup.img.parent['href'], 'https://example.org/video.mp4')
        self.assertEqual(soup.find('a', href='https://example.org/other.mp4').get_text(), '查看视频')
        self.assertNotIn('](https://example.org/video.mp4)', soup.get_text())

    def test_fenced_code_stays_literal_and_is_not_sent_for_translation(self):
        body = 'Introduction\n\n```markdown\n[\n\n![preview](https://example.org/p.png)\n\n](https://example.org/v.mp4)\n```\n\nConclusion'
        blocks = reader.split_blocks(body)
        self.assertEqual(len(blocks), 3)
        self.assertFalse(reader.needs_translation(blocks[1]))
        soup = BeautifulSoup(reader.html_from_markdown(body, 'https://example.org/a'), 'html.parser')
        self.assertIn('![preview](https://example.org/p.png)', soup.pre.get_text())
        self.assertIsNone(soup.pre.find('img'))

    def test_missing_translation_never_masquerades_as_a_complete_article(self):
        title, body = 'A title', 'First paragraph\n\nSecond paragraph'
        translations = {reader.key('# ' + title): '# 中文标题', reader.key('First paragraph'): '第一段'}
        self.assertIsNone(reader.translated_blocks(title, body, translations))
        translations[reader.key('Second paragraph')] = '第二段'
        self.assertEqual(reader.translated_blocks(title, body, translations), ('中文标题', '第一段\n\n第二段'))

    def test_protected_links_allow_language_reordering_without_corrupting_destinations(self):
        links = [f'[Link {i}](https://example.org/path_{i}?a=1&b=2)' for i in range(12)]
        _, targets = reader.protect_link_targets(' '.join(links))
        reordered = ' '.join(
            f'[链接 {i}](https://reader.invalid/{i})' for i in reversed(range(12))
        )
        restored = reader.restore_link_targets(reordered, targets)
        self.assertEqual(
            reader.LINK_DESTINATION.findall(restored),
            [f'https://example.org/path_{i}?a=1&b=2' for i in reversed(range(12))],
        )

    def test_missing_protected_link_fails_instead_of_publishing_a_broken_article(self):
        _, targets = reader.protect_link_targets('[First](https://example.org/1) [Second](https://example.org/2)')
        with self.assertRaisesRegex(RuntimeError, 'omitted or changed'):
            reader.restore_link_targets('[第一条](https://reader.invalid/0)', targets)


if __name__ == '__main__':
    unittest.main()

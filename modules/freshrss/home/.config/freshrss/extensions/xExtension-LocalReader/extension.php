<?php
declare(strict_types=1);

final class LocalReaderExtension extends Minz_Extension {
	public const DATA = '/var/www/FreshRSS/reader-data';

	public function init(): void {
		parent::init();
		$this->registerController('localReader');
		$this->registerHook(Minz_HookType::EntryBeforeDisplay, $this->displayEntry(...));
		$this->registerHook(Minz_HookType::EntryBeforeAdd, $this->queueEntry(...));
		$this->registerHook(Minz_HookType::EntryBeforeUpdate, $this->queueEntry(...));
		Minz_View::appendStyle($this->getFileUrl('reader.css'));
		Minz_View::appendScript($this->getFileUrl('reader.js'));
	}

	/** @return array{url:string,title:string,content:string,date:int,source_hash:string} */
	public static function source(FreshRSS_Entry $entry): array {
		$content = $entry->content(false);
		$title = $entry->title();
		return [
			'url' => $entry->link(true),
			'title' => $title,
			'content' => $content,
			'date' => (int)$entry->date(true),
			'source_hash' => hash('sha256', $title . "\n" . $content),
		];
	}

	/** @return array<string,mixed>|null */
	public static function result(string $key): ?array {
		$text = @file_get_contents(self::DATA . '/articles/' . $key . '.json');
		$value = is_string($text) ? json_decode($text, true) : null;
		return is_array($value) ? $value : null;
	}

	public static function enqueue(FreshRSS_Entry $entry, bool $retry = false): void {
		$source = self::source($entry);
		if (!preg_match('#^https?://#i', $source['url'])) {
			return;
		}
		$key = sha1($source['url']);
		$result = self::result($key);
		if (!$retry && $result !== null && ($result['source_hash'] ?? '') === $source['source_hash']) {
			return;
		}
		$path = self::DATA . '/queue/' . $key . '.json';
		if (!$retry && is_file($path)) {
			$queued = json_decode((string)file_get_contents($path), true);
			if (is_array($queued) && ($queued['source_hash'] ?? '') === $source['source_hash']) {
				return;
			}
		}
		$temp = tempnam(self::DATA . '/queue', '.queue-');
		if ($temp === false) {
			throw new RuntimeException('Cannot create reader queue file');
		}
		try {
			$json = json_encode($source, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
			if (file_put_contents($temp, $json) === false || !chmod($temp, 0664) || !rename($temp, $path)) {
				throw new RuntimeException('Cannot publish reader queue file');
			}
		} finally {
			if (is_file($temp)) {
				unlink($temp);
			}
		}
	}

	public function queueEntry(FreshRSS_Entry $entry): FreshRSS_Entry {
		self::enqueue($entry);
		return $entry;
	}

	/** @param array<string,mixed>|null $result */
	public static function fragment(FreshRSS_Entry $entry, ?array $result): string {
		$key = sha1($entry->link(true));
		$status = (string)($result['status'] ?? 'unprepared');
		if (is_file(self::DATA . '/queue/' . $key . '.json') && $status !== 'processing') {
			$status = 'pending';
		}
		$escape = static fn(string $text): string => htmlspecialchars($text, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
		$meta = $escape((string)($result['meta'] ?? ''));
		$body = (string)($result['html'] ?? $entry->content());
		$notice = match ($status) {
			'unprepared' => '打开后自动准备阅读版。',
			'pending' => '已加入后台处理队列，完成后自动显示。',
			'processing' => '正在后台准备正文或翻译，完成后自动显示。',
			'error' => '阅读版处理未完成，当前保留原文。',
			default => '',
		};
		$html = '<section class="local-reader" data-reader-key="' . $key . '" data-reader-id="' . $escape($entry->id())
			. '" data-reader-status="' . $escape($status) . '" data-reader-csrf="' . $escape(FreshRSS_Auth::csrfToken()) . '">';
		if ($meta !== '') {
			$html .= '<p class="local-reader-meta">' . $meta . '</p>';
		}
		if ($notice !== '') {
			$html .= '<p class="local-reader-notice" role="status">' . $notice;
			if ($status === 'error') {
				$html .= ' <button type="button" class="local-reader-retry">重试</button>';
			}
			$html .= '</p>';
		}
		$html .= '<div class="local-reader-body">' . $body . '</div>';
		if ($status === 'translated' && !empty($result['original_html'])) {
			$html .= '<details class="local-reader-original"><summary>查看原文</summary><h2>'
				. $escape((string)($result['original_title'] ?? '原文')) . '</h2>' . (string)$result['original_html'] . '</details>';
		}
		return $html . '</section>';
	}

	public function displayEntry(FreshRSS_Entry $entry): FreshRSS_Entry {
		$result = self::result(sha1($entry->link(true)));
		$fragment = self::fragment($entry, $result);
		if (($result['status'] ?? '') === 'translated' && !empty($result['title'])) {
			$entry->_title((string)$result['title']);
		}
		$entry->_content($fragment);
		// The reader body already includes the article images; do not append them twice.
		$entry->_attribute('enclosures', []);
		$entry->_attribute('thumbnail', []);
		return $entry;
	}
}

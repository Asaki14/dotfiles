<?php
declare(strict_types=1);

final class FreshExtension_localReader_Controller extends FreshRSS_ActionController {
	public function firstAction(): void {
		if (!FreshRSS_Auth::hasAccess() || Minz_User::name() !== 'reader') {
			http_response_code(403);
			exit;
		}
		$this->view->_layout(null);
	}

	private function entry(): FreshRSS_Entry {
		$id = Minz_Request::paramString('id');
		if (!ctype_digit($id)) {
			http_response_code(400);
			exit;
		}
		$entry = FreshRSS_Factory::createEntryDao()->searchById($id);
		if ($entry === null) {
			http_response_code(404);
			exit;
		}
		return $entry;
	}

	private function reply(FreshRSS_Entry $entry): never {
		$key = sha1($entry->link(true));
		$result = LocalReaderExtension::result($key);
		header('Content-Type: application/json; charset=UTF-8');
		header('Cache-Control: private, no-store');
		echo json_encode([
			'fragment' => LocalReaderExtension::fragment($entry, $result),
			'title' => $result['title'] ?? $entry->title(),
		], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
		exit;
	}

	public function statusAction(): void {
		$this->reply($this->entry());
	}

	public function prepareAction(): void {
		if (!Minz_Request::isPost() || !FreshRSS_Auth::isCsrfOk()) {
			http_response_code(403);
			exit;
		}
		$entry = $this->entry();
		LocalReaderExtension::enqueue($entry, Minz_Request::paramBoolean('retry'));
		$this->reply($entry);
	}

	public function imageAction(): void {
		$file = Minz_Request::paramString('file');
		if (!preg_match('/^(?:row-)?[a-f0-9]{40}\.(?:png|jpg|jpeg|gif|webp)$/D', $file)) {
			http_response_code(400);
			exit;
		}
		$path = LocalReaderExtension::DATA . '/images/' . $file;
		if (!is_file($path)) {
			http_response_code(404);
			exit;
		}
		$mime = (new finfo(FILEINFO_MIME_TYPE))->file($path);
		if (!in_array($mime, ['image/png', 'image/jpeg', 'image/gif', 'image/webp'], true)) {
			http_response_code(415);
			exit;
		}
		header('Content-Type: ' . $mime);
		header('X-Content-Type-Options: nosniff');
		header("Content-Security-Policy: default-src 'none'");
		header('Cache-Control: private, max-age=86400');
		readfile($path);
		exit;
	}
}

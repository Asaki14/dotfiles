# freshrss

[English](README.md) | [简体中文](README.zh-CN.md)

RSS 阅读与中文翻译。

## 安装

```bash
./install.sh --modules freshrss
```

在仓库根目录运行。Homebrew 依赖：`colima`、`docker`、`docker-compose`、`uv`。

## 文件与链接目标

| 源文件 | 目标 |
|---|---|
| [`home/.config/freshrss/.gitignore`](home/.config/freshrss/.gitignore) | `~/.config/freshrss/.gitignore` |
| [`home/.config/freshrss/README.md`](home/.config/freshrss/README.md) | `~/.config/freshrss/README.md` |
| [`home/.config/freshrss/compose.yaml`](home/.config/freshrss/compose.yaml) | `~/.config/freshrss/compose.yaml` |
| [`home/.config/freshrss/extensions/xExtension-LocalReader/Controllers/localReaderController.php`](home/.config/freshrss/extensions/xExtension-LocalReader/Controllers/localReaderController.php) | `~/.config/freshrss/extensions/xExtension-LocalReader/Controllers/localReaderController.php` |
| [`home/.config/freshrss/extensions/xExtension-LocalReader/extension.php`](home/.config/freshrss/extensions/xExtension-LocalReader/extension.php) | `~/.config/freshrss/extensions/xExtension-LocalReader/extension.php` |
| [`home/.config/freshrss/extensions/xExtension-LocalReader/metadata.json`](home/.config/freshrss/extensions/xExtension-LocalReader/metadata.json) | `~/.config/freshrss/extensions/xExtension-LocalReader/metadata.json` |
| [`home/.config/freshrss/extensions/xExtension-LocalReader/static/reader.css`](home/.config/freshrss/extensions/xExtension-LocalReader/static/reader.css) | `~/.config/freshrss/extensions/xExtension-LocalReader/static/reader.css` |
| [`home/.config/freshrss/extensions/xExtension-LocalReader/static/reader.js`](home/.config/freshrss/extensions/xExtension-LocalReader/static/reader.js) | `~/.config/freshrss/extensions/xExtension-LocalReader/static/reader.js` |
| [`home/.config/freshrss/reader-settings.json`](home/.config/freshrss/reader-settings.json) | `~/.config/freshrss/reader-settings.json` |
| [`home/.config/freshrss/reader.py`](home/.config/freshrss/reader.py) | `~/.config/freshrss/reader.py` |
| [`home/.config/freshrss/test_reader.py`](home/.config/freshrss/test_reader.py) | `~/.config/freshrss/test_reader.py` |

## 配置

安装器会同时选择 omp，请另行安装 omp 并登录模型服务。启动 Colima，创建共享数据目录，再启动 FreshRSS：

```bash
colima start
mkdir -p ~/.config/freshrss/reader-data/{articles,images,translations,queue}
docker-compose -f ~/.config/freshrss/compose.yaml up -d
```

打开 `http://127.0.0.1:8088` 完成 FreshRSS 初始化，创建 **`reader`** 账户，在该账户的扩展设置中启用 **Local Reader**。扩展路由只允许此账户名访问。请检查挂载目录权限，确保容器的 Web 用户能写入队列。运行 `uv run ~/.config/freshrss/reader.py` 处理排队文章。自行安排周期执行，本模块不安装导出源 README 中描述的 LaunchAgent。模型在 `reader-settings.json` 中设置，文章文本会发送给该模型服务。Docker volumes 保留订阅与阅读状态，除非明确要删除数据，否则不要运行 `down -v`。远程访问、HTTPS 与凭证需自行配置。

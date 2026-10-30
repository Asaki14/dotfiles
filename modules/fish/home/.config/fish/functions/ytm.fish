function ytm --description 'YouTube → ~/Music/inbox（Opus），再 beet import 入库'
    # 用法：ytm <url|搜索词> [更多 url]；搜索词自动走 ytsearch1
    # 需要 Chrome 登录态过 YouTube 的 bot 校验（2026-10 起无 cookie 会被拒）
    if test (count $argv) -eq 0
        echo 'ytm <url|搜索词> ...' >&2
        return 2
    end
    set -l targets
    for a in $argv
        if string match -qr '^https?://' -- $a
            set -a targets $a
        else
            set -a targets "ytsearch1:$a"
        end
    end
    # 缩略图是 16:9 视频帧，封面多数居中、两侧填色；先居中裁成正方再内嵌，
    # rmpc 的封面格才不是长方形（crop=ih:ih 取以高为边的中央正方）
    yt-dlp --cookies-from-browser chrome \
        -x --audio-format opus --audio-quality 0 \
        --embed-metadata --embed-thumbnail --no-playlist \
        --convert-thumbnails jpg \
        --ppa "ThumbnailsConvertor+ffmpeg_o:-c:v mjpeg -vf crop=ih:ih" \
        --parse-metadata 'title:^(?:.+?\s-\s)?(?P<title>[^\(\[]+?)\s*(?:[\(\[].*)?$' \
        -o "$HOME/Music/inbox/%(artist,uploader)s - %(title)s.%(ext)s" \
        $targets
    and echo "已下载到 ~/Music/inbox，入库：beet import -s ~/Music/inbox"
end

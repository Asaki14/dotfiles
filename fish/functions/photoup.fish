function photoup --description '临时上传页：手机浏览器上传照片到 ~/Pictures/Photos/收件箱，Ctrl-C 结束'
    # 同一局域网内，iPhone 打开打印出的地址并输入密码；上传时选「选项 → 全部照片数据」以保留 HEIC 原图
    set -l dir ~/Pictures/Photos/收件箱
    mkdir -p $dir
    set -l ip (ipconfig getifaddr en0)
    set -l pass (openssl rand -hex 4)
    echo "http://$ip:8080  用户名 photo  密码 $pass" >&2
    miniserve --auth photo:$pass --upload-files --port 8080 --interfaces $ip $dir
end

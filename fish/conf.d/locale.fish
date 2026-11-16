# 为未提供语言环境的终端补充 UTF-8，不覆盖已有设置。
if test -z "$LANG"
    set -gx LANG zh_CN.UTF-8
end

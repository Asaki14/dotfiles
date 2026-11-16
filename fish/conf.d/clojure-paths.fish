# Clojure 工具链缓存改到 ~/.cache，避免家目录堆 .clojure/.gitlibs/.m2
# Maven 本地仓库位置在 ~/.cache/clojure/config/deps.edn 的 :mvn/local-repo 声明
set -gx CLJ_CONFIG $HOME/.cache/clojure/config
set -gx CLJ_CACHE $HOME/.cache/clojure/cache
set -gx GITLIBS $HOME/.cache/clojure/gitlibs

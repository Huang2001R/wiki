# ============ 阶段1：编译前端 + 安装依赖 ============
FROM node:20-alpine AS build
# 国内镜像源加速：阿里云 apk 软件源 + 淘宝 npm 源（避免海外源龟速）
RUN sed -i 's#https://dl-cdn.alpinelinux.org#https://mirrors.aliyun.com#g' /etc/apk/repositories
# 编译原生模块(sqlite3等)需要 g++/make/cmake/python3；
# Python3.12 已移除 distutils，node-gyp 编译会报 "No module named distutils"，
# 因此额外装 py3-setuptools 并用清华 pip 镜像升级 setuptools 以恢复 distutils 垫片
RUN apk add --no-cache yarn g++ make cmake python3 git py3-setuptools py3-pip
RUN pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple && pip3 install --break-system-packages --upgrade setuptools
RUN yarn config set registry https://registry.npmmirror.com && npm config set registry https://registry.npmmirror.com
# 国内连 GitHub 下载预编译二进制会超时，改为全部从源码编译（依赖上面的编译工具链）
ENV npm_config_build_from_source=true
WORKDIR /wiki

# 先放依赖清单，利用 Docker 缓存加速（只有 package.json 变了才重新装）
COPY package.json yarn.lock patches/ ./
RUN yarn install --frozen-lockfile --ignore-optional --network-timeout 600000 || yarn install --ignore-optional --network-timeout 600000

# 再放源码
COPY client/ ./client
COPY server/ ./server
COPY dev/ ./dev
COPY .babelrc .eslintrc.yml .eslintignore ./

# 编译前端（node20 才支持 --openssl-legacy-provider；限制内存防止 2G 服务器编译时爆内存）
RUN NODE_OPTIONS="--openssl-legacy-provider --max-old-space-size=1024" \
    node ./node_modules/webpack/bin/webpack.js --profile --config dev/webpack/webpack.prod.js

# 换成只装“生产依赖”（去掉 devDependencies，镜像更小、启动更快）
RUN rm -rf node_modules
RUN yarn install --production --frozen-lockfile --ignore-optional --network-timeout 600000 || yarn install --production --ignore-optional --network-timeout 600000
RUN yarn patch-package

# ============ 阶段2：运行时（最终只需要这个，很小） ============
FROM node:20-alpine
RUN sed -i 's#https://dl-cdn.alpinelinux.org#https://mirrors.aliyun.com#g' /etc/apk/repositories
RUN apk add --no-cache bash curl git openssh gnupg sqlite
WORKDIR /wiki

COPY --from=build /wiki/assets ./assets
COPY --from=build /wiki/node_modules ./node_modules
COPY server/ ./server
COPY --from=build /wiki/server/views ./server/views
COPY package.json ./package.json
COPY LICENSE ./LICENSE

EXPOSE 3000
CMD ["node", "server"]

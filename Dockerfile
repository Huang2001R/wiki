# ============ 阶段1：编译前端 + 安装依赖 ============
FROM node:20-alpine AS build
# 国内镜像源加速：阿里云 apk 软件源 + 淘宝 npm 源（避免海外源龟速，2核2G 上能省几十分钟）
RUN sed -i 's#https://dl-cdn.alpinelinux.org#https://mirrors.aliyun.com#g' /etc/apk/repositories
RUN apk add --no-cache yarn g++ make cmake python3 git
RUN yarn config set registry https://registry.npmmirror.com && npm config set registry https://registry.npmmirror.com
WORKDIR /wiki

# 先放依赖清单，利用 Docker 缓存加速（只有 package.json 变了才重新装）
COPY package.json yarn.lock patches/ ./
RUN yarn install --frozen-lockfile --network-timeout 600000 || yarn install --network-timeout 600000

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
RUN yarn install --production --frozen-lockfile --network-timeout 600000 || yarn install --production --network-timeout 600000
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

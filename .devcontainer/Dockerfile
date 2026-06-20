FROM mcr.microsoft.com/devcontainers/base:alpine-3.20

RUN apk add --no-cache lua5.1 luacheck curl unzip github-cli \
    && ln -sf /usr/bin/lua5.1 /usr/local/bin/lua \
    && curl -fsSL "https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-linux-x86_64.zip" \
        -o /tmp/stylua.zip \
    && unzip /tmp/stylua.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/stylua \
    && rm /tmp/stylua.zip

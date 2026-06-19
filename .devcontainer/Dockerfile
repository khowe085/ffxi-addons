FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    lua5.1 \
    luarocks \
    unzip \
    curl \
    && ln -sf /usr/bin/lua5.1 /usr/local/bin/lua \
    && rm -rf /var/lib/apt/lists/*

RUN luarocks install luacheck

RUN curl -fsSL "https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-linux-x86_64.zip" \
    -o /tmp/stylua.zip \
    && unzip /tmp/stylua.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/stylua \
    && rm /tmp/stylua.zip

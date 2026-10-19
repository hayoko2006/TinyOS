#!/bin/sh
# TinyOS: 为 Plasma Wayland 会话设置 fcitx5 输入法环境变量
export INPUT_METHOD=fcitx
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=ibus

#!/bin/bash

echo "🔨 编译 Apple Music MIDI 控制器..."

# 编译 Swift 程序
swiftc -framework CoreAudio -framework CoreMIDI -framework AudioToolbox -framework Foundation AppleMusicMIDIController.swift -o AppleMusicMIDIController

if [ $? -eq 0 ]; then
    echo "✅ 编译成功！"
    echo "🚀 启动监控程序..."
    echo ""
    
    # 运行程序
    ./AppleMusicMIDIController
else
    echo "❌ 编译失败！"
    exit 1
fi

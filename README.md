# Apple Music MIDI 控制器

之前一周用大佬的Lossless Switcher，最近升级到了macOS 15.5之后失效了，并不会自动切换采样率。
看了一下代码和解释，大致了解了原理但完全改不来，就用Amazon Q for command line重新写了一个纯命令行的工具，在终端里直接运行就行.
第一版会自动扫描默认输出设备，但不太稳定，也不知道为啥。改了一版，增加了选择设备的交互。
AI说是1.1版那就1.1版吧，当成0.1版用就行。

## 功能特性

- 🎵 **实时监控** - 监控 Apple Music 播放时的音频格式变化
- 🔍 **设备扫描** - 自动扫描并列出所有可用的音频输出设备
- 🎯 **精确控制** - 用户可选择特定设备进行自动调整
- ⚡ **自动同步** - 根据音频格式变化自动调整设备设置
- 🎛️ **MIDI 同步** - 发送 MIDI 时钟同步消息到所有 MIDI 设备
- 📊 **详细信息** - 显示设备的采样率、位深度、通道数等信息

## 系统要求

- macOS 10.12 或更高版本
- Swift 5.0 或更高版本
- Xcode 命令行工具
- 管理员权限（用于访问系统日志）

## 安装和使用

### 1. 克隆或下载项目

```bash
git clone <repository-url>
cd AppleMusicMIDISwitcher
```

### 2. 编译项目

使用提供的构建脚本：

```bash
chmod +x build_and_run.sh
./build_and_run.sh
```

或者手动编译：

```bash
swiftc -framework CoreAudio -framework CoreMIDI -framework AudioToolbox -framework Foundation AppleMusicMIDIController.swift -o AppleMusicMIDIController
```

### 3. 运行程序

```bash
./AppleMusicMIDIController
```

## 使用说明

### 启动流程

1. **设备扫描阶段**
   ```
   🔍 扫描到以下音频设备:
   ==================================================
   1. MacBook Pro扬声器
      设备ID: 73
      当前采样率: 48000.0 Hz
      当前位深度: 16 bit
      输入通道: 0, 输出通道: 2

   2. USB Audio Device
      设备ID: 45
      当前采样率: 96000.0 Hz
      当前位深度: 24 bit
      输入通道: 2, 输出通道: 2

   请选择要自动更改设置的设备 (输入序号 1-2):
   ```

2. **选择目标设备**
   - 输入对应的序号选择要控制的音频设备
   - 如果输入无效，程序会自动使用默认输出设备

3. **开始监控**
   ```
   ✅ 已选择设备: USB Audio Device
   🎵 开始监控 Apple Music 音频格式变化...
   ```

### 监控过程

程序会每 5 秒检查一次 Apple Music 的系统日志，当检测到音频格式变化时：

```
🔄 检测到音频格式变化:
   采样率: 48000.0 Hz → 96000.0 Hz
   位深度: 16 bit → 24 bit
🎛️ 更新 MIDI 设置...
🎯 目标设备: USB Audio Device
✅ MIDI 采样率已更新为: 96000.0 Hz
✅ MIDI 位深度已更新为: 24 bit
🕐 MIDI 时钟同步消息已发送
```

## 技术原理

### 监控机制
- 使用 macOS 的 `log show` 命令监控 Apple Music 的系统日志
- 通过正则表达式解析音频格式信息（采样率和位深度）
- 基于定时器的轮询检查机制

### 音频控制
- 使用 CoreAudio 框架控制音频设备属性
- 支持动态调整采样率（44.1kHz, 48kHz, 96kHz, 192kHz 等）
- 支持位深度设置（16bit, 24bit, 32bit）

### MIDI 同步
- 使用 CoreMIDI 框架发送时钟同步消息
- 向所有连接的 MIDI 设备广播同步信号
- 发送标准 MIDI 时钟消息（0xF8）

## 支持的音频格式

| 采样率 | 位深度 | 状态 |
|--------|--------|------|
| 44.1 kHz | 16 bit | ✅ 支持 |
| 48 kHz | 16 bit | ✅ 支持 |
| 48 kHz | 24 bit | ✅ 支持 |
| 96 kHz | 24 bit | ✅ 支持 |
| 192 kHz | 24 bit | ✅ 支持 |
| 192 kHz | 32 bit | ✅ 支持 |

## 故障排除

### 常见问题

**Q: 程序提示"未找到任何音频设备"**
- A: 检查系统音频设置，确保有可用的输出设备

**Q: 无法检测到 Apple Music 格式变化**
- A: 确保 Apple Music 正在播放，并且播放的是不同格式的音频文件

**Q: 设备设置更新失败**
- A: 某些设备可能不支持特定的采样率或位深度组合

**Q: 需要管理员权限**
- A: 程序需要访问系统日志，可能需要 sudo 权限运行

### 调试模式

程序会输出详细的状态信息，包括：
- MIDI 设置状态
- 设备扫描结果
- 音频格式变化检测
- 设备设置更新结果

## 开发信息

### 项目结构
```
AppleMusicMIDISwitcher/
├── AppleMusicMIDIController.swift  # 主程序文件
├── build_and_run.sh               # 构建脚本
└── README.md                      # 项目文档
```

### 核心类和方法
- `AppleMusicMIDIController` - 主控制器类
- `selectAudioDevice()` - 设备选择界面
- `getAllAudioDevices()` - 设备扫描
- `checkAppleMusicLogs()` - 日志监控
- `updateMIDISettings()` - 设备设置更新

### 依赖框架
- `Foundation` - 基础功能和定时器
- `CoreAudio` - 音频设备控制
- `CoreMIDI` - MIDI 通信
- `AudioToolbox` - 音频格式处理

## 许可证

本项目采用 MIT 许可证。详见 LICENSE 文件。

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目。

## 更新日志

### v1.1.0
- ✨ 新增设备扫描和选择功能
- 🔧 改进用户交互界面
- 🐛 修复内存管理问题
- 📝 完善错误处理和状态提示

### v1.0.0
- 🎉 初始版本发布
- ✅ 基本的 Apple Music 监控功能
- ✅ 自动设备设置调整
- ✅ MIDI 时钟同步

---

**注意**: 此程序仅在 macOS 系统上运行，需要 Apple Music 应用程序配合使用。

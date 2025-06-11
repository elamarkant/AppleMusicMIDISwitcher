import Foundation
import CoreAudio
import CoreMIDI
import AudioToolbox

class AppleMusicMIDIController {
    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var currentSampleRate: Float64 = 0
    private var currentBitDepth: Int = 0
    private var timer: Timer?
    
    init() {
        setupMIDI()
        startMonitoring()
    }
    
    deinit {
        cleanup()
    }
    
    private func setupMIDI() {
        let status = MIDIClientCreate("AppleMusicMIDIController" as CFString, nil, nil, &midiClient)
        if status != noErr {
            print("❌ 创建 MIDI 客户端失败: \(status)")
            return
        }
        
        let portStatus = MIDIOutputPortCreate(midiClient, "Output Port" as CFString, &outputPort)
        if portStatus != noErr {
            print("❌ 创建输出端口失败: \(portStatus)")
            return
        }
        
        print("✅ MIDI 设置完成")
    }
    
    private func startMonitoring() {
        print("🎵 开始监控 Apple Music 音频格式变化...")
        
        // 每5秒检查一次
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.checkAppleMusicLogs()
        }
        
        // 立即执行一次
        checkAppleMusicLogs()
    }
    
    private func checkAppleMusicLogs() {
        let task = Process()
        task.launchPath = "/usr/bin/log"
        task.arguments = [
            "show",
            "--predicate", "subsystem contains \"com.apple.Music\" AND message contains \"asbdSampleRate\"",
            "--last", "10s",
            "--style", "compact"
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                parseLogOutput(output)
            }
        } catch {
            print("❌ 执行日志命令失败: \(error)")
        }
    }
    
    private func parseLogOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("asbdSampleRate") && line.contains("sdBitDepth") {
                if let audioInfo = extractAudioInfo(from: line) {
                    let sampleRate = audioInfo.sampleRate
                    let bitDepth = audioInfo.bitDepth
                    
                    // 检查是否有变化
                    if sampleRate != currentSampleRate || bitDepth != currentBitDepth {
                        print("🔄 检测到音频格式变化:")
                        print("   采样率: \(currentSampleRate) Hz → \(sampleRate) Hz")
                        print("   位深度: \(currentBitDepth) bit → \(bitDepth) bit")
                        
                        currentSampleRate = sampleRate
                        currentBitDepth = bitDepth
                        
                        updateMIDISettings(sampleRate: sampleRate, bitDepth: bitDepth)
                    }
                }
            }
        }
    }
    
    private func extractAudioInfo(from logLine: String) -> (sampleRate: Float64, bitDepth: Int)? {
        // 解析 asbdSampleRate = 96.0 kHz
        let sampleRatePattern = #"asbdSampleRate = ([0-9.]+) kHz"#
        let bitDepthPattern = #"sdBitDepth = ([0-9]+) bit"#
        
        guard let sampleRateRegex = try? NSRegularExpression(pattern: sampleRatePattern),
              let bitDepthRegex = try? NSRegularExpression(pattern: bitDepthPattern) else {
            return nil
        }
        
        let range = NSRange(location: 0, length: logLine.utf16.count)
        
        // 提取采样率
        guard let sampleRateMatch = sampleRateRegex.firstMatch(in: logLine, range: range),
              let sampleRateRange = Range(sampleRateMatch.range(at: 1), in: logLine),
              let sampleRateValue = Float64(logLine[sampleRateRange]) else {
            return nil
        }
        
        // 提取位深度
        guard let bitDepthMatch = bitDepthRegex.firstMatch(in: logLine, range: range),
              let bitDepthRange = Range(bitDepthMatch.range(at: 1), in: logLine),
              let bitDepthValue = Int(logLine[bitDepthRange]) else {
            return nil
        }
        
        // 转换 kHz 到 Hz
        let sampleRateHz = sampleRateValue * 1000
        
        return (sampleRate: sampleRateHz, bitDepth: bitDepthValue)
    }
    
    private func updateMIDISettings(sampleRate: Float64, bitDepth: Int) {
        print("🎛️ 更新 MIDI 设置...")
        
        // 获取默认输出设备
        guard let deviceID = getDefaultOutputDevice() else {
            print("❌ 无法获取默认输出设备")
            return
        }
        
        // 设置采样率
        if setAudioDeviceSampleRate(deviceID: deviceID, sampleRate: sampleRate) {
            print("✅ MIDI 采样率已更新为: \(sampleRate) Hz")
        } else {
            print("❌ 更新 MIDI 采样率失败")
        }
        
        // 设置位深度（如果设备支持）
        if setBitDepth(deviceID: deviceID, bitDepth: bitDepth) {
            print("✅ MIDI 位深度已更新为: \(bitDepth) bit")
        } else {
            print("⚠️ 设备可能不支持 \(bitDepth) bit 位深度")
        }
        
        // 发送 MIDI 时钟同步消息
        sendMIDIClockSync(sampleRate: sampleRate)
    }
    
    private func setAudioDeviceSampleRate(deviceID: AudioDeviceID, sampleRate: Float64) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var sampleRateValue = sampleRate
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &sampleRateValue
        )
        
        return status == noErr
    }
    
    private func setBitDepth(deviceID: AudioDeviceID, bitDepth: Int) -> Bool {
        // 尝试设置音频格式
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        
        // 先获取当前格式
        let getStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &format)
        guard getStatus == noErr else { return false }
        
        // 修改位深度
        switch bitDepth {
        case 16:
            format.mBitsPerChannel = 16
            format.mBytesPerFrame = 4  // 2 channels * 2 bytes
            format.mBytesPerPacket = 4
        case 24:
            format.mBitsPerChannel = 24
            format.mBytesPerFrame = 6  // 2 channels * 3 bytes
            format.mBytesPerPacket = 6
        case 32:
            format.mBitsPerChannel = 32
            format.mBytesPerFrame = 8  // 2 channels * 4 bytes
            format.mBytesPerPacket = 8
        default:
            return false
        }
        
        // 设置新格式
        let setStatus = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &format)
        return setStatus == noErr
    }
    
    private func sendMIDIClockSync(sampleRate: Float64) {
        // 发送 MIDI 时钟同步消息
        let count = MIDIGetNumberOfDestinations()
        
        for i in 0..<count {
            let destination = MIDIGetDestination(i)
            
            // 发送时钟同步消息 (0xF8)
            var clockMessage: [UInt8] = [0xF8]
            var packetList = MIDIPacketList()
            var packet = MIDIPacketListInit(&packetList)
            
            packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, 1, &clockMessage)
            
            if packet != nil {
                MIDISend(outputPort, destination, &packetList)
            }
        }
        
        print("🕐 MIDI 时钟同步消息已发送")
    }
    
    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        return status == noErr ? deviceID : nil
    }
    
    private func cleanup() {
        timer?.invalidate()
        timer = nil
        
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
        
        print("🛑 监控已停止")
    }
    
    func stop() {
        cleanup()
    }
}

// 主程序
print("🎵 Apple Music MIDI 控制器启动中...")
let controller = AppleMusicMIDIController()

// 保持程序运行
print("按 Ctrl+C 停止监控")
RunLoop.main.run()

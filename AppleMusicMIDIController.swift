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
    private var selectedDeviceID: AudioDeviceID?
    
    private struct AudioDeviceInfo {
        let id: AudioDeviceID
        let inputChannels: Int
        let outputChannels: Int
    }
    
    init() {
        setupMIDI()
        selectAudioDevice()
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
    
    private func selectAudioDevice() {
        let devices = getAllAudioDevices()
        
        if devices.isEmpty {
            print("❌ 未找到任何音频设备")
            return
        }
        
        print("\n🔍 扫描到以下音频设备:")
        print(String(repeating: "=", count: 50))
        
        for (index, device) in devices.enumerated() {
            let deviceName = getDeviceName(deviceID: device.id) ?? "未知设备"
            let sampleRate = getCurrentSampleRate(deviceID: device.id)
            let bitDepth = getCurrentBitDepth(deviceID: device.id)
            
            print("\(index + 1). \(deviceName)")
            print("   设备ID: \(device.id)")
            print("   当前采样率: \(sampleRate) Hz")
            print("   当前位深度: \(bitDepth) bit")
            print("   输入通道: \(device.inputChannels), 输出通道: \(device.outputChannels)")
            print("")
        }
        
        print("请选择要自动更改设置的设备 (输入序号 1-\(devices.count)):")
        
        if let input = readLine(), let choice = Int(input), choice >= 1 && choice <= devices.count {
            selectedDeviceID = devices[choice - 1].id
            let deviceName = getDeviceName(deviceID: selectedDeviceID!) ?? "未知设备"
            print("✅ 已选择设备: \(deviceName)")
        } else {
            print("❌ 无效选择，将使用默认输出设备")
            selectedDeviceID = getDefaultOutputDevice()
        }
    }
    
    private func getAllAudioDevices() -> [AudioDeviceInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        
        guard status == noErr else { return [] }
        
        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array<AudioDeviceID>(repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )
        
        guard status == noErr else { return [] }
        
        var devices: [AudioDeviceInfo] = []
        
        for deviceID in deviceIDs {
            let inputChannels = getChannelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
            let outputChannels = getChannelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
            
            // 只包含有输出通道的设备
            if outputChannels > 0 {
                devices.append(AudioDeviceInfo(
                    id: deviceID,
                    inputChannels: inputChannels,
                    outputChannels: outputChannels
                ))
            }
        }
        
        return devices
    }
    
    private func getChannelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else { return 0 }
        
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }
        
        let getStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList)
        guard getStatus == noErr else { return 0 }
        
        var channelCount = 0
        let bufferCount = Int(bufferList.pointee.mNumberBuffers)
        
        withUnsafePointer(to: &bufferList.pointee.mBuffers) { buffersPtr in
            let buffers = UnsafeBufferPointer(start: buffersPtr, count: bufferCount)
            for buffer in buffers {
                channelCount += Int(buffer.mNumberChannels)
            }
        }
        
        return channelCount
    }
    
    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else { return nil }
        
        var name: Unmanaged<CFString>?
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let deviceName = name?.takeRetainedValue() else { return nil }
        
        return deviceName as String
    }
    
    private func getCurrentSampleRate(deviceID: AudioDeviceID) -> Float64 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        return status == noErr ? sampleRate : 0
    }
    
    private func getCurrentBitDepth(deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &format)
        return status == noErr ? Int(format.mBitsPerChannel) : 0
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
    
    private func startMonitoring() {
        guard selectedDeviceID != nil else {
            print("❌ 未选择有效设备，无法开始监控")
            return
        }
        
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
        
        guard let deviceID = selectedDeviceID else {
            print("❌ 未选择有效设备")
            return
        }
        
        let deviceName = getDeviceName(deviceID: deviceID) ?? "未知设备"
        print("🎯 目标设备: \(deviceName)")
        
        // 获取当前设置用于比较
        let currentSampleRate = getCurrentSampleRate(deviceID: deviceID)
        let currentBitDepth = getCurrentBitDepth(deviceID: deviceID)
        
        print("📊 当前设置: \(currentSampleRate) Hz, \(currentBitDepth) bit")
        print("🎯 目标设置: \(sampleRate) Hz, \(bitDepth) bit")
        
        var successCount = 0
        var totalOperations = 0
        
        // 设置采样率
        if abs(currentSampleRate - sampleRate) > 1.0 {
            totalOperations += 1
            if setAudioDeviceSampleRate(deviceID: deviceID, sampleRate: sampleRate) {
                print("✅ MIDI 采样率已更新为: \(sampleRate) Hz")
                successCount += 1
            } else {
                print("❌ 更新 MIDI 采样率失败")
                // 尝试获取设备支持的采样率列表
                printSupportedSampleRates(deviceID: deviceID)
            }
        } else {
            print("ℹ️ 采样率无需更改")
        }
        
        // 设置位深度
        if currentBitDepth != bitDepth {
            totalOperations += 1
            if setBitDepth(deviceID: deviceID, bitDepth: bitDepth) {
                print("✅ MIDI 位深度已更新为: \(bitDepth) bit")
                successCount += 1
            } else {
                print("❌ 设备不支持 \(bitDepth) bit 位深度")
                printSupportedFormats(deviceID: deviceID)
            }
        } else {
            print("ℹ️ 位深度无需更改")
        }
        
        // 发送 MIDI 时钟同步消息
        sendMIDIClockSync(sampleRate: sampleRate)
        
        // 总结操作结果
        if totalOperations > 0 {
            print("📈 操作完成: \(successCount)/\(totalOperations) 成功")
        } else {
            print("ℹ️ 设备设置已是目标格式，无需更改")
        }
    }
    
    private func printSupportedSampleRates(deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else { return }
        
        let rangeCount = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = Array<AudioValueRange>(repeating: AudioValueRange(), count: rangeCount)
        
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges)
        guard status == noErr else { return }
        
        print("📋 设备支持的采样率范围:")
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                print("   - \(range.mMinimum) Hz")
            } else {
                print("   - \(range.mMinimum) - \(range.mMaximum) Hz")
            }
        }
    }
    
    private func printSupportedFormats(deviceID: AudioDeviceID) {
        print("💡 提示: 某些设备可能不支持动态位深度更改")
        print("   建议在 Audio MIDI Setup 应用中手动配置设备格式")
    }
    
    private func setAudioDeviceSampleRate(deviceID: AudioDeviceID, sampleRate: Float64) -> Bool {
        // 首先检查设备是否支持该采样率
        if !isSampleRateSupported(deviceID: deviceID, sampleRate: sampleRate) {
            print("⚠️ 设备不支持采样率 \(sampleRate) Hz")
            return false
        }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var sampleRateValue = sampleRate
        
        // 重试机制：最多尝试3次
        for attempt in 1...3 {
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float64>.size),
                &sampleRateValue
            )
            
            if status == noErr {
                // 验证设置是否成功
                Thread.sleep(forTimeInterval: 0.1) // 等待设备响应
                let actualRate = getCurrentSampleRate(deviceID: deviceID)
                if abs(actualRate - sampleRate) < 1.0 {
                    return true
                } else {
                    print("⚠️ 采样率设置验证失败，期望: \(sampleRate), 实际: \(actualRate)")
                }
            } else {
                print("⚠️ 采样率设置失败 (尝试 \(attempt)/3)，错误码: \(status)")
                if attempt < 3 {
                    Thread.sleep(forTimeInterval: 0.2) // 等待后重试
                }
            }
        }
        
        return false
    }
    
    private func isSampleRateSupported(deviceID: AudioDeviceID, sampleRate: Float64) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else { return false }
        
        let rangeCount = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = Array<AudioValueRange>(repeating: AudioValueRange(), count: rangeCount)
        
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges)
        guard status == noErr else { return false }
        
        for range in ranges {
            if sampleRate >= range.mMinimum && sampleRate <= range.mMaximum {
                return true
            }
        }
        
        return false
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
        guard getStatus == noErr else { 
            print("⚠️ 无法获取当前音频格式")
            return false 
        }
        
        // 备份原始格式
        var originalFormat = format
        
        // 修改位深度
        switch bitDepth {
        case 16:
            format.mBitsPerChannel = 16
            format.mBytesPerFrame = UInt32(format.mChannelsPerFrame * 2)
            format.mBytesPerPacket = format.mBytesPerFrame
        case 24:
            format.mBitsPerChannel = 24
            format.mBytesPerFrame = UInt32(format.mChannelsPerFrame * 3)
            format.mBytesPerPacket = format.mBytesPerFrame
        case 32:
            format.mBitsPerChannel = 32
            format.mBytesPerFrame = UInt32(format.mChannelsPerFrame * 4)
            format.mBytesPerPacket = format.mBytesPerFrame
        default:
            print("⚠️ 不支持的位深度: \(bitDepth)")
            return false
        }
        
        // 重试机制：最多尝试3次
        for attempt in 1...3 {
            let setStatus = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &format)
            
            if setStatus == noErr {
                // 验证设置是否成功
                Thread.sleep(forTimeInterval: 0.1)
                let actualBitDepth = getCurrentBitDepth(deviceID: deviceID)
                if actualBitDepth == bitDepth {
                    return true
                } else {
                    print("⚠️ 位深度设置验证失败，期望: \(bitDepth), 实际: \(actualBitDepth)")
                }
            } else {
                print("⚠️ 位深度设置失败 (尝试 \(attempt)/3)，错误码: \(setStatus)")
                if attempt < 3 {
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
        }
        
        // 如果所有尝试都失败，恢复原始格式
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &originalFormat)
        return false
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
            
            // 发送 MIDI 消息
            MIDISend(outputPort, destination, &packetList)
        }
        
        print("🕐 MIDI 时钟同步消息已发送")
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

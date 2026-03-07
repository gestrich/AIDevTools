import Foundation

final class TimerDisplay: @unchecked Sendable {
    private let maxRuntimeSeconds: Int
    private let scriptStartTime: Date
    private let lock = NSLock()
    private var phaseStartTime: Date = Date()
    private var running = false
    private static let statusLineCount = 5
    private var statusLines: [String] = []

    init(maxRuntimeSeconds: Int, scriptStartTime: Date) {
        self.maxRuntimeSeconds = maxRuntimeSeconds
        self.scriptStartTime = scriptStartTime
    }

    static func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    func setStatusLine(_ text: String) {
        lock.lock()
        statusLines.append(text)
        if statusLines.count > Self.statusLineCount {
            statusLines.removeFirst(statusLines.count - Self.statusLineCount)
        }
        lock.unlock()
    }

    func start() {
        lock.lock()
        guard !running else {
            lock.unlock()
            return
        }
        phaseStartTime = Date()
        statusLines = []
        running = true
        lock.unlock()

        let reservedLines = Self.statusLineCount + 1
        let size = terminalSize()
        if size.height > reservedLines + 1 {
            writeToStdout("\u{1B}[1;\(size.height - reservedLines)r")
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.timerLoop()
        }
    }

    func stop() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        running = false
        lock.unlock()

        usleep(100_000)

        let reservedLines = Self.statusLineCount + 1
        let size = terminalSize()
        writeToStdout("\u{1B}7")
        writeToStdout("\u{1B}[r")
        for i in 0..<reservedLines {
            writeToStdout("\u{1B}[\(size.height - i);1H\u{1B}[K")
        }
        writeToStdout("\u{1B}8")
        writeToStdout("\n")
    }

    private func timerLoop() {
        while true {
            lock.lock()
            let isRunning = running
            lock.unlock()
            guard isRunning else { break }

            updateDisplay()
            usleep(500_000)
        }
    }

    private func updateDisplay() {
        lock.lock()
        let phaseStart = phaseStartTime
        let currentLines = statusLines
        lock.unlock()

        let now = Date()
        let phaseElapsed = Int(now.timeIntervalSince(phaseStart))
        let totalElapsed = Int(now.timeIntervalSince(scriptStartTime))

        let timerText = "\u{1B}[0;36m\u{23F1}  Phase: \(Self.formatTime(phaseElapsed)) | Total: \(Self.formatTime(totalElapsed)) of \(Self.formatTime(maxRuntimeSeconds))\u{1B}[0m"

        let size = terminalSize()
        let count = Self.statusLineCount
        let firstStatusRow = size.height - count
        var output = "\u{1B}7"
        for i in 0..<count {
            let row = firstStatusRow + i
            let text: String
            if i < currentLines.count {
                let lineIndex = currentLines.count - count + i
                if lineIndex >= 0 {
                    text = "\u{1B}[0;33m\(String(currentLines[lineIndex].prefix(size.width)))\u{1B}[0m"
                } else {
                    text = ""
                }
            } else {
                text = ""
            }
            output += "\u{1B}[\(row);1H\u{1B}[K\(text)"
        }
        output += "\u{1B}[\(size.height);1H\u{1B}[K\(timerText)"
        output += "\u{1B}8"
        writeToStdout(output)
    }

    private func terminalSize() -> (width: Int, height: Int) {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_row > 0, ws.ws_col > 0 {
            return (Int(ws.ws_col), Int(ws.ws_row))
        }
        return (80, 24)
    }

    private func writeToStdout(_ str: String) {
        fputs(str, stdout)
        fflush(stdout)
    }
}

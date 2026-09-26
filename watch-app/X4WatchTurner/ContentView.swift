import SwiftUI
import WatchKit

struct ContentView: View {
    @EnvironmentObject private var bluetooth: BluetoothController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("feedbackEnabled") private var feedbackEnabled = true

    @State private var flipAmount = 0.0
    @State private var turnDirection: BluetoothController.PageCommand = .next
    @State private var turnSequence = 0
    @State private var confirmationVisible = false
    @State private var statusPulse = false
    @State private var isShowingFeedbackSettings = false
    @State private var selectedPage = ProcessInfo.processInfo.arguments.contains("--session-preview")
        ? 2
        : ProcessInfo.processInfo.arguments.contains("--book-preview") ? 1 : 0

    var body: some View {
        TabView(selection: $selectedPage) {
            remotePage
                .tag(0)

            nowReadingPage
                .tag(1)

            sessionPage
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
        .background(RemotePalette.background.ignoresSafeArea())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                statusPulse = true
            }
        }
        .sheet(isPresented: $isShowingFeedbackSettings) {
            FeedbackSettingsView(feedbackEnabled: $feedbackEnabled)
        }
    }

    private var remotePage: some View {
        GeometryReader { proxy in
            ZStack {
                RemotePalette.background
                    .ignoresSafeArea()

                Circle()
                    .fill(RemotePalette.glow)
                    .frame(width: proxy.size.width * 0.88)
                    .blur(radius: 34)
                    .offset(y: -proxy.size.height * 0.2)
                    .opacity(bluetooth.isReady ? 0.42 : 0.16)

                pageDeck
                    .frame(height: min(260, proxy.size.height * 0.62))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
    }

    private var nowReadingPage: some View {
        let snapshot = bluetooth.readerSnapshot

        return ZStack {
            dashboardGlow(color: RemotePalette.ready)

            if snapshot.hasBook {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Text("BOOK · 2/3")
                            .tracking(1.05)
                        Spacer()
                        Image(systemName: batterySymbol(for: snapshot.batteryPercent))
                        Text("\(snapshot.batteryPercent)%")
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(RemotePalette.paper.opacity(0.58))

                    Text(snapshot.title.isEmpty ? "Loading title…" : snapshot.title)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(RemotePalette.paper)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    HStack(spacing: 14) {
                        progressMedallion(snapshot.progressPercent)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("PAGE")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(0.9)
                                .foregroundStyle(RemotePalette.paper.opacity(0.46))

                            Text(pageDescription(for: snapshot))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(RemotePalette.paper)
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)

                            Text(snapshot.format == .epub ? "EPUB · CHAPTER" : "\(snapshot.format.label) · BOOK")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(RemotePalette.ready)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RemotePalette.paper.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            } else {
                emptyDashboardPage(
                    eyebrow: "BOOK · 2/3",
                    symbol: bluetooth.isReady ? "book.closed" : "antenna.radiowaves.left.and.right",
                    title: bluetooth.isReady ? "Open a book" : "Connect your X4",
                    detail: bluetooth.isReady ? "Reading details appear here." : "Return to Remote and reconnect."
                )
            }
        }
        .background(RemotePalette.background)
    }

    private var sessionPage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = sessionElapsed(at: context.date)
            let pace = readingPace(elapsed: elapsed)

            ZStack {
                dashboardGlow(color: RemotePalette.signal)

                VStack(spacing: 9) {
                    HStack {
                        Text("SESSION · 3/3")
                            .tracking(1.05)
                        Spacer()
                        Circle()
                            .fill(bluetooth.isReady ? RemotePalette.ready : RemotePalette.warning)
                            .frame(width: 6, height: 6)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(RemotePalette.paper.opacity(0.58))

                    VStack(spacing: 1) {
                        Text("READING TIME")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1.1)
                            .foregroundStyle(RemotePalette.paper.opacity(0.42))

                        Text(durationText(elapsed))
                            .font(.system(size: 29, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(RemotePalette.paper)
                    }

                    HStack(spacing: 7) {
                        sessionStat(value: "\(bluetooth.forwardTurns)", label: "FORWARD", symbol: "arrow.right")
                        sessionStat(value: "\(bluetooth.backwardTurns)", label: "BACK", symbol: "arrow.left")
                        sessionStat(value: pace, label: "PAGES/HR", symbol: "speedometer")
                    }

                    Button {
                        bluetooth.resetSession()
                    } label: {
                        Label("Reset session", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RemotePalette.signal)
                    .accessibilityHint("Clears the reading timer and page-turn counts")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .background(RemotePalette.background)
        }
    }

    private var pageDeck: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(RemotePalette.paper.opacity(0.16))
                .offset(y: 7)
                .padding(.horizontal, 9)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(RemotePalette.paper.opacity(0.28))
                .offset(y: 4)
                .padding(.horizontal, 4)

            Button {
                send(.next)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(RemotePalette.paper)

                    pageGrain

                    VStack(spacing: 4) {
                        HStack {
                            Text(cardEyebrow)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.1)
                            Spacer()
                            Text("X4")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .padding(.trailing, 28)
                        }
                        .foregroundStyle(RemotePalette.ink.opacity(0.55))

                        Spacer(minLength: 0)

                        ZStack {
                            Circle()
                                .fill(RemotePalette.ink.opacity(0.055))
                                .frame(width: 58, height: 58)
                                .scaleEffect(isSearching && statusPulse ? 1.12 : 1)

                            Image(systemName: cardSymbol)
                                .font(.system(size: 29, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .foregroundStyle(RemotePalette.ink)

                        Text(cardTitle)
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .foregroundStyle(RemotePalette.ink)
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        HStack(spacing: 5) {
                            Image(systemName: bluetooth.isReady ? "hand.tap.fill" : "antenna.radiowaves.left.and.right")
                            Text(cardInstruction)
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.75)
                        .foregroundStyle(RemotePalette.ink.opacity(0.58))
                        .padding(.bottom, 16)
                    }
                    .padding(13)

                    PageFold()
                        .fill(RemotePalette.signal)
                        .frame(width: 27, height: 27)
                        .opacity(bluetooth.isReady ? 1 : 0.34)

                    if confirmationVisible {
                        Text(turnDirection == .next ? "TURNED →" : "← BACK")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(RemotePalette.paper)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RemotePalette.ink, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PagePressButtonStyle())
            .handGestureShortcut(.primaryAction)
            .disabled(!bluetooth.isReady)
            .accessibilityLabel("Next page")
            .accessibilityHint("Double tap your fingers or tap the screen")
            .rotation3DEffect(
                .degrees(flipAmount * (turnDirection == .next ? -24 : 24)),
                axis: (x: 0, y: 1, z: 0),
                anchor: turnDirection == .next ? .leading : .trailing,
                perspective: 0.55
            )
            .offset(x: flipAmount * (turnDirection == .next ? 22 : -22))
            .scaleEffect(1 - (flipAmount * 0.035))
            .opacity(1 - (flipAmount * 0.34))

            Button {
                isShowingFeedbackSettings = true
            } label: {
                Image(systemName: feedbackEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RemotePalette.ink.opacity(0.68))
                    .frame(width: 30, height: 30)
                    .background(RemotePalette.paper.opacity(0.92), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(RemotePalette.ink.opacity(0.08), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 7)
            .padding(.trailing, 8)
            .accessibilityLabel("Feedback settings")
            .accessibilityValue(feedbackEnabled ? "Sound and haptics on" : "Silent")

            floatingControl
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: 11)
        }
        .frame(maxHeight: .infinity)
    }

    private var pageGrain: some View {
        Canvas { context, size in
            for index in 0..<7 {
                let y = size.height * (0.15 + (Double(index) * 0.105))
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.11, y: y))
                path.addLine(to: CGPoint(x: size.width * 0.89, y: y))
                context.stroke(path, with: .color(RemotePalette.ink.opacity(0.025)), lineWidth: 0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .allowsHitTesting(false)
    }

    private func dashboardGlow(color: Color) -> some View {
        Circle()
            .fill(color.opacity(bluetooth.isReady ? 0.2 : 0.08))
            .frame(width: 170, height: 170)
            .blur(radius: 42)
            .offset(y: -72)
            .allowsHitTesting(false)
    }

    private func progressMedallion(_ percent: Int) -> some View {
        ZStack {
            Circle()
                .stroke(RemotePalette.paper.opacity(0.1), lineWidth: 6)

            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(percent, 100))) / 100)
                .stroke(
                    RemotePalette.ready,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: -2) {
                Text("\(percent)")
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .monospacedDigit()
                Text("PERCENT")
                    .font(.system(size: 6, weight: .heavy, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(RemotePalette.paper.opacity(0.45))
            }
            .foregroundStyle(RemotePalette.paper)
        }
        .frame(width: 68, height: 68)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Book progress")
        .accessibilityValue("\(percent) percent")
    }

    private func emptyDashboardPage(
        eyebrow: String,
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(spacing: 12) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.05)
                .foregroundStyle(RemotePalette.paper.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(RemotePalette.signal)

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(RemotePalette.paper)
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(RemotePalette.paper.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func sessionStat(value: String, label: String, symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(RemotePalette.signal)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(RemotePalette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 6, weight: .heavy, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(RemotePalette.paper.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 55)
        .background(RemotePalette.paper.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func batterySymbol(for percent: Int) -> String {
        switch percent {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        case 1...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func pageDescription(for snapshot: BluetoothController.ReaderSnapshot) -> String {
        guard snapshot.currentPage > 0 else { return "Preparing…" }
        guard snapshot.totalPages > 0 else { return "\(snapshot.currentPage)" }
        return "\(snapshot.currentPage) / \(snapshot.totalPages)"
    }

    private func sessionElapsed(at date: Date) -> TimeInterval {
        guard let start = bluetooth.sessionStartedAt else { return 0 }
        return max(0, date.timeIntervalSince(start))
    }

    private func durationText(_ elapsed: TimeInterval) -> String {
        let seconds = Int(elapsed)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func readingPace(elapsed: TimeInterval) -> String {
        guard elapsed >= 60, bluetooth.forwardTurns > 0 else { return "—" }
        return "\(Int((Double(bluetooth.forwardTurns) * 3_600 / elapsed).rounded()))"
    }

    @ViewBuilder
    private var floatingControl: some View {
        if bluetooth.isReady {
            Button {
                send(.previous)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left")
                    Text("Previous")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(RemotePalette.paper)
                .background(RemotePalette.ink, in: Capsule())
                .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                bluetooth.reconnect()
                playFeedback(.start)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Search again")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(RemotePalette.ink)
                .background(RemotePalette.signal, in: Capsule())
                .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search again")
        }
    }

    private var isSearching: Bool {
        bluetooth.state == .scanning || bluetooth.state == .connecting
    }

    private var cardEyebrow: String {
        switch bluetooth.state {
        case .connected: return "READER READY"
        case .scanning: return "SEARCHING"
        case .connecting: return "PAIRING"
        case .disconnected: return "NOT FOUND"
        case .bluetoothUnavailable: return "BLUETOOTH OFF"
        }
    }

    private var cardTitle: String {
        switch bluetooth.state {
        case .connected: return "Next page"
        case .scanning: return "Finding X4"
        case .connecting: return "Almost there"
        case .disconnected: return "Wake your X4"
        case .bluetoothUnavailable: return "Bluetooth off"
        }
    }

    private var cardInstruction: String {
        switch bluetooth.state {
        case .connected: return "DOUBLE TAP"
        case .scanning, .connecting: return "KEEP X4 AWAKE"
        case .disconnected: return "TAP RETRY"
        case .bluetoothUnavailable: return "ENABLE TO CONNECT"
        }
    }

    private var cardSymbol: String {
        switch bluetooth.state {
        case .connected: return "arrow.right"
        case .scanning, .connecting: return "antenna.radiowaves.left.and.right"
        case .disconnected: return "moon.zzz"
        case .bluetoothUnavailable: return "bluetooth.slash"
        }
    }

    private func send(_ command: BluetoothController.PageCommand) {
        guard bluetooth.send(command) else {
            playFeedback(.failure)
            return
        }

        turnDirection = command
        turnSequence += 1
        let sequence = turnSequence

        playFeedback(command == .next ? .directionUp : .directionDown)

        withAnimation(.easeOut(duration: reduceMotion ? 0.06 : 0.13)) {
            confirmationVisible = true
            flipAmount = reduceMotion ? 0.08 : 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 70 : 145))
            guard sequence == turnSequence else { return }

            withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.34, dampingFraction: 0.72)) {
                flipAmount = 0
            }

            try? await Task.sleep(for: .milliseconds(520))
            guard sequence == turnSequence else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                confirmationVisible = false
            }
        }
    }

    private func playFeedback(_ type: WKHapticType) {
        guard feedbackEnabled else { return }
        WKInterfaceDevice.current().play(type)
    }
}

private struct FeedbackSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var feedbackEnabled: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(RemotePalette.signal.opacity(0.16))
                        .frame(width: 42, height: 42)

                    Image(systemName: feedbackEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(RemotePalette.signal)
                        .contentTransition(.symbolEffect(.replace))
                }

                VStack(spacing: 3) {
                    Text("Feedback")
                        .font(.system(size: 18, weight: .semibold, design: .serif))

                    Text(feedbackEnabled ? "Feel every page turn" : "Page turns are silent")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Toggle(isOn: $feedbackEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sound & haptics")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text(feedbackEnabled ? "On" : "Off")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(RemotePalette.signal)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(RemotePalette.paper.opacity(0.1), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(RemotePalette.signal)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
        }
        .background(RemotePalette.background.ignoresSafeArea())
    }
}

private enum RemotePalette {
    static let background = Color(red: 0.055, green: 0.059, blue: 0.078)
    static let paper = Color(red: 0.94, green: 0.93, blue: 0.89)
    static let ink = Color(red: 0.10, green: 0.105, blue: 0.13)
    static let signal = Color(red: 0.46, green: 0.62, blue: 1.0)
    static let ready = Color(red: 0.43, green: 0.88, blue: 0.67)
    static let warning = Color(red: 1.0, green: 0.67, blue: 0.36)
    static let glow = Color(red: 0.24, green: 0.31, blue: 0.63)
}

private struct PageFold: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PagePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

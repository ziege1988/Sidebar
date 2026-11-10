import AppKit
import SwiftUI

// MARK: - Startbild beim (Neu-)Start der Sidebar
//
// Erscheint mittig auf dem Bildschirm, wenn die Sidebar neu gestartet wird (nach dem Beenden,
// nach einem Update, „Sidebar neu starten“) – nicht beim Hochfahren des Macs.

@MainActor
final class SplashController {
    static let shared = SplashController()
    private var panel: NSPanel?


    func show(settings: SidebarSettings, version: String) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = NSSize(width: 360, height: 300)
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.appearance = settings.appearance.nsAppearance
        let host = NSHostingView(rootView: SplashView(theme: settings.colorTheme, version: version,
                                                      showCat: settings.catEnabled))
        host.sizingOptions = []
        panel.contentView = host
        let area = screen.visibleFrame
        panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2 + 40,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                self?.panel = nil
            }
        })
    }
}

struct SplashView: View {
    let theme: ColorTheme
    let version: String
    let showCat: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false
    private let start = Date()

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        let dark = scheme == .dark
        VStack(spacing: 10) {
            if showCat {
                ZStack {
                    Circle().fill(palette.accent.opacity(dark ? 0.35 : 0.45)).blur(radius: 7).padding(-4)
                    Circle().fill(Color.white.opacity(dark ? 0.08 : 0.88))
                    Circle().fill(RadialGradient(colors: [Color.white.opacity(dark ? 0.12 : 0.5), palette.accent.opacity(dark ? 0.5 : 0.55)],
                                                 center: UnitPoint(x: 0.45, y: 0.36), startRadius: 2, endRadius: 70))
                    // Rüdiger winkt
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        if let image = CatSprites.shared.image("ask", at: timeline.date.timeIntervalSince(start)) {
                            Image(nsImage: image).resizable().interpolation(.high)
                                .frame(width: 110 * CGFloat(CatSprites.shared.span("ask")),
                                       height: 110 * CGFloat(CatSprites.shared.span("ask")))
                        }
                    }
                }
                .frame(width: 110, height: 110)
                .padding(.top, 6)
            }
            Text(showCat ? "Rüdigers Sidebar" : "Sidebar")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.text)
            Text("dezent · funktional · übersichtlich")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.secondary)
            Text("Version \(version)")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(palette.secondary.opacity(0.8))
                .padding(.top, 2)
        }
        .padding(.vertical, 22)
        .frame(width: 320)
        .background(
            ZStack {
                VisualEffectBackground(mask: AnyShape(RoundedRectangle(cornerRadius: 26, style: .continuous)), opacity: 1)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(palette.panelFill(gradient: true))
                    .opacity(0.82)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(Color.white.opacity(dark ? 0.18 : 0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        .scaleEffect(appeared ? 1 : 0.94)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorTheme, theme)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { appeared = true }
        }
    }
}

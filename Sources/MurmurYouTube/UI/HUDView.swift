import SwiftUI

/// Brand palette. The orb's three hues — everything else in the app stays neutral, so this
/// is the only place colour actually moves. Backed by `Settings` (user-customizable in
/// Ustawienia ▸ Kolory) rather than fixed constants, with the original blue/violet/cyan as
/// the shipped default — every read goes through `Settings.shared`, so a color change is
/// visible the instant it's picked, same as any other `@Observable` setting.
@MainActor
enum Brand {
    static var accent: Color { Settings.shared.accentPrimary.color }
    static var accentWarm: Color { Settings.shared.accentSecondary.color }
    static var accentCool: Color { Settings.shared.accentTertiary.color }
    static let error = Color(red: 1.0, green: 0.42, blue: 0.38)
    static let errorWarm = Color(red: 1.0, green: 0.64, blue: 0.32)

    /// The orb's palette while "dyktuj i przetłumacz" is armed — a different set of three so
    /// it reads at a glance which mode is running, no text needed.
    static var accentTranslate: Color { Settings.shared.translateAccentPrimary.color }
    static var accentTranslateWarm: Color { Settings.shared.translateAccentSecondary.color }
    static var accentTranslateCool: Color { Settings.shared.translateAccentTertiary.color }

    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accentWarm], startPoint: .leading, endPoint: .trailing)
    }

    /// The three defaults, for the "Przywróć domyślne" button in color settings.
    static let defaultPrimary = RGBColor(r: 0.42, g: 0.55, b: 1.0)
    static let defaultSecondary = RGBColor(r: 0.76, g: 0.47, b: 1.0)
    static let defaultTertiary = RGBColor(r: 0.40, g: 0.85, b: 0.92)

    /// Green/amber, deliberately far from the blue/violet default so the two are never
    /// mistaken for each other even at a glance.
    static let defaultTranslatePrimary = RGBColor(r: 0.30, g: 0.78, b: 0.48)
    static let defaultTranslateSecondary = RGBColor(r: 0.96, g: 0.78, b: 0.25)
    static let defaultTranslateTertiary = RGBColor(r: 0.35, g: 0.85, b: 0.70)
}

/// The floating indicator while you hold the key: just the orb, no card, no pill, no bar
/// behind it. Parakeet doesn't stream text while you talk — there's nothing to caption —
/// so the chrome that used to hold a live transcript was doing nothing but announcing
/// "an app is here." A naked orb reads as a live indicator, not a window.
///
/// The one exception is an error: that genuinely has something to say, so it gets a plain
/// text line under the orb — no background box, just white-on-shadow so it holds up over
/// any desktop wallpaper.
struct HUDView: View {
    @Bindable var controller: DictationController

    static let size = CGSize(width: 300, height: 150)
    private static let orbSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 14) {
            SiriOrb(
                energy: energy, isAnimating: isAnimating, isError: isError,
                isTranslating: controller.wantsTranslate, size: Self.orbSize
            )

            if isError {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                    .frame(maxWidth: Self.size.width - 24)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var isAnimating: Bool {
        if case .idle = controller.state { return false }
        return true
    }

    /// 0…1: jak "pobudzona" jest kula w danej chwili. Idle nie ma tu wpływu (orb jest
    /// wtedy ukryty razem z całym HUD-em); starting delikatnie się rozgrzewa; listening
    /// jedzie na poziomie mikrofonu (Parakeet nie pokazuje tekstu na żywo, ale poziom
    /// głosu jest mierzony w czasie rzeczywistym niezależnie od silnika transkrypcji);
    /// finishing zostaje żywe mimo braku dźwięku, żeby nie wyglądało na zamrożone w
    /// trakcie transkrypcji.
    private var energy: CGFloat {
        switch controller.state {
        case .idle: 0
        case .starting: 0.16
        case .listening: 0.22 + CGFloat(max(0, min(controller.level, 1))) * 0.85
        case .finishing: 0.32
        case .error: 0.22
        }
    }

    private var isError: Bool {
        if case .error = controller.state { return true }
        return false
    }

    private var errorMessage: String {
        if case .error(let message) = controller.state { return message }
        return ""
    }
}

/// Miękka, świetlista kula w duchu Siri. Trzy rozmyte, przenikające się plamy koloru krążą
/// wokół środka ("sztuczka metaballi", która czyta się jako jedna płynna bryła zamiast
/// trzech kółek) i pulsują razem z poziomem energii; jasny rdzeń w środku daje jej wagę
/// zamiast być tylko poświatą.
///
/// Odsprzęgnięta od `DictationController.State` na czystym `energy`/`isAnimating`/`isError`
/// — dzięki temu ten sam komponent obsługuje HUD dyktowania, miernik poziomu w oknie
/// głównym i HUD chwytania tekstu, każdy licząc swoje "pobudzenie" po swojemu.
struct SiriOrb: View {
    var energy: CGFloat
    var isAnimating: Bool
    var isError: Bool = false
    /// True while the recording in flight is armed to be translated — swaps in
    /// `Brand.accentTranslate*` instead of the usual palette.
    var isTranslating: Bool = false
    var size: CGFloat = 44

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                glow
                blobs(at: t)
                core
            }
            .frame(width: size, height: size)
            .compositingGroup()
            .scaleEffect(0.86 + energy * 0.22)
            .animation(.easeOut(duration: 0.12), value: energy)
        }
    }

    private var palette: [Color] {
        if isError { return [Brand.error, Brand.errorWarm, Brand.errorWarm] }
        if isTranslating { return [Brand.accentTranslate, Brand.accentTranslateWarm, Brand.accentTranslateCool] }
        return [Brand.accent, Brand.accentWarm, Brand.accentCool]
    }

    private var glow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [palette[0].opacity(0.5), palette[1].opacity(0.18), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.78
                )
            )
            .frame(width: size * 1.7, height: size * 1.7)
            .blur(radius: size * 0.2)
            .opacity(0.55 + energy * 0.45)
    }

    /// Three blurred discs orbiting the centre at slightly different speeds and radii —
    /// close enough together that they read as one soft, morphing blob rather than
    /// separate circles. `Settings.orbSpread` scales how far energy pushes them outward —
    /// "rozpiętość" in Ustawienia: low values keep the blob tight and calm even when
    /// shouting, high values fork it wide open on a whisper.
    private func blobs(at t: TimeInterval) -> some View {
        let spread = Settings.shared.orbSpread
        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                let phase = Double(index) / 3.0 * 2 * .pi
                let speed = 0.5 + Double(index) * 0.22
                let angle = t * speed + phase
                let orbitRadius = size * (0.10 + 0.05 * Double(index)) * (1 + Double(energy) * spread)
                let diameter = size * (0.66 - CGFloat(index) * 0.08)

                Circle()
                    .fill(palette[index % palette.count].opacity(0.9))
                    .frame(width: diameter, height: diameter)
                    .offset(
                        x: CGFloat(cos(angle)) * orbitRadius,
                        y: CGFloat(sin(angle)) * orbitRadius
                    )
                    .blur(radius: size * 0.136)
                    .blendMode(.plusLighter)
            }
        }
        .scaleEffect(0.92 + energy * 0.3)
    }

    private var core: some View {
        Circle()
            .fill(.white.opacity(0.9))
            .frame(width: size * (0.18 + energy * 0.08), height: size * (0.18 + energy * 0.08))
            .blur(radius: size * 0.057)
    }
}

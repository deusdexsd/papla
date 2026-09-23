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

    /// The waveform visualizer's own three colors — deliberately a separate setting from the
    /// orb's `accent*` above, so customizing one never drags the other along with it.
    static var waveformAccent: Color { Settings.shared.waveformAccentPrimary.color }
    static var waveformAccentWarm: Color { Settings.shared.waveformAccentSecondary.color }
    static var waveformAccentCool: Color { Settings.shared.waveformAccentTertiary.color }
    static var waveformAccentTranslate: Color { Settings.shared.waveformTranslateAccentPrimary.color }
    static var waveformAccentTranslateWarm: Color { Settings.shared.waveformTranslateAccentSecondary.color }
    static var waveformAccentTranslateCool: Color { Settings.shared.waveformTranslateAccentTertiary.color }

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

    /// A cyan/teal/pink family, deliberately distinct from the orb's blue/violet — the two
    /// visualizers read as different things even before anyone customizes either.
    static let defaultWaveformPrimary = RGBColor(r: 0.30, g: 0.85, b: 0.95)
    static let defaultWaveformSecondary = RGBColor(r: 0.55, g: 0.60, b: 1.0)
    static let defaultWaveformTertiary = RGBColor(r: 0.95, g: 0.45, b: 0.80)

    static let defaultWaveformTranslatePrimary = defaultTranslatePrimary
    static let defaultWaveformTranslateSecondary = defaultTranslateSecondary
    static let defaultWaveformTranslateTertiary = defaultTranslateTertiary
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
            VisualizerView(
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

/// Picks the orb or the waveform per `Settings.hudVisualizerStyle` — the one place any of the
/// three call sites (dictation HUD, main window's level meter, grab HUD) need to touch, so
/// adding a third style later only means adding a case here.
struct VisualizerView: View {
    var energy: CGFloat
    var isAnimating: Bool
    var isError: Bool = false
    var isTranslating: Bool = false
    var size: CGFloat = 44

    var body: some View {
        switch Settings.shared.hudVisualizerStyle {
        case .orb:
            SiriOrb(energy: energy, isAnimating: isAnimating, isError: isError, isTranslating: isTranslating, size: size)
        case .waveform:
            WaveformVisualizer(energy: energy, isAnimating: isAnimating, isError: isError, isTranslating: isTranslating, size: size)
        }
    }
}

/// A borderless plasma streak, not a bar chart: no fixed start/end point, no frame the wave
/// bumps up against. Amplitude is architecturally zero at both edges and maximal in the
/// middle — the shape *is* the fade, not a mask applied to one — so it always reads as a
/// glowing thread suspended in the interface rather than a chart with axes.
///
/// Every band reacts to the *current* mic level simultaneously (fast attack, slower decay,
/// like a real VU meter), each scaled by its own fixed "character" multiplier for organic
/// variation across the width — not a scrolling history buffer. A history buffer draws
/// yesterday's loud moment as a hump that visibly *travels* across the view as time passes,
/// which reads as sluggish and disconnected from what's happening right now; this instead
/// snaps the whole shape up together the instant the mic gets louder, the way an actual
/// live waveform (Siri, a voice memo app, anything reacting to sound in real time) does.
///
/// A soft blurred glow layer sits under a crisp particle layer for depth, echoing the same
/// light-through-fog look as `SiriOrb`'s own glow. At rest it never goes fully flat — a slow,
/// quiet undulation keeps it reading as alive rather than off. Same
/// `energy`/`isAnimating`/`isError`/`isTranslating` inputs as `SiriOrb`, so `VisualizerView`
/// can swap between the two without either caller knowing which one it got.
struct WaveformVisualizer: View {
    var energy: CGFloat
    var isAnimating: Bool
    var isError: Bool = false
    var isTranslating: Bool = false
    var size: CGFloat = 44

    private static let bandCount = 40
    @State private var bandLevels = Array(repeating: CGFloat(0), count: bandCount)

    /// A fixed, deterministic per-band multiplier (not random per-frame — the same band is
    /// always a little louder or quieter than its neighbor) so the wave has organic, scattered
    /// texture instead of every band snapping to the exact same height. Wide range (down to
    /// 0.2, up past 1) on purpose — a narrow range reads as a tame, uniform ripple; this reads
    /// as genuinely reactive and a little chaotic, the way a real spectrum does.
    private static let bandCharacter: [CGFloat] = (0..<bandCount).map { i in
        let x = sin(Double(i) * 12.9898) * 43758.5453
        let fraction = x - floor(x)
        return CGFloat(0.2 + fraction * 1.3)
    }

    /// Waveform colors are independent of the orb's own `accent*` — a separate Ustawienia
    /// setting, so customizing one never touches the other.
    private var palette: [Color] {
        if isError { return [Brand.error, Brand.errorWarm] }
        if isTranslating {
            return [Brand.waveformAccentTranslate, Brand.waveformAccentTranslateWarm, Brand.waveformAccentTranslateCool]
        }
        return [Brand.waveformAccent, Brand.waveformAccentWarm, Brand.waveformAccentCool]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            Canvas { context, canvasSize in
                draw(into: &context, canvasSize: canvasSize, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        // Taller than the wave's own amplitude on purpose — the glow needs headroom above and
        // below the line's peak or it visibly clips against the view's own bounds the moment
        // the mic gets loud. Shorter horizontally than the first pass — the long version read
        // as an oversized, slow-feeling shape rather than a compact reactive one.
        .frame(width: size * 2.3, height: size * 1.4)
        .onChange(of: energy) { _, newValue in
            guard isAnimating else { return }
            // A bit of gain above 1 on purpose — a raised peak reads as punchier and more
            // reactive; edgeEnvelope and the draw-time scale still keep it from ever
            // overflowing the frame.
            let clamped = max(0, min(1, newValue)) * 1.3
            for i in 0..<Self.bandCount {
                let target = clamped * Self.bandCharacter[i]
                // Fast attack (snap straight to a louder target), quicker decay than before —
                // the same asymmetry a real VU meter uses so peaks read instantly and the
                // motion doesn't linger, staying tightly tied to what's happening right now.
                bandLevels[i] = target > bandLevels[i] ? target : bandLevels[i] + (target - bandLevels[i]) * 0.5
            }
        }
        .onChange(of: isAnimating) { _, animating in
            guard !animating else { return }
            bandLevels = Array(repeating: 0, count: Self.bandCount)
        }
    }

    /// 0 at both edges, 1 at the center — this is what guarantees "no point A or B": every
    /// term below (the core line, the glow, the particle density) is multiplied by this, so
    /// nothing the mic does can ever put a hard edge anywhere but the exact middle.
    private func edgeEnvelope(_ unit: CGFloat) -> CGFloat {
        let distanceFromCenter = abs(unit - 0.5) * 2
        return max(0, 1 - pow(distanceFromCenter, 1.7))
    }

    private func draw(into context: inout GraphicsContext, canvasSize: CGSize, time: TimeInterval) {
        let midY = canvasSize.height / 2
        let n = Self.bandCount
        // Never truly silent: a slow, low breathing term so a quiet mic still reads as a
        // living, softly waving line rather than a dead flat one.
        let breathing = 0.05 + 0.035 * sin(time * 0.8)
        // Room for the glow to bleed past the line's own peak without hitting the canvas edge.
        let amplitudeScale = canvasSize.height * 0.3

        func amplitude(at index: Int) -> CGFloat {
            let unit = CGFloat(index) / CGFloat(n - 1)
            let wobble = 1 + sin(time * 2.2 + Double(index) * 0.4) * 0.1
            let raw = (bandLevels[index] + breathing) * edgeEnvelope(unit) * CGFloat(wobble)
            return min(1, raw) // headroom guarantee: never lets the extra gain push past the frame
        }

        var corePath = Path()
        for i in 0..<n {
            let unit = CGFloat(i) / CGFloat(n - 1)
            let x = unit * canvasSize.width
            let y = midY - amplitude(at: i) * amplitudeScale
            if i == 0 { corePath.move(to: CGPoint(x: x, y: y)) } else { corePath.addLine(to: CGPoint(x: x, y: y)) }
        }

        // A bloom from the center, not a left/right split: transparent at both ends, ramping
        // through all three palette colors and peaking at the middle. The two inner stops'
        // positions drift slowly over time — the same "always a little in motion" quality as
        // the orb's own orbiting blobs, just expressed as color travelling along the line
        // instead of blobs travelling around a circle.
        let drift = sin(time * 0.35) * 0.06
        let third = palette.count > 2 ? palette[2] : palette[0]
        let second = palette.count > 1 ? palette[1] : palette[0]
        let gradient = Gradient(stops: [
            .init(color: palette[0].opacity(0), location: 0),
            .init(color: palette[0], location: 0.32 + drift),
            .init(color: second, location: 0.5),
            .init(color: third, location: 0.68 - drift),
            .init(color: third.opacity(0), location: 1),
        ])
        let start = CGPoint(x: 0, y: midY)
        let end = CGPoint(x: canvasSize.width, y: midY)

        // Deep, wide, blurred glow — the diffuse "fog" layer.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: size * 0.16))
            layer.stroke(corePath, with: .linearGradient(gradient, startPoint: start, endPoint: end), lineWidth: size * 0.16)
        }
        // A second, tighter glow pass for depth between the fog and the crisp line.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: size * 0.05))
            layer.stroke(corePath, with: .linearGradient(gradient, startPoint: start, endPoint: end), lineWidth: size * 0.07)
        }
        // The crisp, sharp core registering the actual micro-movement.
        context.stroke(corePath, with: .linearGradient(gradient, startPoint: start, endPoint: end), lineWidth: size * 0.025)

        // Volumetric dust: a scatter of tiny points hugging the line, denser and brighter
        // near the center and on louder samples — the "3D particle cloud" around the core.
        for i in 0..<n {
            let unit = CGFloat(i) / CGFloat(n - 1)
            let env = edgeEnvelope(unit)
            guard env > 0.02 else { continue }
            let amp = amplitude(at: i)
            let x = unit * canvasSize.width
            let y = midY - amp * amplitudeScale
            let particleCount = Int(1 + env * (2 + amp * 5))
            for p in 0..<particleCount {
                let seed = Double(i * 37 + p * 11)
                let jx = x + CGFloat(sin(time * 1.7 + seed)) * size * 0.06 * env
                let jy = y + CGFloat(cos(time * 2.3 + seed * 1.4)) * size * (0.04 + amp * 0.1) * env
                let dotSize = size * (0.012 + amp * 0.02) * (0.6 + env * 0.4)
                let opacity = (0.12 + amp * 0.5) * env
                let dot = CGRect(x: jx - dotSize / 2, y: jy - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: dot), with: .color(palette[p % palette.count].opacity(opacity)))
            }
        }
    }
}

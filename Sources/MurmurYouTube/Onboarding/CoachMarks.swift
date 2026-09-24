import SwiftUI

/// The "co jest co" tour: the main window dims, one element at a time is lit up, and a bubble
/// says what it is and what it does. Elements register themselves with `.coachAnchor`.
struct CoachStep: Identifiable {
    let id = UUID()
    /// Anchor ids to light up together; empty means "nothing in the window" (centred bubble).
    let anchors: [String]
    let symbol: String
    let title: String
    let text: String
}

@MainActor
@Observable
final class TourState {
    static let shared = TourState()

    var isActive = false
    var index = 0
    /// Set when the tour should begin as soon as the main window appears.
    var isPending = false

    var steps: [CoachStep] {
        [
            CoachStep(anchors: ["record"], symbol: "record.circle", title: t("Nagrywanie", "Recording"),
                      text: t("To samo, co trzymanie klawisza dyktowania: mówisz, a tekst wpisuje się tam, gdzie masz kursor. Gdy kursor nie jest w żadnym polu, tekst ląduje w schowku — możesz chodzić po aplikacjach, oglądać rzeczy, mówić, a na końcu kliknąć w pole i wkleić (⌘V).",
                              "The same as holding the dictation key: you talk and the text lands where your cursor is. When the cursor isn't in any field, the text goes to the clipboard — so you can wander through apps, look at things, talk, and finally click into a field and paste (⌘V).")),
            CoachStep(anchors: ["grab"], symbol: "viewfinder", title: t("Chwyć obszar", "Grab Area"),
                      text: t("Zaznaczasz kawałek ekranu, a Papla czyta z niego tekst (OCR) albo kod QR i kopiuje go do schowka.",
                              "Select a piece of the screen and Papla reads the text (OCR) or QR code from it and copies it to the clipboard.")),
            CoachStep(anchors: ["search"], symbol: "magnifyingglass", title: t("Wyszukiwarka", "Search"),
                      text: t("Historia wszystkiego, co skopiowałeś lub podyktowałeś: teksty, linki, obrazy, kolory, zrzuty ekranu, transkrypcje. Otwiera się też skrótem z dowolnej aplikacji.",
                              "The history of everything you copied or dictated: text, links, images, colors, screenshots, transcripts. It also opens with a shortcut from any app.")),
            CoachStep(anchors: ["tabs"], symbol: "slider.horizontal.3", title: t("Ustawienia funkcji", "Feature settings"),
                      text: t("Każda funkcja ma swoją zakładkę: skróty, opcje, wygląd. Wszystko zapisuje się od razu.",
                              "Every feature has its own tab: shortcuts, options, looks. Everything saves instantly.")),
            CoachStep(anchors: ["dictionary"], symbol: "character.book.closed", title: t("Słownik", "Dictionary"),
                      text: t("Uczy Paplę słów, które źle rozpoznaje — nazw własnych, żargonu. Ma inny kolor, bo w odróżnieniu od reszty nie ma odpowiednika w wyszukiwarce.",
                              "Teaches Papla words it mishears — names, jargon. It has a different color because, unlike the rest, it has no counterpart in the search.")),
            CoachStep(anchors: ["icon-appearance", "icon-model", "icon-permissions"], symbol: "gearshape", title: t("Ogólne, model, uprawnienia", "General, model, permissions"),
                      text: t("Trzy ikony: zębatka (język, ikona w pasku menu, kula lub fala, ponowne uruchomienie przewodnika i tego samouczka), wybór i pobieranie modelu mowy oraz uprawnienia macOS. Najedź myszką, żeby zobaczyć nazwę.",
                              "Three icons: the gear (language, menu bar icon, orb or wave, replaying the guide and this tour), speech model choice and download, and macOS permissions. Hover to see the name.")),
            CoachStep(anchors: [], symbol: "menubar.rectangle", title: t("Ikona w pasku menu", "Menu bar icon"),
                      text: t("Papla mieszka w pasku menu u góry ekranu. Lewy klik otwiera i zamyka to okno, prawy pokazuje menu: wyszukiwarka, ustawienia, język, szybkie przełączniki.",
                              "Papla lives in the menu bar at the top of the screen. Left click opens and closes this window, right click shows the menu: search, settings, language, quick toggles.")),
            CoachStep(anchors: [], symbol: "checkmark.seal", title: t("To wszystko", "That's it"),
                      text: t("Przewodnik i ten samouczek możesz uruchomić ponownie w menu pod prawym klikiem albo w Ustawienia ▸ ikona zębatki.",
                              "You can run this tour and the guide again from the right-click menu or in Settings ▸ the gear icon.")),
        ]
    }

    func start() {
        index = 0
        isActive = true
    }

    func next() {
        if index + 1 < steps.count { index += 1 } else { finish() }
    }

    func finish() {
        isActive = false
        Settings.shared.tourDone = true
    }
}

struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func coachAnchor(_ id: String) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

struct CoachOverlay: View {
    let tour: TourState
    let anchors: [String: Anchor<CGRect>]
    let geometry: GeometryProxy

    private static let bubbleWidth: CGFloat = 340

    var body: some View {
        let step = tour.steps[min(tour.index, tour.steps.count - 1)]
        let rects = step.anchors.compactMap { anchors[$0] }.map { geometry[$0] }
        let hole = rects.dropFirst().reduce(rects.first) { $0?.union($1) }?.insetBy(dx: -7, dy: -7)
        let size = geometry.size

        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12)) }
            }
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
            .contentShape(Rectangle())
            .onTapGesture { tour.next() }

            if let hole {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Brand.accent, lineWidth: 2)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                    .allowsHitTesting(false)
            }

            bubble(step: step)
                .frame(width: Self.bubbleWidth)
                .offset(bubbleOffset(hole: hole, in: size))
        }
        .animation(DS.Motion.panel, value: tour.index)
    }

    private func bubbleOffset(hole: CGRect?, in size: CGSize) -> CGSize {
        let height: CGFloat = 190
        guard let hole else {
            return CGSize(width: (size.width - Self.bubbleWidth) / 2, height: (size.height - height) / 2)
        }
        let x = min(max(hole.midX - Self.bubbleWidth / 2, 16), size.width - Self.bubbleWidth - 16)
        let below = hole.maxY + 14
        let y = below + height < size.height ? below : max(16, hole.minY - height - 14)
        return CGSize(width: x, height: y)
    }

    private func bubble(step: CoachStep) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack(spacing: DS.Space.snug) {
                Image(systemName: step.symbol).foregroundStyle(Brand.accent)
                Text(step.title).font(DS.Font.title)
            }
            Text(step.text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(tour.index + 1) / \(tour.steps.count)")
                    .font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                Spacer()
                Button(t("Pomiń", "Skip")) { tour.finish() }
                    .buttonStyle(.plain).foregroundStyle(DS.Color.inkSecondary)
                TransportKey(
                    title: tour.index + 1 == tour.steps.count ? t("Gotowe", "Done") : t("Dalej", "Next"),
                    isEngaged: true, engagedColor: Brand.accent
                ) { tour.next() }
            }
            .padding(.top, DS.Space.tight)
        }
        .padding(DS.Space.roomy)
        .background(.regularMaterial, in: .rect(cornerRadius: DS.Radius.panel))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }
}

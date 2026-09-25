# Papla

**English** · [Polski](#papla--po-polsku)

A background app for macOS (menu bar icon, no Dock icon). Everything happens locally on your Mac —
your recordings and text never leave it. The network is only used to download the speech model
(and the optional update check in Settings ▸ Model).

Features, each with its own shortcut and its own tab in Settings:

- **Dictation** — hold a key (or press once to start and once to stop), speak, and the text lands in
  the field you are typing in. When the cursor isn't in a field the text goes to the clipboard, so you
  can move through apps, keep talking, and finally click into a field and paste. Speech recognition:
  NVIDIA Parakeet TDT v3 (CoreML, ~470 MB, downloaded once), optimized for Polish. Rule-based cleanup
  (filler words, punctuation) plus your own correction dictionary.
  - **Translate what you dictate** — a second shortcut (⌃⌥⌘T): speak Polish, the text is inserted in
    the language you picked (details below).
  - **Emoji** — Papla adds emoji to dictated text from a fixed rule dictionary (no AI, fully local).
    Intensity 0–5, individual keywords can be switched off, your own phrase → emoji entries, at the
    word or at the end of the sentence.
  - **Punctuation** — normal, "no final period" (no more hate period in chat), or minimal (no commas).
    Nothing ever follows an emoji or "XD" — no comma, no period.
  - **Visualization** — an orb or a wave that reacts to your voice, with your own colors.
- **Text grab** — select an area of the screen and OCR (Apple Vision, Polish-tuned) copies its text to
  the clipboard. A selected QR / Aztec / DataMatrix / PDF417 code copies its decoded value.
- **Clipboard / Papla search** — a shortcut opens a floating Spotlight-style window with the history of
  everything you copied (⌘C): text, links, images, colors, code, files — with real thumbnails and
  Finder-style QuickLook previews, plus macOS screenshots and screen recordings. Native look (Liquid
  Glass, system colors), system / light / dark. Category filters, ⌘1–⌘9 to paste, ⌘T to translate,
  adjustable width with a live preview. Right-click ▸ **Remove formatting** puts a plain-text copy on the clipboard as a new entry. Images, screenshots, recordings, files and colors can be dragged straight out of the search into other apps. Optionally **on paste** "—" and "–" become "-". Content from
  password managers is never saved.
- **Timer** — ⌃⌥⌘M opens a quick entry: type minutes (e.g. 45) and a description, get an alarm with
  the sound you chose, optionally a countdown in the menu bar.
- **Color picker** — the system eyedropper under its own shortcut; the color goes to the clipboard
  (HEX / RGB / HSL) and to a color history.
- **First-run guide and "what's what" tour** — shown once, skippable, replayable from the menu bar icon
  or Settings ▸ gear icon ▸ Guide.

Full user guide (PL / EN): [docs/instrukcja.html](docs/instrukcja.html).

## Install

**One command** (builds from source, a few minutes the first time):

```bash
curl -fsSL https://raw.githubusercontent.com/deusdexsd/papla/main/install.sh | bash
```

Needs a Mac with Apple Silicon, macOS 26+ and Xcode Command Line Tools (the script asks for them).

**Or the ready-made app:** download `Papla.dmg` from
[Releases](https://github.com/deusdexsd/papla/releases) and drag Papla to Applications. The app is
not signed by Apple, so macOS will block it. Right-click Papla ▸ **Open** ▸ Open, or in Terminal:

```bash
xattr -cr /Applications/Papla.app
```

### First launch

On first start Papla walks you through a short guide (language, what it does, speech model,
permissions, looks) and then shows what's what in the window. Everything can be skipped and replayed.

1. Launch Papla — the icon appears in the menu bar (left click opens/closes the settings window, right
   click shows the menu with search, settings and language).
2. Grant permissions in System Settings ▸ Privacy & Security: **Microphone**, **Accessibility**,
   **Screen Recording** (status and shortcuts live in Settings ▸ Permissions, the lock icon).
3. On the first dictation the speech model (~470 MB) downloads by itself — a one-time thing. Model
   choice, status, re-download (if something is wrong) and update checks are in Settings ▸ Model.
   Note: only the default Parakeet v3 understands Polish — the other models (English, Japanese) are
   flagged with a warning in the app.
4. Interface language (English / Polish), shortcuts and the menu bar icon can be changed in Settings.

### Tips

- After every update (new signature) macOS forgets Accessibility: remove Papla from the list (−), add
  it again and restart the app.
- F1–F12 have their own functions in macOS; use combinations with ⌘⌥⌃ for shortcuts, or map a key in
  Karabiner-Elements (a separate app — the (i) button in Settings explains how).
- Translation uses Apple Translation on your Mac — the language pack downloads on first use (one
  click in the system dialog).
- Update: run the install command again.
- Uninstall: move `/Applications/Papla.app` to the Trash.

## Translation and languages

Translation runs entirely on your Mac (Apple Translation), without sending text anywhere. The source
language is always **Polish**.

**Target languages:** English, German, Spanish, French, Italian, Ukrainian, Portuguese (Settings ▸
Dictation).

**Where you translate:** dictate-and-translate (⌃⌥⌘T) and ⌘T on an entry in the search. If a language
pack is missing, Papla inserts the original and shows an error instead of silently doing nothing.

**Other languages in the app:** interface — Polish and English; OCR — Polish, English, German, French,
Spanish, Italian, Ukrainian, Portuguese; dictation — tuned for Polish.

## Default shortcuts

| Function | Shortcut |
|---|---|
| Dictation | Right ⌥ (changeable) |
| Dictate and translate | ⌃⌥⌘T |
| Text grab | ⌃⌥⌘4 |
| Search / clipboard history | ⌃⌥⌘V |
| Color picker | ⌃⌥⌘C |
| Timer | ⌃⌥⌘M |

## Build

```bash
make install   # builds, packages the .app, signs ad-hoc and installs to /Applications
make run       # same without installing
swift test --scratch-path "$HOME/Library/Caches/MurmurYouTubeBuild/scratch"
```

Build products go to `~/Library/Caches/MurmurYouTubeBuild`, not this folder — `~/Desktop` is synced by
iCloud, which can corrupt compilation and signing. The ad-hoc signature changes with every build, so
macOS forgets the permissions: grant them again after rebuilding.

## License

[MIT](LICENSE) — use, modify and redistribute the code, keeping the copyright notice. **The name
"Papla" and the app icon are excluded** — they are not covered by the MIT license; see
[TRADEMARK.md](TRADEMARK.md). If you fork, give your version its own name and icon.

---

<a id="papla--po-polsku"></a>

# Papla — po polsku

[English](#papla)  ·  **Polski**

Appka na macOS działająca w tle (ikona w pasku menu, bez ikony w Docku). Wszystko
dzieje się lokalnie na Macu — Twoje nagrania i teksty nie wychodzą w sieć. Sieć jest używana tylko do
pobrania modelu mowy (i opcjonalnego sprawdzenia aktualizacji w Ustawienia ▸ Model).

Funkcje, każda z własnym skrótem i zakładką w ustawieniach:

- **Dyktowanie** — trzymasz klawisz (albo naciskasz raz i raz), mówisz po polsku, tekst
  ląduje w polu, w którym piszesz. Gdy kursor nie jest w polu, tekst trafia do schowka — możesz więc
  chodzić po aplikacjach, mówić, a na końcu kliknąć w pole i wkleić. Transkrypcja: NVIDIA Parakeet TDT v3 (CoreML, ~470 MB,
  pobierany raz). Brak pola do wpisania → tekst trafia do schowka. Czyszczenie regułowe
  (wypełniacze, interpunkcja) + własny słownik poprawek.
  - **Tłumaczenie podyktowanego tekstu** — drugi skrót (⌃⌥⌘T): mówisz po polsku, wstawia się
    tekst w wybranym języku (szczegóły niżej).
  - **Emoji** — Papla sama dodaje emoji do podyktowanego tekstu według słownika reguł (bez AI,
    lokalnie). Natężenie ustawiasz w skali 0–5, możesz wyłączać pojedyncze hasła, dopisywać
    własne (fraza → emoji) i wybrać, czy emoji ma wpadać w zdaniu czy na jego końcu.
  - **Interpunkcja** — normalna, „bez kropki na końcu" albo minimalna (bez przecinków). Po emoji i
    po „XD" nigdy nie ma przecinka ani kropki.
  - **Wizualizacja** — podczas nagrywania kula albo fala reagująca na głos, z własnymi kolorami.
- **Chwytanie tekstu** — zaznaczasz obszar ekranu, OCR (Apple Vision, wymuszony polski)
  kopiuje tekst do schowka. Zaznaczony kod QR / Aztec / DataMatrix / PDF417 kopiuje swoją
  zdekodowaną wartość. Opcjonalnie zamienia „—” na „-”.
- **Schowek / wyszukiwarka Papli** — skrót otwiera pływające okno w stylu Spotlight z
  historią wszystkiego, co skopiowałeś (⌘C): tekst, linki, obrazy, kolory, kod, pliki —
  z prawdziwymi miniaturami (obrazy, a dla plików podgląd QuickLook jak w Finderze) i
  kolorami wybranymi pipetą oraz zrzutami i nagraniami ekranu z macOS (kategoria „Zrzuty"). Natywny wygląd (szkło Liquid Glass, kolory systemowe), tryb
  systemowy / jasny / ciemny. Wyszukiwarka + filtry kategorii, ⌘1–⌘9 do wklejania, zębatka
  otwiera ustawienia Papli. ⌘T tłumaczy zaznaczony wpis. Prawy klik ▸ **Usuń formatowanie** kładzie do schowka czysty tekst jako nową pozycję. Obrazy, zrzuty, nagrania, pliki i kolory można przeciągać prosto z wyszukiwarki do innych aplikacji.
  Zwykłe kopiowanie zostaje nietknięte; opcjonalnie **przy wklejaniu** (⌘V w dowolnej
  aplikacji lub z historii) „—” i „–” zamieniają się na „-”, a po wklejeniu schowek wraca do
  oryginału. Treści z menedżerów haseł nigdy nie są zapisywane.
- **Minutnik** — skrót ⌃⌥⌘M otwiera szybkie okno: wpisujesz minuty (np. 45) i opis, alarm z
  wybranym dźwiękiem, opcjonalnie odliczanie w pasku menu.
- **Próbnik kolorów** — systemowa pipeta pod własnym skrótem; kolor trafia do schowka
  (HEX / RGB / HSL) i do osobnej historii kolorów.

Pełna instrukcja obsługi (PL / EN): [docs/instrukcja.html](docs/instrukcja.html).

## Instalacja

**Jedna komenda** (buduje ze źródeł, ~kilka minut za pierwszym razem):

```bash
curl -fsSL https://raw.githubusercontent.com/deusdexsd/papla/main/install.sh | bash
```

Wymaga Maca z Apple Silicon, macOS 26+ i Xcode Command Line Tools (skrypt sam o nie poprosi).

**Albo gotowa aplikacja:** pobierz `Papla.dmg` z zakładki
[Releases](https://github.com/deusdexsd/papla/releases), przeciągnij Paplę do Programów.
Aplikacja nie jest podpisana przez Apple, więc macOS ją zablokuje. Rozwiązanie: prawy klik na
Papli ▸ **Otwórz** ▸ Otwórz, albo w terminalu:

```bash
xattr -cr /Applications/Papla.app
```

### Pierwsze uruchomienie

Przy pierwszym starcie Papla prowadzi przez krótki przewodnik (co robi, model mowy, uprawnienia, wygląd), a
potem pokazuje w oknie „co jest co". Wszystko da się pominąć i uruchomić ponownie z menu pod ikoną.

1. Uruchom Paplę — ikona pojawi się w pasku menu (lewy klik otwiera/zamyka okno ustawień, prawy pokazuje menu z wyszukiwarką, ustawieniami i językiem).
2. Nadaj uprawnienia w Ustawieniach systemowych ▸ Prywatność i bezpieczeństwo: **Mikrofon**,
   **Dostępność**, **Nagrywanie ekranu**.
3. Przy pierwszym dyktowaniu model rozpoznawania mowy (~470 MB) pobierze się sam — to jednorazowe.
   Wybór modelu mowy, jego stan, ponowne pobranie (gdy coś nie działa) i sprawdzanie aktualizacji są w Ustawienia ▸ Model.
   Uwaga: tylko domyślny Parakeet v3 rozumie polski — pozostałe modele (angielskie, japoński) są w aplikacji
   oznaczone ostrzeżeniem.
4. Język interfejsu (angielski / polski), skróty i wygląd ikony zmienisz w Ustawieniach.

### Porady

- Wszystkie uprawnienia (status na żywo, skróty do ustawień systemu, restart Papli) są w Ustawienia ▸ Uprawnienia.
- Po każdej aktualizacji (nowy podpis) macOS zapomina Dostępność: usuń Paplę z listy (−), dodaj
  ponownie i uruchom appkę od nowa.
- Klawisze F1–F12 mają w macOS własne funkcje; do skrótów używaj kombinacji z ⌘⌥⌃ albo
  zbinduj klawisz w Karabiner-Elements.
- Tłumaczenie używa systemowego Apple Translation — pakiet języka pobierze się przy pierwszym
  użyciu (potrzebne jedno kliknięcie w systemowym oknie).
- Aktualizacja: uruchom komendę instalacyjną jeszcze raz.
- Odinstalowanie: przenieś `/Applications/Papla.app` do kosza.

## Licencja

[MIT](LICENSE) — możesz używać, zmieniać i rozpowszechniać kod, zostawiając informację o autorze. **Z wyłączeniem nazwy „Papla” i ikony aplikacji** — one nie są objęte licencją MIT; szczegóły w [TRADEMARK.md](TRADEMARK.md). Forka nazwij i oznacz własną nazwą i ikoną.

## Tłumaczenie i języki

Tłumaczenie działa w całości na Macu (systemowy Apple Translation), bez wysyłania tekstu do
internetu. Źródłem jest zawsze **polski**.

**Języki docelowe:** angielski, niemiecki, hiszpański, francuski, włoski, ukraiński, portugalski.
Wybierasz go w Ustawienia ▸ Dyktowanie.

**Gdzie tłumaczysz:**
- **Dyktowanie z tłumaczeniem** — skrót ⌃⌥⌘T (zmienisz w Ustawieniach): mówisz po polsku, w polu
  ląduje tekst w wybranym języku. Kula/fala dostaje wtedy osobne kolory, żebyś widział, że to
  tryb tłumaczenia.
- **Wyszukiwarka schowka** — zaznacz wpis i naciśnij ⌘T, żeby go przetłumaczyć.

**Pakiety językowe:** przy pierwszym użyciu danego języka macOS pobiera jego pakiet. Pojawi się
systemowe okno z prośbą o zgodę — kliknij Pobierz, potem tłumaczenie działa offline. Bez pakietu
Papla wstawi oryginał i pokaże błąd, zamiast po cichu nic nie robić.

**Pozostałe języki w aplikacji:**
- **Interfejs:** polski i angielski (przełącznik w Ustawieniach oraz w menu pod prawym klikiem na
  ikonę; domyślnie angielski).
- **OCR (chwytanie tekstu):** polski, angielski, niemiecki, francuski, hiszpański, włoski,
  ukraiński, portugalski — główny i opcjonalny dodatkowy język.
- **Dyktowanie:** rozpoznawanie mowy jest ustawione pod polski.

## Wymagania

- macOS 26+ na Apple Silicon, Xcode / Swift 6.

## Budowanie

```bash
make install   # buduje, pakuje w .app, podpisuje ad-hoc i instaluje do /Applications
make run       # to samo bez instalowania
swift test --scratch-path "$HOME/Library/Caches/MurmurYouTubeBuild/scratch"
```

Artefakty budowania trafiają do `~/Library/Caches/MurmurYouTubeBuild`, nie do tego folderu —
`~/Desktop` jest synchronizowany przez iCloud, który potrafi psuć kompilację i podpis.
Jeśli iCloud „przywróci” usunięte pliki źródłowe (zdarzało się), po prostu usuń je ponownie.

### Uprawnienia

Podpis ad-hoc zmienia się przy każdym buildzie, więc macOS zapomina uprawnienia. Po
przebudowaniu: Ustawienia systemowe ▸ Prywatność i bezpieczeństwo ▸ **Dostępność**,
**Mikrofon**, **Nagrywanie ekranu** → usuń Paplę z listy (−) i dodaj ponownie, potem
uruchom appkę od nowa. Podpisanie certyfikatem Developer ID (99 USD/rok) to załatwia.

## Domyślne skróty

| Funkcja | Skrót |
|---|---|
| Dyktowanie | Prawy ⌥ (zmienisz na dowolny) |
| Chwytanie tekstu | ⌃⌥⌘4 |
| Wyszukiwarka / historia schowka | ⌃⌥⌘V |
| Próbnik kolorów | ⌃⌥⌘C |
| Dyktowanie z tłumaczeniem | ⌃⌥⌘T |
| Minutnik | ⌃⌥⌘M |

## Struktura

`Sources/MurmurYouTube/`: `Core` (hotkey, wstawianie tekstu), `Transcription` (Parakeet),
`Formatting`, `Grab` (OCR), `Clipboard` (historia, panel, wklejanie, indeks zrzutów), `Colors` (pipeta),
`UI`, `Support`. Osobny target `MurmurDictionary` (słownik poprawek) z testami w `Tests/`.

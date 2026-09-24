# Papla

Osobista appka na macOS działająca w tle (ikona w pasku menu, bez ikony w Docku). Wszystko
dzieje się lokalnie na Macu — nic nie wychodzi w sieć. Zaczęła się jako fork
[murmur-youtube](https://github.com/per-simmons/murmur-youtube), dziś to osobny projekt.

Cztery niezależne funkcje, każda z własnym skrótem, historią i zakładką w ustawieniach:

- **Dyktowanie** — trzymasz klawisz (albo naciskasz raz i raz), mówisz po polsku, tekst
  ląduje w polu, w którym piszesz. Transkrypcja: NVIDIA Parakeet TDT v3 (CoreML, ~470 MB,
  pobierany raz). Brak pola do wpisania → tekst trafia do schowka. Czyszczenie regułowe
  (wypełniacze, interpunkcja) + własny słownik poprawek.
- **Chwytanie tekstu** — zaznaczasz obszar ekranu, OCR (Apple Vision, wymuszony polski)
  kopiuje tekst do schowka. Zaznaczony kod QR / Aztec / DataMatrix / PDF417 kopiuje swoją
  zdekodowaną wartość. Opcjonalnie zamienia „—” na „-”.
- **Schowek / wyszukiwarka Papli** — skrót otwiera pływające okno w stylu Spotlight z
  historią wszystkiego, co skopiowałeś (⌘C): tekst, linki, obrazy, kolory, kod, pliki —
  z prawdziwymi miniaturami (obrazy, a dla plików podgląd QuickLook jak w Finderze) i
  kolorami wybranymi pipetą oraz zrzutami i nagraniami ekranu z macOS (kategoria „Zrzuty"). Natywny wygląd (szkło Liquid Glass, kolory systemowe), tryb
  systemowy / jasny / ciemny. Wyszukiwarka + filtry kategorii, ⌘1–⌘9 do wklejania, zębatka
  otwiera ustawienia Papli.
  Zwykłe kopiowanie zostaje nietknięte; opcjonalnie **przy wklejaniu** (⌘V w dowolnej
  aplikacji lub z historii) „—” i „–” zamieniają się na „-”, a po wklejeniu schowek wraca do
  oryginału. Treści z menedżerów haseł nigdy nie są zapisywane.
- **Próbnik kolorów** — systemowa pipeta pod własnym skrótem; kolor trafia do schowka
  (HEX / RGB / HSL) i do osobnej historii kolorów.

Pełna instrukcja obsługi: [docs/instrukcja.html](docs/instrukcja.html) (wersja PDF do wydruku).

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

1. Uruchom Paplę — ikona pojawi się w pasku menu (lewy klik otwiera/zamyka okno, prawy pokazuje menu).
2. Nadaj uprawnienia w Ustawieniach systemowych ▸ Prywatność i bezpieczeństwo: **Mikrofon**,
   **Dostępność**, **Nagrywanie ekranu**.
3. Przy pierwszym dyktowaniu model rozpoznawania mowy (~470 MB) pobierze się sam — to jednorazowe.
4. Język interfejsu (angielski / polski), skróty i wygląd ikony zmienisz w Ustawieniach.

### Porady

- Po każdej aktualizacji (nowy podpis) macOS zapomina Dostępność: usuń Paplę z listy (−), dodaj
  ponownie i uruchom appkę od nowa.
- Klawisze F1–F12 mają w macOS własne funkcje; do skrótów używaj kombinacji z ⌘⌥⌃ albo
  zbinduj klawisz w Karabiner-Elements.
- Tłumaczenie używa systemowego Apple Translation — pakiet języka pobierze się przy pierwszym
  użyciu (potrzebne jedno kliknięcie w systemowym oknie).
- Aktualizacja: uruchom komendę instalacyjną jeszcze raz.
- Odinstalowanie: przenieś `/Applications/Papla.app` do kosza.

## Licencja

Wszystkie prawa zastrzeżone. Aplikacja jest darmowa do użytku osobistego; kodu nie wolno
kopiować ani rozpowszechniać bez zgody autora.

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

## Struktura

`Sources/MurmurYouTube/`: `Core` (hotkey, wstawianie tekstu), `Transcription` (Parakeet),
`Formatting`, `Grab` (OCR), `Clipboard` (historia, panel, wklejanie, indeks zrzutów), `Colors` (pipeta),
`UI`, `Support`. Osobny target `MurmurDictionary` (słownik poprawek) z testami w `Tests/`.

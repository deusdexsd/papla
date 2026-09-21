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

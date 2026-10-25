# PortScope

[English](README.md) · [简体中文](README.zh-CN.md) · Deutsch

Eine native macOS-Menüleisten-App, die jeden Port zeigt, auf dem dein Mac
lauscht, erklärt, was dahinter tatsächlich läuft, und ihn stoppen oder neu
starten lässt – ohne Suche durch `lsof`, `ps` und fünf Terminal-Tabs.

![PortScope](docs/screenshots/ports-dark.png)

## Installation

Mit [Homebrew](https://brew.sh):

```bash
brew install --cask xiaoyuhen/tap/portscope
```

Oder die neueste `PortScope-x.y.z.zip` von
[Releases](https://github.com/xiaoyuhen/portscope/releases) laden, entpacken und
`PortScope.app` in den Programme-Ordner ziehen.

Der Build ist **ad-hoc signiert, nicht notarisiert**, daher blockiert macOS den
ersten Start eines heruntergeladenen Zips. (Der Homebrew-Cask erledigt das
selbst.) Entweder einmal das Quarantäne-Flag entfernen:

```bash
xattr -dr com.apple.quarantine /Applications/PortScope.app
```

oder die App öffnen, die Warnung schließen und unter Systemeinstellungen →
Datenschutz & Sicherheit auf **Dennoch öffnen** klicken. (Unter macOS 14
funktioniert auch Rechtsklick → **Öffnen**; macOS 15 hat diese Abkürzung
entfernt.)

Benötigt macOS 14 (Sonoma) oder neuer. Apple Silicon und Intel werden beide
unterstützt.

## Aus dem Quellcode bauen

Xcode ist **nicht** nötig – Apples Command Line Tools reichen.

```bash
git clone https://github.com/xiaoyuhen/portscope.git
cd portscope
./scripts/build.sh
open dist/PortScope.app
```

`./scripts/package.sh` erzeugt dasselbe Zip wie die Releases: ein Universal
Binary (Apple Silicon und Intel) mit Prüfsumme, dessen Signatur nach dem
Entpacken geprüft wird.

## Warum

`lsof -iTCP -sTCP:LISTEN` sagt dir, dass eine PID Port 5173 belegt. Es sagt dir
nicht, dass es der Vite-Dev-Server des Projekts in `~/work/acme-web` ist, dass er
auf allen Netzwerkschnittstellen lauscht oder dass er seit drei Tagen läuft.
PortScope beantwortet diese Fragen auf einen Blick und zeigt, wie es zu seiner
Einschätzung kommt.

## Was es kann

- **Jeder lauschende Port, live.** Loopback, LAN und Wildcard-Bindungen; IPv4-
  und IPv6-Sockets eines Dienstes werden zu einer Zeile zusammengefasst. Sockets
  aufzählen und Prozessdaten lesen dauert etwa 100 ms; ein erster Durchlauf, der
  zusätzlich jeden Kandidaten per HTTP prüft, etwa 2 s – ganz ohne erweiterte
  Rechte.
- **Standardmäßig ruhig.** Desktop-Apps und macOS-Dienste (WeChat, Discord,
  ControlCenter, `rapportd`) halten den ganzen Tag Ports offen und sind nie der
  Grund, einen Monitor zu öffnen. Sie werden zu einer Zeile zusammengefaltet –
  „13 Desktop- und Systemports" –, die sich per Klick aufklappen lässt. Die
  Suche findet sie trotzdem.
- **Was es ist, nicht nur welche PID.** Dienst, Framework, Projektordner,
  HTTP-Status und die Belege für jede Schlussfolgerung. Ist es unsicher, sagt es
  das – „Node.js, 55 %" statt einer selbstbewussten Vermutung.
- **Docker-Container beim Namen.** Ein veröffentlichter Port zeigt den Container
  dahinter – `acme-web-1`, Image, Compose-Projekt – statt `com.docker.backend`.
  Container mit Datenbank- oder Cache-Images zählen als Datenspeicher. Stoppen
  und Neustarten wirken über die Engine-API auf genau diesen einen Container,
  nie auf Docker selbst. Funktioniert mit Docker Desktop, OrbStack, Colima und
  Rancher Desktop; keine CLI nötig.
- **Stoppen und neu starten.** Vorher bestätigt, Kindprozesse eingeschlossen,
  danach geprüft. Unter [Sicherheit](#sicherheit) steht genau, was es anfasst und
  was nicht.
- **Ein Zähler in der Menüleiste.** Wird das Fenster geschlossen, läuft PortScope
  in der Menüleiste mit einer Live-Portanzahl weiter; das Panel zeigt dieselben
  Zeilen wie das Fenster. **Bei Anmeldung öffnen** ist ein Schalter in den
  Einstellungen.
- **English, 简体中文 und Deutsch**, zur Laufzeit umschaltbar. Englisch ist für
  alle die Voreinstellung, unabhängig von der Systemsprache; eine andere Sprache
  gilt, sobald sie in den Einstellungen gewählt wurde.
- **Aktualisiert sich selbst.** Einmal täglich wird bei GitHub Releases
  nachgesehen; gibt es eine neue Version, zeigt PortScope, was sich geändert hat,
  und *Installieren und neu starten* lädt sie, prüft Prüfsumme und Signatur und
  ersetzt die App an Ort und Stelle. Eine Version überspringen oder die Prüfung
  abschalten geht in den Einstellungen.
- **Im Browser öffnen** oder `localhost:port` aus jeder Zeile kopieren.

## Kommandozeile

Dieselbe Engine, ohne Fenster – praktisch für Skripte, und so steuert auch die
Kompatibilitäts-Suite die App.

```bash
PortScope --list            # Tabelle aus Ports, Prozessen und Diensten
PortScope --list --json     # maschinenlesbar
PortScope --stop 3000       # den Dienst auf :3000 stoppen
PortScope --restart 3000    # stoppen, dann seine Kommandozeile erneut ausführen
PortScope --selftest        # eingebaute Prüfungen, Exit-Code 1 bei Fehlern
```

## Wie die Erkennung funktioniert

Drei Stufen von Belegen, die stärkste zuerst. Sie werden zusammengeführt statt
ersetzt: Eine niedrigere Stufe, die *zustimmt*, erhöht die Sicherheit; eine, die
bloß vorhanden ist, nicht.

| Stufe | Signal | Beispiel |
|---|---|---|
| 1. Prozess | Programm, argv, cwd | `manage.py runserver` → Django, 95 % |
| 2. HTTP | Header aus einem `GET /` nur über Loopback | `Server: AirTunes` → AirPlay-Empfänger |
| 3. Port | bekannte Ports, letzter Ausweg | 5173 → Vite, **höchstens 50 %** |

Die Sicherheit ist auf 99 % begrenzt: Jedes Signal hier ist eine Schlussfolgerung.
Ein Port, der HTTP spricht, aber zu nichts passt, wird als „HTTP-API" mit 35 %
gemeldet, nicht als „unbekannt" – dass dort überhaupt HTTP läuft, ist schon
nützlich.

Die Prüfung ist bewusst eng: nur Loopback – `127.0.0.1`, oder `::1` für einen
Dienst, der nur an IPv6 gebunden ist –, nie die LAN-Adresse, auch nicht bei einem
Dienst auf `0.0.0.0`. Weiterleitungen werden nie verfolgt, 1 s Timeout, fester
User-Agent, kein Proxy, und Ports, die kein HTTP sprechen können, werden ganz
übersprungen.

## Wie Ports zusammengefaltet werden

Die Regel ist strukturell, keine Liste von App-Namen, daher braucht eine neu
installierte App nie eine Codeänderung:

1. Eine Entwickler-Art (Dev-Server, Bundler, Datenbank, Cache, Container, KI) →
   **zeigen**.
2. Eine Entwickler-Laufzeit (`node`, `python3.12`, `redis-server`, `docker`, …) →
   **zeigen**.
3. Ein Projektordner ist erkennbar → **zeigen**.
4. Die Erkennung hat es als Systemdienst eingestuft → **falten**.
5. Es liegt unter `/System/`, `/usr/libexec/`, … → **falten**.
6. Es liegt in einem `.app`-Bundle → **falten**.
7. Alles andere → **zeigen**.

Die Reihenfolge ist das Design. Schritt 2 kommt vor Schritt 5, damit
`python3 -m http.server` aus `/usr/bin/python3` sichtbar bleibt; er kommt vor
Schritt 6, damit Dockers Listener `com.docker.backend` sichtbar bleibt. Schritt 7
ist die sichere Richtung: Ausgerechnet die Zeile wegzufalten, die jemand sucht,
ist der teure Fehler.

## Sicherheit

PortScope verändert deinen Rechner, deshalb sind die Regeln im Code erzwungen:

- **Signalisiert nie, was ihm nicht gehört** – nur deine eigenen Prozesse, nie
  PID 1, nie sich selbst. Ablehnungen werden in der Oberfläche erklärt.
- **Zuerst SIGTERM**, SIGKILL erst nach drei Sekunden Schonfrist – und die
  Oberfläche sagt, wenn ein erzwungenes Beenden nötig war.
- **Nimmt die Kindprozesse mit.** Ein Dev-Server besitzt seinen Compiler, seine
  Datenbank und seinen Watcher; nur den Port-Besitzer zu beenden lässt sie den
  Port weiter belegen.
- **Liest nie deine Umgebung.** Dort liegen API-Schlüssel, daher bekommt ein
  Neustart stattdessen die Umgebung deiner Shell – das steht im
  Bestätigungsdialog.
- **Prüft Neustarts.** Der Port muss innerhalb von 20 s wieder lauschen, sonst
  gilt die Aktion als fehlgeschlagen. Die Ausgabe landet in
  `~/Library/Logs/PortScope/`.

## Datenschutz

Ports, Prozesse, Pfade und Kommandozeilen verlassen nie den Rechner.

Die einzige Ausnahme ist eine **anonyme Start-Zählung**: Einmal pro Version und
Tag sendet die App ihre Version, macOS-Hauptversion, Architektur und eine
zufällige UUID pro Installation. Nie einen Port, Prozess, Pfad oder Hostnamen,
und es wird keine IP-Adresse gespeichert. Sie ist standardmäßig an und lässt sich
in den Einstellungen abschalten.

Die vollständigen Daten, das Speicherformat des Empfängers und alle Wege, sie
abzuschalten, stehen in [docs/privacy.md](docs/privacy.md) (Englisch). Ein Build
aus dem Quellcode sendet nichts, außer du übergibst ausdrücklich
`PORTSCOPE_TELEMETRY_URL`.

## Validierung

Drei Ebenen, weil sie Verschiedenes finden.

```bash
PortScope --selftest              # Logikprüfungen, Exit-Code 1 bei Fehlern
./scripts/compat/fixtures.sh      # 4 echte Server, erkannt und gestoppt
./scripts/validate.sh             # UI-Prüfungen gegen die laufende App
```

**Selbsttests** decken Scanner, Erkennung, Prozesssteuerung, Faltregeln, das
gemeinsame Listenmodell und die Lokalisierung ab. Es ist ein selbst gebautes
Testgerüst, weil weder XCTest noch Swift Testing allein mit den Command Line
Tools nutzbar sind.

**Die Kompatibilitätsmatrix** startet echte Server – einen HTTP-Server im
Express-Stil, einen Node-Server ohne Framework, Pythons `http.server` und einen,
der aus einem Projektordner gestartet wird –, fragt PortScope, was jeder davon
ist, stoppt dann jeden *über PortScope* und bestätigt, dass der Port wirklich frei
ist. Sie braucht nichts außerhalb des Repos und läuft deshalb auch in der CI.

**Das UI-Testgerüst** bedient die gebaute App über die Bedienungshilfen so, wie
ein Mensch es täte: startet eine Wegwerfkopie mit isolierter Einstellungsdomain,
öffnet das Menüleisten-Panel, schließt das Fenster, drückt „Open PortScope" und
liest den Bildschirm zurück. Es schlägt fehl, wenn Panel und Fenster sich uneinig
sind, welche Ports gefaltet sind, wenn sich das Fenster nicht zweimal wieder
öffnet, wenn eine frische Installation nicht auf Englisch ist oder wenn eine
gespeicherte chinesische Einstellung nicht beachtet wird.

Die CI führt die ersten beiden plus die Bundle-Prüfungen aus; das UI-Testgerüst
braucht eine grafische Sitzung und läuft daher lokal. In der CI wird es trotzdem
kompiliert, damit es nicht verrottet.

## Architektur

```
Sources/
  PortScopeKit/          # Engine, ohne UI. Wiederverwendbar für CLI oder Widget.
    Core/                # Scanner, Prozessinspektor, Erkennung, Steuerung
    SelfTest/            # Eingebaute Prüfungen, laufen mit --selftest
  PortScope/             # SwiftUI-App
    App/                 # Einstiegspunkt, Store, Menüleiste, Telemetrie, CLI
    UI/                  # Design-Tokens und Views
Support/Validation/      # UI-Testgerüst, gesteuert von scripts/validate.sh
infra/telemetry/         # Cloudflare Worker, der Starts zählt
```

Keine Abhängigkeiten. Die Engine nutzt nur die Standardbibliothek und Darwin,
deshalb ist die App nur wenige Megabyte groß und baut allein mit den CLT.

## Mitwirken

Issues und Pull Requests sind willkommen. Bitte zuerst
[CONTRIBUTING.md](CONTRIBUTING.md) lesen – dort stehen die auszuführenden
Prüfungen und die Konventionen des Codes. Sicherheitsmeldungen gehen über
[SECURITY.md](SECURITY.md), nicht über öffentliche Issues.

## Das Logo

Ein Ring ist der Port; zwei Bogenpaare strahlen von ihm aus. Entworfen nach den
Bold-Minimalism-Richtlinien in
[freshtechbro/claudedesignskills](https://github.com/freshtechbro/claudedesignskills).
Geometrie und Begründung in [docs/logo.md](docs/logo.md).

## Lizenz

MIT

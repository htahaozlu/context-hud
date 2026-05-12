# ContextHUD

<p align="center">
  <img src="logo.png" alt="ContextHUD logosu" width="360">
</p>

<p align="center">
  <a href="README.md">English</a> | Turkce
</p>

<p align="center">
  <strong>Kodlama ajanlari icin local-first depo baglami ve yerel macOS kullanim gorunurlugu.</strong>
</p>

<p align="center">
  ContextHUD, ajanlarin calistiklari depoya bagli kalmasini saglar, ajanlarin okuyabilecegi kararlı ozetler uretir ve Claude Code ile Codex kullanimini yerel bir macOS arayuzuyle gorunur hale getirir.
</p>

<p align="center">
  <a href="https://github.com/htahaozlu/context-hud/releases/latest/download/ContextHUD.dmg">
    <img alt="macOS icin indir" src="https://img.shields.io/badge/Download-macOS%20DMG-black?logo=apple">
  </a>
  <a href="https://github.com/htahaozlu/context-hud/releases/latest">
    <img alt="Guncel surum" src="https://img.shields.io/github/v/release/htahaozlu/context-hud?display_name=tag&label=release">
  </a>
  <a href="LICENSE">
    <img alt="Lisans" src="https://img.shields.io/badge/license-Apache--2.0-5DADE2">
  </a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-7DCEA0">
</p>

<table>
  <tr>
    <td valign="top" width="58%">

### Ne ise yarar

ContextHUD, ajan destekli gelistirmede surekli tekrar eden iki sorunu hedefler:

- depo baglami, ajan ozeti guncellenmeden daha hizli degisir
- kullanim ve oturum durumu terminal ciktisi ile yerel kayitlar arasinda kaybolur

Bu iki problemi, surekli kararlı proje ozetleri ureten yerel bir islem hattiyla ve Claude Code ile Codex etkinligini gosteren yerel bir macOS HUD arayuzuyle cozer.

    </td>
    <td valign="top" width="42%">

### Temel yuzeyler

- `.context-hud/` altinda depo snapshotlari
- Kararlı `AGENT.md` ve `CLAUDE.md`
- refresh, watch ve global gorunumler icin CLI
- Yerel AppKit menubar yardimci uygulamasi
- Araclar icin Markdown ve JSON ciktilari

    </td>
  </tr>
</table>

## Urun Onizlemesi

Uygulamadan disa aktarildiktan sonra urun ekran goruntusunu buraya ekleyin:

```md
![ContextHUD ekran goruntusu](docs/images/context-hud-screenshot.png)
```

Onerilen goruntuler:

- menubar HUD acikken
- yerel kullanim penceresi
- uretilmis `.context-hud/` ciktilari gorunen bir depo

## ContextHUD neden var

Modern kodlama ajanlari her calistirmada ayni iki seye ihtiyac duyar:

1. kisa ve guncel bir depo ozeti
2. yakin donem kullanim ve oturum davranisina dair guvenilir bir gorunum

Cogu is akisi bunlari tutarsiz sekilde ele alir. ContextHUD, barindirilan bir backend gerektirmeden bunlari yerel artifact uretimi ve yerel masaustu yuzeyiyle standardize eder.

## Temel yetenekler

### Depo baglami uretimi

Her yenileme, ajanlarin okuyabilecegi durumu `.context-hud/` altina yazar:

- `state.json`
- `brief-now.md`
- `brief-session.md`
- `brief-week.md`
- `AGENT.md`
- `hud.md`

Claude Code uyumlulugu icin `CLAUDE.md`, depo kokune de aynalanir.

### CLI is akisi

Bugun icin en guvenilir surekli arayuz CLI'dir:

- `context-hud hud` mevcut depoyu yeniler ve HUD ciktisini basar
- `context-hud snapshot` HUD basmadan artifact yazar
- `context-hud watch 30 .` depo baglamini belirli araliklarla taze tutar
- `context-hud global` `~/.context-hud/` altinda projeler arasi HUD olusturur

### Yerel macOS yardimcisi

Istege bagli yardimci uygulama `~/.context-hud/hud.json` dosyasini okur ve sunlari saglar:

- kompakt bir menubar durum gorunumu
- Claude Code ve Codex icin yerel kullanim penceresi
- tema, dil ve menubar baslik birlesimi ayarlari

Masaustu arayuzu yerel AppKit ile yazilmistir. `detail.html`, ana deneyim degil, bir export artifact'idir.

## Kurulum

### CLI kurulumu

```bash
cargo install --path .
```

### macOS uygulamasi kurulumu

1. Son surumu acin.
2. `ContextHUD.dmg` dosyasini indirin.
3. `ContextHUD.app` uygulamasini `Applications` klasorune surukleyin.
4. Uygulamayi bir kez `Applications` icinden calistirin.
5. DMG'yi cikarip silin.

### Zed gelistirme eklentisi olarak kurulum

1. Zed icinde Extensions gorunumunu acin.
2. `Install Dev Extension` secenegini secin.
3. Bu depoyu secin.
4. Gerekirse `granted_extension_capabilities` altinda `process:exec` iznini verin.

## Kullanim

### Mevcut depoyu yenile

```bash
context-hud hud
```

### HUD yazdirmadan artifact uret

```bash
context-hud snapshot
```

### Depo baglamini taze tut

```bash
context-hud watch 30 .
```

### Global HUD uret

```bash
context-hud global
context-hud watch-global 30
```

Global HUD `~/.context-hud/hud.md` konumuna yazilir.

## Artifact duzeni

Her yenileme asagidaki dosyalari atomik olarak yazar:

- `.context-hud/state.json`
- `.context-hud/brief-now.md`
- `.context-hud/brief-session.md`
- `.context-hud/brief-week.md`
- `.context-hud/AGENT.md`
- `.context-hud/hud.md`
- `CLAUDE.md`

Atomik yazim sayesinde ajanlar yenileme sirasinda yari yazilmis durumu gormez.

## Veri kaynaklari

ContextHUD su kaynaklari birlestirir:

- Git branch, son commit'ler ve worktree durumu
- depo `mtime` verilerinden cikarilan dosya etkinligi
- `~/.claude/projects/**/*.jsonl` icinden Claude Code kullanim verisi
- `~/.codex/sessions/**/*.jsonl` icinden Codex CLI kullanim verisi

Temel depo ozetleri icin harici servis gerekmez. Kullanim toplama, yerel transcript verilerine ve `python3` aracina dayanir.

## Paketleme

Depoda, istege bagli macOS yardimci uygulamasi derlemesi icin scriptler bulunur:

```bash
scripts/build-menubar-app.sh
scripts/create-macos-dmg.sh
```

Artifact'ler:

- `dist/ContextHUD.app`
- `dist/ContextHUD.dmg`

## Mevcut kisitlar

- Zed `extension_api` `0.7`, yukleme aninda calisan bir worktree hook saglamiyor
- Zed, eklentiler icin kalici bir HUD primitive'i henuz acmiyor
- ajan otomatik enjeksiyonu bugun `.context-hud/AGENT.md` veya `CLAUDE.md` uzerinden dosya tabanli

Bu sinirlar nedeniyle CLI halen en guvenilir surekli yuzeydir.

## Depo duzeni

- `src/` cekirdek motor, artifact render etme, Zed entegrasyonu ve kullanim toplama
- `src/bin/context-hud.rs` bagimsiz CLI giris noktasi
- `menubar/context-hud.swift` istege bagli macOS yardimci uygulamasi
- `examples/snapshot.rs` yerel gelistirme harness'i

## Gelistirme

```bash
cargo check
cargo run --example snapshot
```

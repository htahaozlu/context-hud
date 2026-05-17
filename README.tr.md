# ContextBar

<p align="center">
  <img src="logo.png" alt="ContextBar logosu" width="560">
</p>

<p align="center">
  <a href="README.md">English</a> | Türkçe
</p>

<p align="center">
  <strong>Kodlama ajanları için local-first depo bağlamı ve yerel macOS kullanım görünürlüğü.</strong>
</p>

<p align="center">
  ContextBar, ajanların çalıştıkları depoya bağlı kalmasını sağlar, ajanların okuyabileceği kararlı özetler üretir ve Claude Code ile Codex kullanımını yerel bir macOS arayüzüyle görünür hale getirir.
</p>

<p align="center">
  <a href="https://github.com/htahaozlu/context-bar/releases/latest/download/ContextBar.dmg">
    <img alt="macOS için indir" src="https://img.shields.io/badge/Download-macOS%20DMG-black?logo=apple">
  </a>
  <a href="https://github.com/htahaozlu/context-bar/releases/latest">
    <img alt="Güncel sürüm" src="https://img.shields.io/github/v/release/htahaozlu/context-bar?display_name=tag&label=release">
  </a>
  <a href="LICENSE">
    <img alt="Lisans" src="https://img.shields.io/badge/license-Apache--2.0-5DADE2">
  </a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-7DCEA0">
  <img src="https://img.shields.io/github/downloads/htahaozlu/context-bar/total?style=flat-square&label=indirme" alt="Toplam İndirme">
</p>

## Canlı demo

<p align="center">
  <img src="docs/images/context-bar-demo.gif" alt="ContextBar üzerinde Claude Code ve Codex kullanımının macOS'ta canlı güncellendiğini gösteren demo" width="100%">
</p>

ContextBar, Claude Code ve Codex kullanımına yerel bir macOS yüzeyi verir; böylece bağlam kayması ve rolling kullanım pencereleri siz çalışırken görünür kalır.

## Kurulum

### Homebrew (önerilen)

```bash
brew install --cask htahaozlu/context-bar/context-bar
```

`brew` ilk kurulumda `htahaozlu/homebrew-context-bar` tap'ini otomatik ekler. Sonraki güncellemeler: `brew update && brew upgrade --cask htahaozlu/context-bar/context-bar`.

### macOS uygulaması (DMG)

1. [En son sürümden](https://github.com/htahaozlu/context-bar/releases/latest) `ContextBar.dmg` dosyasını indirin (evrensel: Apple Silicon + Intel).
2. `ContextBar.app` uygulamasını `Applications` klasörüne sürükleyin.
3. İlk açılış: `ContextBar.app` üzerine sağ tıklayın → **Aç** → tekrar **Aç**. Uygulama ad-hoc imzalı (notarize değil).
4. DMG'yi çıkarıp silin.

macOS uygulamayı "hasarlı" olarak gösterirse quarantine işaretini kaldırın:

```bash
xattr -dr com.apple.quarantine /Applications/ContextBar.app
```

### CLI

```bash
cargo install --path .
```

## Önizleme

<p align="center">
  <img src="docs/images/context-bar-screenshot.png" alt="ContextBar yerel kullanım penceresi" width="100%">
</p>

Claude Code ve Codex için sürekli oturum görünürlüğüne sahip yerel macOS kullanım penceresi.

<p align="center">
  <img src="docs/images/context-bar-menubar.png" alt="ContextBar menubar" width="400">
</p>

Aktif ajan, proje ve bağlam kullanımını gösteren kompakt menubar durum öğesi. Tıklandığında aktif oturum, bağlam penceresi, 5sa/7g limitleri, paralel oturumlar ve canlı tema seçici içeren yerel bir popover açılır.

## Ne işe yarar

ContextBar, ajan destekli geliştirmede sürekli tekrar eden iki sorunu hedefler:

- depo bağlamı, ajan özeti güncellenmeden daha hızlı değişir
- kullanım ve oturum durumu terminal çıktısı ile yerel kayıtlar arasında kaybolur

Bu iki problemi, sürekli kararlı proje özetleri üreten yerel bir işlem hattıyla ve Claude Code ile Codex etkinliğini gösteren yerel bir macOS HUD arayüzüyle çözer.

### Temel yüzeyler

- `.context-bar/` altında depo snapshot'ları
- Kararlı `AGENT.md` ve `CLAUDE.md`
- refresh, watch ve global görünümler için CLI
- Yerel AppKit menubar yardımcı uygulaması
- Araçlar için Markdown ve JSON çıktıları

## Temel yetenekler

### Depo bağlamı üretimi

Her yenileme, ajanların okuyabileceği durumu `.context-bar/` altına yazar:

- `state.json`
- `brief-now.md`
- `brief-session.md`
- `brief-week.md`
- `AGENT.md`
- `hud.md`

Claude Code uyumluluğu için `CLAUDE.md`, depo köküne de aynalanır.

### CLI iş akışı

- `context-bar hud` mevcut depoyu yeniler ve HUD çıktısını basar
- `context-bar snapshot` HUD basmadan artifact yazar
- `context-bar watch 30 .` depo bağlamını belirli aralıklarla taze tutar
- `context-bar global` `~/.context-bar/` altında projeler arası HUD oluşturur

### Yerel macOS yardımcısı

Yardımcı uygulama `~/.context-bar/hud.json` dosyasını okur ve şunları sağlar:

- kompakt menubar durum öğesi (aktif ajan + proje + bağlam %)
- modern AppKit popover: aktif ajan, bağlam penceresi, ilerleme barlı 5sa/7g
  limitleri, paralel oturumlar ve tespit edilen diğer AI araçları için kartlar
- inline renk swatch'leri ve canlı önizlemeli tema seçici — bir temanın
  üzerinde gezinirken menubar başlığı o paletle yeniden çizilir
- Kullanım, Görünüm, Menubar ve Hakkında sekmeleri olan tam Ayarlar penceresi
- paralel Claude / Codex oturumları için per-session bağlam yüzdesi

### Masaüstü ve Bildirim Merkezi widget'ı

ContextBar üç boyutta native bir WidgetKit eklentisiyle gelir:
`systemSmall`, `systemMedium`, `systemLarge`. Widget aynı `hud.json`'u
menubar ile paylaşılan App Group container'ı
(`DQJT5BCZCM.com.htahaozlu.contextbar`) üzerinden okur; aktif agent,
proje, model, context %, 5h/7d limitleri ve agent başına dökümünü ekstra
bir daemon olmadan gösterir.

<p align="center">
  <img src="docs/images/context-bar-screenshot.png" alt="ContextBar widget önizleme" width="100%">
</p>

Eklemek için:

1. ContextBar 0.3.12+ sürümünü kurun ve bir kez başlatın. macOS extension'ı
   indeksleyecek (`pluginkit -m -v -i com.htahaozlu.contextbar.widget`
   listede çıkmalı).
2. Bildirim Merkezi'ni açın (saati tıklayın) → **Widget'ları Düzenle**,
   veya masaüstüne sağ tıklayın → **Widget'ları Düzenle**.
3. **ContextBar** araması yapın, küçük/orta/büyük varyantı istediğiniz
   yere bırakın.

Widget extension sandboxlu ve App Group entitlement'ı ile imzalı. macOS 14+
(macOS 26 Tahoe dahil) `chronod` sandboxsuz widget extension'larını sessizce
reddediyordu (`Ignoring restricted or unknown extension`). Host menubar
uygulaması her refresh'te `~/.context-bar/hud.json`'u App Group container'a
mirror'lar; sandbox içindeki widget bunu okur.

### Bugünün HUD'unu paylaş

Popover footer'da **Paylaş** butonu (`square.and.arrow.up`) mevcut HUD'u
PNG kartı olarak render eder: aktif agent, model, context %, 5h/7d
kullanım ve tespit edilen diğer araçlar. Varsayılan olarak proje isimleri
maskelenir, böylece repo adlarınız sızmaz. PNG geçici bir yola yazılır ve
Preview / kaydetme diyaloğuyla açılır; ekran görüntüsü alıp kırpmadan
Slack, X veya durum güncellemelerine drop edebilirsiniz.

<p align="center">
  <img src="docs/images/context-bar-screenshot-full.png" alt="ContextBar paylaşım kartı önizleme" width="100%">
</p>

UI olmadan headless render (otomasyon için):

```bash
CONTEXTBAR_SHARE_RENDER_PATH=/tmp/hud.png \
CONTEXTBAR_SHARE_MASK=1 \
/Applications/ContextBar.app/Contents/MacOS/context-bar
```

Gerçek proje isimlerinin kartta kalması için `CONTEXTBAR_SHARE_MASK=0`.

Menubar simgesi taşma nedeniyle gizlenirse (Bartender, Hidden Bar veya
kalabalık menubar), uygulamayı Finder / Spotlight'tan tekrar açtığınızda
doğrudan Ayarlar penceresi açılır; tercihlere erişim hep kalır.

Masaüstü arayüzü yerel AppKit'tir (NSPopover + NSVisualEffectView, sürekli
köşe eğrileri, SF Symbol toolbar). `detail.html`, ana deneyim değil, bir
export artifact'idir.

## Kullanım

### Mevcut depoyu yenile

```bash
context-bar hud
```

### HUD yazdırmadan artifact üret

```bash
context-bar snapshot
```

### Depo bağlamını taze tut

```bash
context-bar watch 30 .
```

### Global HUD üret

```bash
context-bar global
context-bar watch-global 30
```

Global HUD `~/.context-bar/hud.md` konumuna yazılır.

## Artifact düzeni

Her yenileme aşağıdaki dosyaları atomik olarak yazar:

- `.context-bar/state.json`
- `.context-bar/brief-now.md`
- `.context-bar/brief-session.md`
- `.context-bar/brief-week.md`
- `.context-bar/AGENT.md`
- `.context-bar/hud.md`
- `CLAUDE.md`

Atomik yazım sayesinde ajanlar yenileme sırasında yarı yazılmış durumu görmez.

## Veri kaynakları

ContextBar şu kaynakları birleştirir:

- Git branch, son commit'ler ve worktree durumu
- depo `mtime` verilerinden çıkarılan dosya etkinliği
- `~/.context-bar/claude-statusline.json` altındaki isteğe bağlı Claude Code statusline snapshot'ı
- `~/.claude/projects/**/*.jsonl` içinden Claude Code kullanım verisi
- `~/.codex/sessions/**/*.jsonl` içinden Codex CLI kullanım verisi

Temel depo özetleri için harici servis gerekmez. Kullanım toplama, yerel transcript verilerine, isteğe bağlı yerel Claude Code statusline verisine ve `python3` aracına dayanır.

### Claude Code parity

Claude context yüzdesi için en iyi kaynak, Claude Code'un native statusline payload'ıdır. ContextBar bunu yerelde saklayabilir:

```json
{
  "statusLine": {
    "type": "command",
    "command": "context-bar claude-statusline"
  }
}
```

Bu komut `~/.context-bar/claude-statusline.json` dosyasını yazar ve ContextBar bu dosyayı Claude context için birincil kaynak olarak okur. Snapshot eksikse veya bayatsa transcript tabanlı tahmine geri düşer.

## Paketleme

Depoda macOS yardımcı uygulaması derlemesi için scriptler bulunur:

```bash
scripts/build-menubar-app.sh
scripts/create-macos-dmg.sh
```

Doğrudan app build'inde WidgetKit extension'ı app bundle'a dahil etmek için:

```bash
WIDGET_BUILD=1 scripts/build-menubar-app.sh
```

`scripts/create-macos-dmg.sh` widget build'ini varsayılan olarak açar.

Artifact'ler:

- `dist/ContextBar.app`
- `dist/ContextBar.dmg`

## Depo düzeni

- `src/` çekirdek motor, artifact render etme ve kullanım toplama
- `src/bin/context-bar.rs` bağımsız CLI giriş noktası
- `menubar/context-bar.swift` macOS yardımcı uygulaması
- `examples/snapshot.rs` yerel geliştirme harness'i

## Geliştirme

```bash
cargo check
cargo run --example snapshot
```

## Topluluk

- Sorular ve kullanım yardımı: GitHub Discussions
- Hatalar ve özellik istekleri: GitHub Issues
- Katkı rehberi: `CONTRIBUTING.md`
- Güvenlik bildirimi: `SECURITY.md`

## Lisans

Apache-2.0

# Zed Context Pilot: Verified Research Notes

Tarih: 2026-05-11

Bu not, urun fikrini Zed'in Mayis 2026 itibariyla dogrulanmis extension yuzeyiyle hizalamak icin hazirlandi.

## Dogrulanan gercekler

1. Zed extension manifest dosyasi `extension.json` degil, `extension.toml`.
2. Zed extension'lari Rust ile yaziliyor ve Wasm olarak calisiyor.
3. Slash command tanımlamak doğrudan destekleniyor.
4. Extension tarafında süreç çalıştırma için capability tabanlı bir `process:exec` modeli var.
5. Resmi örnekler arasında doğrudan slash command extension'ı (`perplexity`) ve context server extension'ı (`postgres-context-server`) bulunuyor.

## Urun hedefi acisindan ana sonuc

Aradigimiz sey sadece "slash command ile context ekleme" degil.

Asil urun:

- kullaniciya gorunen, surekli guncel bir context HUD
- assistant'a varsayilan olarak akan bir context katmani
- zaman pencereli calisma hafizasi:
  - `now`: son 15 dakika
  - `session`: son 5 saat
  - `week`: son 7 gun

Bu nedenle slash command dogrulamasi hala yararli, ama ana urun yuzeyi olarak gorulmemeli.

## Tasarim notundaki duzeltmeler

### 1. Manifest ve temel iskelet

Ilk nottaki `extension.json` varsayimi guncel degil. Dogru dosya:

- `extension.toml`

Temel alanlar:

- `id`
- `name`
- `version`
- `schema_version`
- `authors`
- `description`
- `repository`

## Slash command yuzeyi

Resmi ornek `perplexity` extension'i su iki noktayi dogruluyor:

1. `extension.toml` içinde `[slash_commands.<name>]` bloğu tanımlanıyor.
2. Rust tarafında `run_slash_command(...) -> Result<SlashCommandOutput, String>` implement ediliyor.

Örnek manifest biçimi:

```toml
[slash_commands.perplexity]
description = "Ask a question to Perplexity AI"
requires_argument = true
tooltip_text = "Ask Perplexity"
```

## Extension API yuzeyi

`docs.rs` üzerindeki güncel crate sürümü araştırma sırasında `zed_extension_api 0.7.0` olarak görünüyor.

Bizim ilk prototip için kritik parçalar:

- `Extension` trait
- `SlashCommand`
- `SlashCommandOutput`
- `Worktree`
- `process::Command`

`Worktree` üzerinde doğrulanmış erişimler:

- `root_path()`
- `read_text_file(...)`
- `shell_env()`
- `which(...)`

Bu, `/hello` ve ileride fallback komutlari icin yeterli bir baslangic.

## Diagnostics / LSP erisimi

Burada onemli bir belirsizlik var:

- Zed'in kendi AI agent araçlarında diagnostics erişimi var.
- Ancak extension API dokümanlarında diagnostics veya LSP hata listesine doğrudan erişen açık bir yöntem araştırma sırasında görünmedi.

Bu yuzden "LSP'den son hata cekme" fikri su an icin dogrulanmis bir extension capability degil. Bunu mimaride ayri risk olarak ele almak gerekiyor.

## Context server ile slash command ayni sey degil

`postgres-context-server` örneği context server uzantısıdır. Bu yapı Assistant/Agent tarafına araç sağlayabilir, ama doğrudan "özel briefing slash command" gereksinimi için ilk ve en kısa yol bu değil.

Ilk milestone icin dogru secim:

- dogrudan slash command extension

Sonraki asamada degerlendirilecek alternatif:

- slash command + MCP/context server hibrit yapi

## Persistent HUD ve otomatik context injection durumu

Arastirma sirasinda su iki urun gereksinimi icin acik, dogrudan ve resmi bir extension hook'u dogrulanmadi:

1. Assistant her mesaj baslatmadan once extension kaynakli otomatik prompt/context ekleme
2. Extension'in Zed icinde kalici, ozel bir HUD/panel yuzeyi cizmesi

Bu ikisi urunun cekirdegi oldugu icin, teknik plan bunlari "dogrulanmis", "muhtemel" ve "fallback" yollar olarak ayirmali.

## Bundan sonra neyi "high signal" sayiyoruz?

Bu proje icin yuksek sinyal veri su tiptedir:

1. aktif branch
2. local diff ozeti
3. son 3-10 commit'in tematik ozeti
4. son 15 dakikada dokunulan dosyalar
5. son 5 saatte odak olunan dosya ve klasorlar
6. son 7 gunde tekrar eden calisma basliklari
7. varsa hata/uyari ozeti
8. assistant konusmalarindan uretilen kisa hafiza

Dusuk sinyal ve gosteris icin veri toplamayacagiz:

- ham uzun diff'ler
- tum commit log'unu oldugu gibi basmak
- her dosya olayini listemek
- kullanicinin karar vermesini zorlastiran asiri telemetry

## Bu proje icin cikarim

En dusuk riskli baslangic mimarisi:

1. context engine'i once editor-disinda mantiksal bir katman olarak tasarlamak
2. Zed dev extension'i entegrasyon kabugu olarak kullanmak
3. slash command'i sadece fallback ve debug yuzeyi olarak tutmak
4. context uretimini once `git` ve calisma alani verisiyle sinirlamak
5. diagnostics entegrasyonunu dogrulanana kadar opsiyonel tutmak

## Su anki teknik yon

Urun hedefi acisindan bugunden itibaren su ayrimi net:

- ana urun: `always-on HUD + automatic assistant context`
- fallback: `/brief` benzeri manuel inject komutu

## İncelenen kaynaklar

- Zed Developing Extensions: https://zed.dev/docs/extensions/developing-extensions
- Zed Extension Capabilities: https://zed.dev/docs/extensions/capabilities
- Zed MCP Server Extensions: https://zed.dev/docs/extensions/mcp-extensions
- Zed Text Threads: https://zed.dev/docs/ai/text-threads
- docs.rs `zed_extension_api`: https://docs.rs/zed_extension_api/latest/zed_extension_api/
- Örnek extension: https://github.com/zed-extensions/perplexity
- Örnek context server: https://github.com/zed-extensions/postgres-context-server

# Zed Context Pilot: Architecture v1

Tarih: 2026-05-11

## Hedef

Aktif Zed worktree'si icin surekli guncel kalan, yuksek sinyalli bir calisma hafizasi uretmek ve bunu hem kullaniciya gorunur hale getirmek hem de assistant'a varsayilan context olarak vermek.

Bu urun slash command merkezli degil. Slash command sadece fallback ve debug yuzeyi.

## Urun modeli

### 1. Gorunen katman: Context HUD

Kullanicinin editor icinde surekli gordugu ozet.

Beklenen bloklar:

1. `Now`
   - son 15 dk
   - en cok degisen dosyalar
   - aktif branch
   - local change ozeti
2. `Session`
   - son 5 saat
   - bugunun calisma temasi
   - odak klasorleri
   - son anlamli donus noktasi
3. `Week`
   - son 7 gun
   - tekrar eden is basliklari
   - iliskili dosya alanlari
   - acik kalan is parcasi

### 2. Gorunmeyen katman: Automatic Assistant Context

Assistant mesaja cevap verirken bu hafizayi bilsin.

Istenen davranis:

- kullanici konuyu yarim cumleyle acsa bile baglami kacirmasin
- "dun ne yapiyorduk?" ve "bu branch'te ne degisti?" gibi sorulara direkt cevap verebilsin
- son 5 saatlik odagi ve haftalik calisma cizgisini koruyabilsin

### 3. Fallback katman: Manual Injection

Otomatik baglama basarisiz veya kisitliysa kullanilacak mekanizma.

Ornek:

- `/hello`
- ileride `/brief`

Bu urunun cekirdegi degildir.

## Fazlara bolunmus yaklasim

### Faz 0: API doğrulama

Amaç:

- slash command yüzeyini çalıştırmak
- worktree bilgisini Assistant içine akıtmak

Çıktı:

- `/hello` komutu

Beklenen davranış:

- aktif worktree yolunu okur
- Assistant içine kısa bir metin enjekte eder

### Faz 1: Context Engine

Amaç:

- zaman pencereli yuksek sinyal hafiza uretmek

Zaman pencereleri:

1. `now`: son 15 dakika
2. `session`: son 5 saat
3. `week`: son 7 gun

Toplanacak sinyaller:

1. aktif worktree yolu
2. aktif branch
3. son commitler ve konu ozetleri
4. staged / unstaged degisiklikler
5. son N dakikada dokunulan dosyalar
6. son 5 saatte yogunlasilan klasorler
7. son 7 gunde tekrar eden is temalari
8. varsa diagnostics ozeti
9. assistant konusma hafizasi ozetleri

Teknik yöntem:

- `Worktree::root_path()`
- `process:exec` ile `git`
- gerekiyorsa dosya mtime taramasi
- yerel state dosyalari

Uretilecek artefaktlar:

- `.zed-context/state.json`
- `.zed-context/brief-now.md`
- `.zed-context/brief-session.md`
- `.zed-context/brief-week.md`

Not:

Ilk implementation'da bile veri modeli HUD odakli olmali. "Tek seferlik briefing" mantigi ana tasarim olmamali.

### Faz 2: HUD Surface

Amaç:

- context'i editor icinde surekli gorunur kilmak

Secenekler:

1. Zed extension UI primitifi varsa dogrudan onu kullanmak
2. Zed icinde mevcut bir yuzeye bindirmek
3. bunun mumkun olmadigi durumda dosya tabanli veya command tabanli bir gecici HUD uretmek

Risk:

- arastirma asamasinda persistent custom HUD API'si dogrulanmadi

Bu yuzden HUD entegrasyonu "dogrudan", "uyarlanmis", "fallback" diye katmanlanmali.

### Faz 3: Automatic Assistant Context

Amaç:

- assistant'in bu hafizayi varsayilan olarak kullanmasi

Secenekler:

1. resmi otomatik prompt/context hook'u varsa onu kullanmak
2. prompt override hattina baglanmak
3. MCP/tool mantigiyla modele bu hafizayi cekmeyi ogretmek
4. hicbiri olmazsa fallback injection kullanmak

Risk:

- arastirma sirasinda bu ihtiyac icin net bir extension hook'u dogrulanmadi

### Faz 4: Fallback slash commands

Amaç:

- otomatik entegrasyon olmadiginda hizli kurtarma mekanizmasi sunmak

Örnek çıktı şablonu:

```md
## Project Brief

- Worktree: /Users/ozlu/projeler/hususi/backend/zed-context
- Branch: main

### Recent Commits
- abc123 Fix slash command registration
- def456 Add worktree summary
- ghi789 Write architecture notes

### Local Changes
- modified: src/lib.rs
- added: docs/02-architecture.md
```

## Veri modeli

Onerilen `state.json` iskeleti:

```json
{
  "worktree_root": "/path/to/project",
  "branch": "main",
  "updated_at": "2026-05-11T10:00:00Z",
  "now": {
    "window_minutes": 15,
    "top_files": [],
    "change_summary": [],
    "diagnostics_summary": null
  },
  "session": {
    "window_hours": 5,
    "focus_areas": [],
    "themes": [],
    "resume_hint": ""
  },
  "week": {
    "window_days": 7,
    "themes": [],
    "hot_paths": [],
    "open_loops": []
  },
  "assistant_memory": {
    "latest_summary": "",
    "thread_refs": []
  }
}
```

## Kararlar

### Neden slash command ana urun degil?

- kullanici beklentisi sifir ek efor
- HUD hissi surekli gorunurluk ister
- tek komutla inject etmek "where was I?" problemini tam cozmez

### Neden once context engine?

- UI ve prompt hook belirsiz olsa bile cekirdek deger burada
- entegrasyon yollari degisse de veri modeli korunur
- baska oturumda implementasyonu parcali sekilde yaptirmayi kolaylastirir

### Neden zaman pencereleri?

- Claude HUD hissinin cekirdegi sureklilik ve ritim
- "simdi", "bugun", "bu hafta" farkli bilissel ihtiyaclari karsilar
- assistant'in cevabini sadece son diff'e degil, calisma egilimine baglar

### Neden once `git` tabanli sinyal?

- guvenilir
- deterministik
- extension API ile uyumlu gorunmesi daha olasi

### Neden surekli watcher ile baslamiyoruz?

- ilk surumde asiri entegrasyon riski var
- veri modelini once dogrulamak daha onemli
- watcher daha sonra engine'e eklenebilir

## Minimal dosya yapısı

```text
zed-context/
  extension.toml
  Cargo.toml
  src/
    lib.rs
  docs/
    01-research.md
    02-architecture.md
```

## Sonraki teknik adimlar

1. context engine modulunu tasarla
2. `state.json` ve markdown brief uretimini ekle
3. `now/session/week` ozetleyicilerini ayri fonksiyonlar halinde yaz
4. `process:exec` capability gereksinimini manifest ve kullanici dokumantasyonuna yaz
5. HUD yuzeyi icin Zed entegrasyon noktasini arastir
6. otomatik assistant context hook'u icin Zed entegrasyon noktasini arastir
7. fallback slash command'leri en son tamamla

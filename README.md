# Zed Context Pilot

`Zed Context Pilot`, Claude HUD benzeri "terminalde farkindalik" hissini Zed'in icine tasimayi hedefleyen bir extension prototipidir.

Ana urun hedefi:

- always-on context HUD
- otomatik assistant context
- zaman pencereli ozetler:
  - `now`: son 15 dakika
  - `session`: son 5 saat
  - `week`: son 7 gun

Ilk milestone:

- Zed extension iskeleti
- `/hello` slash command ile API dogrulamasi
- dogrulanmis arastirma notlari
- sonraki fazlar icin HUD-first mimari plan

Dokumanlar:

- [docs/01-research.md](docs/01-research.md)
- [docs/02-architecture.md](docs/02-architecture.md)
- [docs/03-implementation-prompt.md](docs/03-implementation-prompt.md)

## Urun cizgisi

`/brief` ana urun degil, fallback mekanizmasidir.

Asil hedef:

1. context'in surekli gorunur olmasi
2. assistant'in bu context'i varsayilan olarak kullanmasi
3. kullanicinin "nerede kalmistim?" sorusuna anlik, oturumluk ve haftalik cevap verilmesi

## Geliştirme

Zed içinde dev extension olarak yüklemek için bu klasörü seç:

1. `cmd-shift-x`
2. `Install Dev Extension`
3. bu dizini seç

Debug için:

- `zed: open log`
- terminalden `zed --foreground`

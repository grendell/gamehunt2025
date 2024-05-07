.segment "RODATA"
palettes:
; https://www.nesdev.org/wiki/PPU_palettes
  ; background palettes
  .byte $00, $0f, $2a, $20
  .byte $00, $00, $00, $00
  .byte $00, $00, $00, $00
  .byte $00, $00, $00, $00

  ; sprite palettes
  .byte $00, $0f, $16, $36
  .byte $00, $0f, $11, $36
  .byte $00, $0f, $20, $2a
  .byte $00, $00, $00, $00

initial_oam:
  ; player
  .byte 111, $06, 0, 120
  .byte 111, $07, 0, 128
  .byte 119, $16, 1, 120
  .byte 119, $17, 1, 128

  ; qr code
  .byte 200, $20, 2, 217
  .byte 200, $21, 2, 225
  .byte 200, $22, 2, 233
  .byte 200, $23, 2, 241
  .byte 208, $30, 2, 217
  .byte 208, $31, 2, 225
  .byte 208, $32, 2, 233
  .byte 208, $33, 2, 241
  .byte 216, $40, 2, 217
  .byte 216, $41, 2, 225
  .byte 216, $42, 2, 233
  .byte 216, $43, 2, 241
  .byte 224, $50, 2, 217
  .byte 224, $51, 2, 225
  .byte 224, $52, 2, 233
  .byte 224, $53, 2, 241

  ; thought bubble
  .byte 101, $24, 2, 134
  .byte 101, $25, 2, 142
  .byte 109, $34, 2, 134
  .byte 109, $35, 2, 142

nametable1:
  .incbin "nametable1.nam"

nametable2:
  .incbin "nametable2.nam"

.segment "CHARS"
  .incbin "patterntable.chr"
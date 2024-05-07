.segment "HEADER"
; https://www.nesdev.org/wiki/INES
  .byte $4e, $45, $53, $1a ; iNES header identifier
  .byte $01                ; 1x 16KB PRG code
  .byte $01                ; 1x  8KB CHR data
  .byte $01                ; mapper 0 and vertical mirroring
  .byte $00                ; mapper 0

.segment "VECTORS"
  .addr nmi, reset, 0

.segment "ZEROPAGE"
nametable_ptr: .res 2

joy1_current: .res 1
joy1_previous: .res 1

ppu_ctrl: .res 1
scroll_x: .res 1
scroll_y: .res 1

walk_cycle_sprite: .res 1
sprite_timer: .res 1

show_bubble: .res 1

waiting_for_nmi: .res 1

.include "system.inc"
.include "data.inc"

.segment "CODE"
; memory map
;   $00 -   $ff: zero page (fast-access variables)
; $0100 - $01ff: stack (program flow)
; $0200 - $02ff: OAM shadow (next sprite update)
; $0300 - $07ff: unused
OAM_SHADOW = $0200

; sprites will animate every 16 / 60 of a second
SPRITE_MASK = %00010000

; second frames always start at an offset of 2 in the pattern table
SECOND_FRAME_OFFSET = 2

OAM_BUBBLE_OFFSET = 80
OAM_SIZE = 96

; player must be within 14 pixels in either direction to find the game
SEARCH_DISTANCE = 14

HIDDEN_CART_NT = 1
HIDDEN_CART_X = 80
HIDDEN_CART_Y = 176

; sprite mappings for directional animations
.enum
  UP = 0
  DOWN = 4
  LEFT = 8
  RIGHT = 12
  NONE = $ff
.endenum

.proc reset
  ; https://www.nesdev.org/wiki/Init_code
  sei                    ; ignore IRQs
  cld                    ; disable decimal mode
  ldx #$40
  stx APU_FRAME_COUNTER  ; disable APU frame IRQ
  ldx #$ff
  txs                    ; Set up stack
  inx                    ; now X = 0
  stx PPU_CTRL           ; disable NMI
  stx PPU_MASK           ; disable rendering
  stx DMC_FREQ           ; disable DMC IRQs

  ; clear vblank flag
  bit PPU_STATUS

  ; wait for first vblank
: bit PPU_STATUS
  bpl :-

  ; initialize cpu variables
  lda #0
  sta scroll_x
  sta sprite_timer
  sta waiting_for_nmi

  lda #236
  sta scroll_y

  lda #1
  sta show_bubble

  jsr init_audio

  ; wait for second vblank
: bit PPU_STATUS
  bpl :-

  ; initialize ppu
  jsr init_palettes
  jsr init_nametables
  jsr init_sprites

  ; initialize background scroll position
  lda scroll_x
  sta PPU_SCROLL
  lda scroll_y
  sta PPU_SCROLL

  ; enable NMI and select pattern tables
  ;           00 - base nametable
  ;          0   - vram update direction
  ;         1    - sprite pattern table
  ;        0     - background pattern table
  ;       0      - 8x8 sprite size
  ;      0       - default EXT pin behavior - never enable on NES!
  ;     1        - enable vblank NMI
  lda #%10001000
  sta ppu_ctrl
  sta PPU_CTRL

game_loop:
  ; wait for frame to be completed
  inc waiting_for_nmi
: lda waiting_for_nmi
  bne :-

  jsr handle_input
  jsr update_animation

  jmp game_loop
.endproc

.proc nmi
  ; retain previous value of a on the stack
  pha

  ; clear vblank flag
  bit PPU_STATUS

  ; update sprite OAM via DMA
  lda #>OAM_SHADOW
  sta OAM_DMA

  ; show backgrounds and sprites, including leftmost 8 pixels
  ;            0 - disable grayscale rendering
  ;           1  - show background in left-most 8 pixels on screen
  ;          1   - show sprites in left-most 8 pixels on screen
  ;         1    - draw backgrounds
  ;        1     - draw sprites
  ;       0      - disable red emphasis
  ;      0       - disable green emphasis
  ;     0        - disable blue emphasis
  lda #%00011110
  sta PPU_MASK

  ; update background scroll position
  lda scroll_x
  sta PPU_SCROLL
  lda scroll_y
  sta PPU_SCROLL

  ; update base nametable
  lda ppu_ctrl
  sta PPU_CTRL

  ; allow game loop to continue after interrupt
  lda #0
  sta waiting_for_nmi

  ; restore previous value of a before interrupt
  pla
  rti
.endproc

.proc init_palettes
  ; set ppu address to palette entries ($3f00)
  lda #$3f
  sta PPU_ADDR
  lda #0
  sta PPU_ADDR

  ; loop through each palette entry, 32 total
  ldx #0
: lda palettes, x
  sta PPU_DATA
  inx
  cpx #32
  bne :-

  rts
.endproc

.proc init_nametables
  ; set ppu address to first nametable ($2000)
  lda #$20
  sta PPU_ADDR
  lda #0
  sta PPU_ADDR

  ; set nametable pointer to first nametable data
  lda #<nametable1
  sta nametable_ptr
  lda #>nametable1
  sta nametable_ptr + 1

  ldx #4
  ldy #0
  ; use nametable pointer + offset to look up next tile
: lda (nametable_ptr), y
  sta PPU_DATA

  iny
  bne :-

  ; move pointer to next 256 tiles
  inc nametable_ptr + 1
  dex
  bne :-

  ; set nametable pointer to second nametable data
  lda #<nametable2
  sta nametable_ptr
  lda #>nametable2
  sta nametable_ptr + 1

  ldx #4
  ldy #0
  ; use nametable pointer + offset to look up next tile
: lda (nametable_ptr), y
  sta PPU_DATA

  iny
  bne :-

  ; move pointer to next 256 tiles
  inc nametable_ptr + 1
  dex
  bne :-

  rts
.endproc

.proc init_sprites
  ; set initial contents of the OAM shadow
  ; this copy will be sent to the PPU during NMI
  ldx #0
: lda initial_oam, x
  sta OAM_SHADOW, x

  inx
  cpx #OAM_SIZE
  bne :-

  ; move the rest of the buffer off-screen
  lda #$ff
: sta OAM_SHADOW, x
  inx
  bne :-

  rts
.endproc

.proc init_audio
  ; mute pulse channel 1
  lda #0
  sta SQ1_VOL
  sta SQ1_SWEEP
  sta SQ1_LO
  sta SQ1_HI

  ; mute noise channel
  sta NOISE_VOL
  sta NOISE_LO
  sta NOISE_HI

  ; enable pulse 1 and noise
  ;            1 - enable pulse 1
  ;           0  - disable pulse 2
  ;          0   - disable triangle
  ;         1    - enable noise
  ;        0     - disable DMC
  ;     000      - unused
  lda #%00001001
  sta SND_CHN

  rts
.endproc

.proc read_joypad
  ; https://www.nesdev.org/wiki/Controller_reading_code
  ; progress previous button state
  lda joy1_current
  sta joy1_previous

  ; initialize ring buffer
  lda #1
  sta joy1_current

  ; strobe joypad to record latest state
  sta JOY_STROBE
  lsr
  sta JOY_STROBE

: lda JOY1         ; read next button state
  lsr              ; bit 0 -> carry
  rol joy1_current ; carry -> bit 0, bit 7 -> carry
  bcc :-

  rts
.endproc

.proc handle_input
  jsr read_joypad

  lda #NONE
  sta walk_cycle_sprite

  ; is A currently pressed?
  lda joy1_current
  and #BUTTON_A
  beq :+

  ; was A just pressed?
  lda joy1_previous
  and #BUTTON_A
  bne :+

  jsr check_cart

  ; is B currently pressed?
: lda joy1_current
  and #BUTTON_B
  beq :+

  ; was B just pressed?
  lda joy1_previous
  and #BUTTON_B
  bne :+

  jsr toggle_bubble

  ; is up currently pressed?
: lda joy1_current
  and #BUTTON_UP
  beq :+

  jsr move_up

  ; is down currently pressed?
: lda joy1_current
  and #BUTTON_DOWN
  beq :+

  jsr move_down

  ; is left currently pressed?
: lda joy1_current
  and #BUTTON_LEFT
  beq :+

  jsr move_left

  ; is right currently pressed?
: lda joy1_current
  and #BUTTON_RIGHT
  beq :+

  jsr move_right

: rts
.endproc

.proc check_cart
  ; are we in the right nametable?
  lda ppu_ctrl
  and #1

  cmp #HIDDEN_CART_NT
  bne play_failure

  ; are we close enough horizontally?
  ; a = player_x - cart_x
  lda scroll_x
  sec
  sbc #HIDDEN_CART_X

  ; a = |a| (absolute value)
  jsr abs

  ; is a < SEARCH_DISTANCE?
  cmp #SEARCH_DISTANCE
  bcs play_failure

  ; are we close enough vertically?
  ; a = player_y - cart_y
  lda scroll_y
  sec
  sbc #HIDDEN_CART_Y

  ; a = |a| (absolute value)
  jsr abs

  ; is a < SEARCH_DISTANCE?
  cmp #SEARCH_DISTANCE
  bcs play_failure

  jmp play_success
.endproc

.proc abs
  ; check if negative
  asl ; bit 7 -> carry
  bcs :+

  ; a is positive, restore value and return
  ror ; carry -> bit 7
  rts

  ; a is negative, restore value and negate
: ror ; carry -> bit 7

  ; apply two's complement to negate
  ; https://en.wikipedia.org/wiki/Two%27s_complement
  eor #$ff
  clc
  adc #1
  rts
.endproc

.proc play_success
  ; https://www.nesdev.org/wiki/APU_period_table
  ; $00e2 == B4
  lda #$e2 ; lo byte of $00e2
  sta SQ1_LO

  ; https://www.nesdev.org/wiki/APU_Length_Counter
  ; $00e2 == B4
  ; half note @ 75 bpm (NTSC)
  ;          000 - hi bits of $00e2
  ;     10110    - half note @ 75 bpm (NTSC)
  lda #%10110000
  sta SQ1_HI

  ; 50% duty, length counter halted,
  ; constant volume, 50% volume
  ;         0111 - 50% volume
  ;        1     - constant volume
  ;       0      - update length counter
  ;     10       - 50% duty
  lda #%10010111
  sta SQ1_VOL

  rts
.endproc

.proc play_failure
  ; https://www.nesdev.org/wiki/APU_Noise
  ; short-loop mode and period of %1000
  ;         1000 - period
  ;      000     - unused
  ;     1        - enable short-loop
  lda #%10001000
  sta NOISE_LO

  ; quarter note @ 75 bpm (NTSC)
  ;          000 - unused
  ;     10100    - quarter note @ 75 bpm (NTSC)
  lda #%10100000
  sta NOISE_HI

  ; length counter halted,
  ; constant volume, 50% volume
  ;         0111 - 50% volume
  ;        1     - constant volume
  ;       0      - update length counter
  ;     00       - unused
  lda #%00010111
  sta NOISE_VOL

  rts
.endproc

.proc toggle_bubble
  ldx #OAM_BUBBLE_OFFSET

  ; flip bubble visibility
  lda show_bubble
  eor #1
  sta show_bubble
  beq hide

show:
  ; restore initial OAM y values for the bubble
: lda initial_oam, x
  sta OAM_SHADOW, x

  txa
  clc
  adc #.sizeof(sprite)
  tax

  cpx #OAM_SIZE
  bne :-
  rts

hide:
  ; clear OAM y values for the bubble
: lda #$ff
  sta OAM_SHADOW, x

  txa
  clc
  adc #.sizeof(sprite)
  tax

  cpx #OAM_SIZE
  bne :-
  rts
.endproc

.proc move_up
  lda #UP
  sta walk_cycle_sprite

  dec scroll_y

  ; is y == 255?
  lda scroll_y
  cmp #255
  bne :+

  ; wrap y to 239
  lda #239
  sta scroll_y

: rts
.endproc

.proc move_down
  lda #DOWN
  sta walk_cycle_sprite

  inc scroll_y

  ; is y == 240?
  lda scroll_y
  cmp #240
  bne :+

  ; wrap y to 0
  lda #0
  sta scroll_y

: rts
.endproc

.proc move_left
  lda #LEFT
  sta walk_cycle_sprite

  dec scroll_x

  ; is y == 255?
  lda scroll_x
  cmp #255
  bne :+

  ; flip base nametable
  lda ppu_ctrl
  eor #1
  sta ppu_ctrl

: rts
.endproc

.proc move_right
  lda #RIGHT
  sta walk_cycle_sprite

  inc scroll_x

  ; is x == 0?
  lda scroll_x
  ; no need to cmp #0, lda sets the zero flag
  bne :+

  ; flip base nametable
  lda ppu_ctrl
  eor #1
  sta ppu_ctrl

: rts
.endproc

.proc update_animation
  lda walk_cycle_sprite
  cmp #NONE
  beq reset_timer

  ; sprite timer:   %abcdefgh
  ; SPRITE_MASK:  & %00010000
  ;                 ---------
  ;                 %000d0000
  ;
  ; since sprite_timer increments 60 times per second,
  ; and %10000 == 16, d will flip every 16 / 60 of a second

  lda sprite_timer
  and #SPRITE_MASK
  bne second_frame
  jmp animate

second_frame:
  lda walk_cycle_sprite
  ; here, walk_cycle_sprite is guaranteed to be %0000xx00,
  ; so ora acts as a cheaper add without carry
  ora #SECOND_FRAME_OFFSET
  sta walk_cycle_sprite

animate:
  ; set the top-left sprite of the character
  lda walk_cycle_sprite
  sta OAM_SHADOW + sprite::tile

  ; the top-right sprite is always +1 of the top-left
  ora #$01
  sta OAM_SHADOW + .sizeof(sprite) + sprite::tile

  ; the bottom-left sprite is always +$10 of the top-left
  lda walk_cycle_sprite
  ora #$10
  sta OAM_SHADOW + 2 * .sizeof(sprite) + sprite::tile

  ; the bottom-right sprite is always +1 of the bottom-left
  ora #$01
  sta OAM_SHADOW + 3 * .sizeof(sprite) + sprite::tile

  inc sprite_timer
  rts

reset_timer:
  lda #0
  sta sprite_timer
  rts
.endproc
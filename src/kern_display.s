.include "constants.inc.s"

.section .ktext
.global init_display
;; Initialize LCD
init_display:
    push af
    ld a, 1 + LCD_CMD_SETDISPLAY
    call lcd_busy_loop
    out (PORT_LCD_CMD), a ; Enable screen

    ld a, 7 + LCD_CMD_POWERSUPPLY_SETLEVEL ; versus +3? TIOS uses +7, and that's the only value that works (the datasheet says go with +3)
    call lcd_busy_loop
    out (PORT_LCD_CMD), a ; Op-amp control (OPA1) set to max (with DB1 set for some reason)

    ld a, 3 + LCD_CMD_POWERSUPPLY_SETENHANCEMENT ; B
    call lcd_busy_loop
    out (PORT_LCD_CMD), a ; Op-amp control (OPA2) set to max

    ld a, 1 + LCD_CMD_AUTOINCDEC_SETX
    call lcd_busy_loop
    out (PORT_LCD_CMD), a       ; X-Increment Mode (vertical)

    ld a, 0x3F + LCD_CMD_SETCONTRAST
    call lcd_busy_loop
    out (PORT_LCD_CMD), a ; Contrast

    pop af
    ret

.global init_text
;; Initialize LCD for text mode
init_text:
    push af
    in a, (PORT_LCD_CMD)        ; Check if already in text mode.
    and LCD_CMD_8BITS
    jp z, 1f

    ld a, 0 + LCD_CMD_SETOUTPUTMODE
    call lcd_busy_loop
    out (PORT_LCD_CMD), a       ; 6-bit mode
1:  pop af
    ret

.global init_graphic
;; Initialize LCD for graphical mode
init_graphic:
    push af
    in a, (PORT_LCD_CMD)        ; Check if already in graphic mode.
    and LCD_CMD_8BITS
    jp nz, 1f

    ld a, 1 + LCD_CMD_SETOUTPUTMODE
    call lcd_busy_loop
    out (PORT_LCD_CMD), a       ; 8-bit mode
1:  pop af
    ret

.global putc
;; putc
;;  Translate a character to a glyph and insert
;;  it into the buffer at current location.
;; Inputs:
;;  A: Character to print
;;  DE: Base address of glyph buffer
;;  BC: Offset into glyph buffer (in characters)
;; Outputs:
;;  BC: New offset into glyph buffer
putc:
    push af
    push hl

    cp 0x0A         ; if LF
    call z, newline
    jp z, 2f

    cp 0x0D         ; if CR
    call z, carriage
    jp z, 2f

    cp 0x0C         ; if FF
    call z, scroll
    jp z, 2f

    push bc

    ld  h, d        ; set position
    ld  l, e
    rl  c           ; 1 character = 2 bytes
    add hl, bc

    pop bc

    push de

    push hl

    sub 0x20        ; Subtract 32 from a.
    ld hl, font
    jp c, 1f        ; If result is negative, print blank.

    ld h, 0
    ld l, a

    ld d, 0
    ld e, a

    add hl, hl      ; Double hl (x2)
    add hl, hl      ; Double hl (x4)
    add hl, de      ; a + hl (x5)
    ld de, font
    add hl, de      ; Add base address to offset

    ex de, hl       ; Glyph pointer now in de.

1:  pop hl

    ld (hl), d      ; Store glyph pointer in buffer.
    inc hl
    ld (hl), e

    pop de

    inc bc          ; Next character
2:
    ld a, c
    cp 0x80         ; Is buffer offset overflowed?
    jp c, 3f        ; If not, return.

    call scroll     ; Else, scroll
    ld bc, 0x70     ; Reset to start of last line.

3:
    pop hl
    pop af
    ret

newline:
    push af
    push hl

    ld a, c
    cp 0x70       ; if on last line
    jp c, 1f
    call scroll   ; scroll instead of newline
    jp 2f
1:

    ld hl, 16
    add hl, bc  ; Increment by 16.
    ld b, h
    ld c, l

2:  pop hl
    pop af
    ret

carriage:
    push af

    ld a, 0xF0
    and c
    ld c, a         ; Round to lower 16.

    pop af
    ret

scroll:
    push af
    push hl
    push de
    push bc

    ld bc, 224      ; Copy rows 1-7 to 0-6
    ld hl, 32
    add hl, de
    ldir

    ld bc, 32       ; Clear last row.
    ld (hl), 0x00

    ldir

    pop bc
    pop de
    pop hl
    pop af
    ret

.global puts
;; puts
;;  Copies a string to the glyph buffer.
;; Inputs:
;;  DE: Base address of glyph buffer
;;  BC: Offset into glyph buffer
;;  IY: Text buffer (byte per character)
;; Outputs:
;;  BC: Ending address in glyph buffer
puts:
    push iy
    push hl
    push de
    push af
    di
1: ; Next character
        ld a, (iy)      ; Load character code.
        cp 0
        jp z, 2f        ; if 0, end of string.

        call putc       ; Put character in buffer.

        inc iy          ; Advance to next character
        jp 1b
2: ; End loop.
    ei
    pop af
    pop de
    pop hl
    pop iy
    ret

.global putg
;; putg
;;  Displays a character 5x6 glyph on the LCD.
;; Inputs:
;;  DE: Glyph to print
;;  B: Starting line (in Pixels)
;;  C: Starting column (in column)
;; Outputs:
;;  None
putg:
    push af
    push hl
    push bc
    push de
    ;; Test for NULL ptr.
    ld a, d
    cp 0
    jp nz, 1f

    ld a, e
    cp 0
    jp nz, 1f

    ld de, font   ; Print blank on null ptr.

1:
        di
        call init_text
    ; Set column
        ld a, c
        add a, LCD_CMD_SETCOLUMN
        call lcd_busy_loop
        out (PORT_LCD_CMD), a

    ; Set row
        ld a, b
        inc a
        add a, LCD_CMD_SETROW
        call lcd_busy_loop
        out (PORT_LCD_CMD), a

        push bc

        ld b,5
2: ; Draw character
        ld a, (de)

        call lcd_busy_loop
        out (PORT_LCD_DATA), a
        inc de
        djnz 2b     ; Advance to next row.

        pop bc

    ; Set row back to initial position.
        ld a, b
        add a, LCD_CMD_SETROW
        call lcd_busy_loop
        out (PORT_LCD_CMD), a
        ei
3:  pop de
    pop bc
    pop hl
    pop af
    ret

.global display_glyphs
;; display_graphic
;;  Copies a glyph buffer to the LCD.
;; Inputs:
;;  DE: Glyph pointer buffer (2 bytes per glyph)
;; NOTE:
;;  Length is assumed to be 128 glyphs (256 bytes).
display_glyphs:
    push af
    push hl
    push de
    push bc

    ex de, hl                   ; HL now contains address of starting glyph pointer.
    ld bc, 0                    ; B - line, C - column

1:  ; Start glyph loop
    ld d, (hl)
    inc hl
    ld e, (hl)                  ; DE now contains glyph pointer.
    inc hl                      ; HL now contains address of next glyph pointer.

    call putg

    inc c
    ld a, c

    cp 0x10                     ; Check if newline.
    jp c, 1b

    ld c, 0                     ; Advance to next line.
    ld a, b
    add a, 8
    ld b, a

    cp 0x40                     ; Check if end of buffer
    jp c, 1b

    pop bc
    pop de
    pop hl
    pop af
    ret


.global display_graphic
;; display_graphic
;;  Copies a screen buffer to the LCD.
;; Inputs:
;;  IY: Screen buffer (bit per pixel)
display_graphic:
        push hl
        push bc
        push af
        push de
            di
            call init_graphic
            ld a, i
            push af
                push iy
                pop hl

                ld a, LCD_CMD_SETROW
                call lcd_busy_loop
                out (PORT_LCD_CMD), a

                ld de, 12
                ld a, LCD_CMD_SETCOLUMN
1: ; Set column
                call lcd_busy_loop
                out (PORT_LCD_CMD),a

                push af
                    ld b,64
2: ; Draw row
                    ld a, (hl)
                    call lcd_busy_loop
                    out (PORT_LCD_DATA), a
                    add hl, de
                    djnz 2b
                pop af
                dec h
                dec h
                dec h
                inc hl
                inc a
                cp 0x0C + LCD_CMD_SETCOLUMN
                jp nz, 1b
            pop af
            ei
    pop de
    pop af
    pop bc
    pop hl
    ret

.global lcd_busy_loop
;; lcd_busy_loop
;;  Waits for LCD to become ready.
;; Inputs:
;;  None
lcd_busy_loop:
    push bc
    ld c, PORT_LCD_CMD
1:
    in b, (c)    ;bit 7 set if LCD is busy
    jp m, 1b     ;repeat if bit 7 (sign bit) set.
    pop bc
    ret

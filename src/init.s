.section .init
init:
    call init_display

    ;; Set screen buffer to pattern.
    ld hl, gfx_buffer
    push hl

    ld (hl), 0xFF
    ld de, gfx_buffer+1
    ld bc, gfx_buffer_len-1
    ldir

    inc bc
    pop iy
    call display_graphic

    ;; Display message
    ld de, glyph_buffer
    ld bc, 0x02
    ld iy, message
    call puts
    ld bc, 0x10

repl:
    ld de, glyph_buffer
    call display_glyphs
    call get_key
    cp 0x00
    jp nz, print

    jp repl

print:
    cp 0xFF
    jp nz, 1f
    call poweroff
    jp repl
1:

    cp 0x0A                     ; if LF
    jp nz, 1f
    call putc
    jp repl
1:

    cp 0x0D                     ; if NL
    jp nz, 1f
    call putc
    jp repl
1:

    cp 0x08                     ; Remap delete to form feed (scroll).
    jp nz, 1f
    ld a, 0x0C
    call putc
    jp repl
1:

    cp 0x20                     ; Ignore invalid or null keys.
    jp c, repl

    cp 0x80                     ; Ignore invalid or null keys.
    jp nc, repl

    call putc

    call link_putc              ; Output over link port.
    call update_link_stat       ; Update link status display.

    jp repl

end:jr $

update_link_stat:
    push af
    push bc
    ld bc, 0x00
    or a
    jp nz, 1f

    ld a, '.'                   ; Success = .
    jp 2f

1:  ld a, '!'                   ; Failed = !

2:  call putc
    pop bc
    pop af
    ret


.section .data
message:
    .db "It works!",0

.section .bss
gfx_buffer:
    .skip 768
gfx_buffer_len equ $ - gfx_buffer

glyph_buffer:
    .skip 256
glyph_buffer_len equ $ - glyph_buffer
glyph_buffer_end equ $

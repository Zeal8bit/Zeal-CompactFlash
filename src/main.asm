; SPDX-FileCopyrightText: 2023 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: CC0-1.0

    ; Include the Zeal 8-bit OS header file, containing all the syscalls macros.
    INCLUDE "zos_sys.asm"

    ; Make the code start at 0x4000, as requested by the kernel
    ORG 0x4000

    DEFC CF_IO_ADDR     = 0x70
    DEFC CF_REG_DATA    = CF_IO_ADDR + 0
    ; Error and feature registers are the same
    DEFC CF_REG_ERROR   = CF_IO_ADDR + 1    ; RO
    DEFC CF_REG_FEATURE = CF_IO_ADDR + 1    ; WO
    DEFC CF_REG_SEC_CNT = CF_IO_ADDR + 2
    DEFC CF_REG_LBA_0   = CF_IO_ADDR + 3
    DEFC CF_REG_LBA_8   = CF_IO_ADDR + 4
    DEFC CF_REG_LBA_16  = CF_IO_ADDR + 5
    DEFC CF_REG_LBA_24  = CF_IO_ADDR + 6

    ; For the command register, define the ones we are interested in
    DEFC CF_REG_COMMAND = CF_IO_ADDR + 7    ; WO
    DEFC COMMAND_READ_SECTORS  = 0x20
    DEFC COMMAND_READ_BUFFER   = 0xE4
    DEFC COMMAND_IDENTIFY_DRV  = 0xEC
    DEFC COMMAND_SET_FEATURES  = 0xEF

    ; For the status register, define the different bit
    DEFC CF_REG_STATUS  = CF_IO_ADDR + 7    ; RO
    DEFC STATUS_BUSY_BIT = 7
    DEFC STATUS_RDY_BIT  = 6
    DEFC STATUS_DWF_BIT  = 5
    DEFC STATUS_DSC_BIT  = 4
    DEFC STATUS_DRQ_BIT  = 3
    DEFC STATUS_CORR_BIT = 2
    DEFC STATUS_ERR_BIT  = 0

    ; For the feature register, the different possibilities
    DEFC FEATURE_ENABLE_8_BIT  = 0x1
    DEFC FEATURE_DISABLE_8_BIT = 0x81


_start:
    ; Wait for the ready bit
    S_WRITE3(DEV_STDOUT, _start_msg, _start_msg_end - _start_msg)
    call wait_for_ready
    S_WRITE3(DEV_STDOUT, _ready_msg, _ready_msg_end - _ready_msg)
    ; Write "Enable 8-bit mode" feature in feature register
    ld a, FEATURE_ENABLE_8_BIT
    out (CF_REG_FEATURE), a
    ; Issue a "Set feature" command
    ld a, COMMAND_SET_FEATURES
    out (CF_REG_COMMAND), a
    ; Wait for the CF to be ready again
    call wait_for_ready
    ; Make sure A is 0, else return an error
    or a
    jr nz, cf_error_occurred
    S_WRITE3(DEV_STDOUT, _read_msg, _read_msg_end - _read_msg)
    ; No error so far, let's read the first block
    xor a
    out (CF_REG_LBA_0), a
    out (CF_REG_LBA_8), a
    out (CF_REG_LBA_16), a
    ; For LBA_24 register, we must set the upper 3 bits
    or 0xE0
    out (CF_REG_LBA_24), a
    ; Number of sectors to read: 1
    ld a, 1
    out (CF_REG_SEC_CNT), a
    ; Issue a read sector command
    ld a, COMMAND_READ_SECTORS
    out (CF_REG_COMMAND), a
    ; Wait for the disk to be ready
    call wait_for_ready
    or a
    jr nz, cf_error_occurred
    ; Once its ready, the content is stored in the CompactFlash internal buffer
    ; Read this buffer thanks to ... a command again
    ld a, COMMAND_READ_BUFFER
    out (CF_REG_COMMAND), a
    call wait_for_ready
    or a
    jr nz, cf_error_occurred
    ; We can start reading the data. In our case, we will only read the first
    ; 256 bytes, even though 512 bytes are ready.
    ld c, 32
_read_big_loop:
    ld hl, _buffer
    ld b, 16
    ; Store each byte in a buffer, in ASCII format
_read_loop:
    in a, (CF_REG_DATA)
    call byte_to_ascii
    ld (hl), d
    inc hl
    ld (hl), e
    inc hl
    ld (hl), ' '
    inc hl
    djnz _read_loop
    ; Replace the last space by a new line
    dec hl
    ld (hl), '\n'
    ; The buffer should contain 48 characters, print it
    push bc
    S_WRITE3(DEV_STDOUT, _buffer, 48)
    pop bc
    dec c
    jr nz, _read_big_loop
_end:
    ; We MUST execute EXIT() syscall at the end of any program.
    EXIT()

    ; Routine that waits for the CompactFlash to to be ready and not busy.
    ; Once its ready, return check for errors:
    ; Return 0 in A on success, 1 on error
wait_for_ready:
    in a, (CF_REG_STATUS)
    ;call print_a
    ; Check that RDY bit is set and that BUSY bit is not set
    bit STATUS_RDY_BIT, a
    jr z, wait_for_ready
    bit STATUS_BUSY_BIT, a
    jr nz, wait_for_ready
    ; Device is ready, return the error bit in A
    and 1 << STATUS_ERR_BIT
    ret

print_a:
    push af
    call byte_to_ascii
    ld hl, buf
    ld (hl), d
    inc hl
    ld (hl), e
    dec hl
    ex de, hl
    ld bc, 3
    S_WRITE1(DEV_STDOUT)
    pop af
    ret

buf: defm "00\n"


    ; An error occurred during a command, print a message
cf_error_occurred:
    ; Get the error register
    in a, (CF_REG_ERROR)
    ; Convert this value to ASCII (hex)
    call byte_to_ascii
    ld hl, _error_code
    ld (hl), d
    inc hl
    ld (hl), e
    ; Write it to the error message and print it
    S_WRITE3(DEV_STDOUT, _error_msg, _error_msg_end - _error_msg)
    ; Exit the program now
    jr _end

_start_msg: DEFM "Waiting for the CompactFlash RDY bit...\n"
_start_msg_end:
_ready_msg: DEFM "CompactFlash is ready. Activating 8-bit mode...\n"
_ready_msg_end:
_read_msg:  DEFM "Reading first block...\n"
_read_msg_end:
_error_msg: DEFM "Error 0x"
_error_code:
            DEFS 2
            DEFM"\n"
_error_msg_end:

_buffer: DEFS 64


        ; Convert an 8-bit value to ASCII (hex)
        ; Parameters:
        ;       A - Value to convert
        ; Returns:
        ;       D - First character
        ;       E - Second character
        ; Alters:
        ;       A
        PUBLIC byte_to_ascii
byte_to_ascii:
        ld e, a
        rlca
        rlca
        rlca
        rlca
        and 0xf
        call _byte_to_ascii_nibble
        ld d, a
        ld a, e
        and 0xf
        call _byte_to_ascii_nibble
        ld e, a
        ret
_byte_to_ascii_nibble:
        ; If the byte is between 0 and 9 included, add '0'
        sub 10
        jp nc, _byte_to_ascii_af
        ; Byte is between 0 and 9
        add '0' + 10
        ret
_byte_to_ascii_af:
        ; Byte is between A and F
        add 'A'
        ret
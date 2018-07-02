
;; xOS32
;; Copyright (C) 2016-2017 by Omar Mohammad.

use32

com1_port			dw 0
com1_last_byte			db 0
debug_mode			db 0	; when system is in debug mode, kprint puts things on the screen
kprint_type			db KPRINT_TYPE_NORMAL

KPRINT_TYPE_NORMAL		= 0
KPRINT_TYPE_ERROR		= 1
KPRINT_TYPE_WARNING		= 2

; com1_detect:
; Detects the COM1 serial port

com1_detect:
	mov ax, [0x400]
	mov [com1_port], ax

	cmp ax, 0
	je .done

	mov al, 0x1			; interrupt whenever the serial port has data
	mov dx, [com1_port]
	add dx, 1
	out dx, al
	call iowait

	mov al, 0x80			; enable DLAB
	mov dx, [com1_port]
	add dx, 3
	out dx, al
	call iowait

	mov al, 2
	mov dx, [com1_port]
	out dx, al
	call iowait

	mov al, 0
	mov dx, [com1_port]
	add dx, 1
	out dx, al
	call iowait

	mov al, 3			; disable DLAB
	mov dx, [com1_port]
	add dx, 3
	out dx, al
	call iowait

	mov al, 0xC7			; enable FIFO
	mov dx, [com1_port]
	add dx, 2
	out dx, al
	call iowait

	mov esi, kernel_version
	call kprint
	mov esi, newline
	call kprint

.done:
	ret

; com1_wait:
; Waits for COM1 port to receive data

com1_wait:
	pusha

.loop:
	mov dx, [com1_port]
	add dx, 5
	in al, dx
	test al, 0x20
	jz .loop

	popa
	ret

; com1_send_byte:
; Sends a byte via COM1 serial port
; In\	AL = Byte
; Out\	Nothing

com1_send_byte:
	pusha

	mov [com1_last_byte], al

	cmp [debug_mode], 1
	jne .send

	cmp [.escape], 1
	je .is_escape

	cmp al, 0x1B		; escape sequence
	je .skip_escape

.put:
	;mov ebx, 0
	;mov ecx, 0xFFFFFF
	;call set_text_color

	call put_char
	jmp .send

.skip_escape:
	mov [.escape], 1
	jmp .send

.is_escape:
	cmp al, 'm'
	je .end_escape

	jmp .send

.end_escape:
	mov [.escape], 0

.send:
	cmp [com1_port], 0
	je .done

	cmp al, 10
	je .newline
	cmp al, 13
	je .done
	;cmp al, 0x7F
	;jg .done
	;cmp al, 0x20
	;jl .done

	call com1_wait
	mov dx, [com1_port]
	out dx, al

.done:
	popa
	ret

.newline:
	call com1_wait
	mov dx, [com1_port]
	mov al, 13
	out dx, al

	call com1_wait
	mov al, 10
	out dx, al

	mov [com1_last_byte], 10
	popa
	ret

.escape				db 0

; com1_send:
; Sends an ASCIIZ string via COM1
; In\	ESI = String
; Out\	Nothing

com1_send:
	pusha

	;cmp [com1_port], 0
	;je .done

.loop:
	lodsb
	cmp al, 0
	je .done
	call com1_send_byte
	jmp .loop

.done:
	popa
	ret

; kprint:
; Prints a kernel debug message
; In\	ESI = String
; Out\	Nothing

kprint:
	pusha
	cmp [com1_last_byte], 10
	je .timestamp

	call com1_send
	popa
	ret

.timestamp:
	cmp [kprint_type], KPRINT_TYPE_ERROR
	je .error

	cmp [kprint_type], KPRINT_TYPE_WARNING
	je .warning

.normal:
	push esi
	mov al, 0x1B
	call com1_send_byte
	mov al, '['
	call com1_send_byte
	mov al, '1'
	call com1_send_byte
	mov al, ';'
	call com1_send_byte
	mov al, '3'
	call com1_send_byte
	mov al, '4'
	call com1_send_byte
	mov al, 'm'
	call com1_send_byte

	mov al, '['
	call com1_send_byte

	mov eax, [timer_ticks]
	call hex_dword_to_string
	call com1_send

	mov al, ']'
	call com1_send_byte
	jmp .send

.error:
	push esi
	mov al, 0x1B
	call com1_send_byte
	mov al, '['
	call com1_send_byte
	mov al, '1'
	call com1_send_byte
	mov al, ';'
	call com1_send_byte
	mov al, '3'
	call com1_send_byte
	mov al, '1'
	call com1_send_byte
	mov al, 'm'
	call com1_send_byte

	mov al, '['
	call com1_send_byte

	mov eax, [timer_ticks]
	call hex_dword_to_string
	call com1_send

	mov al, ']'
	call com1_send_byte
	jmp .send

.warning:
	push esi
	mov al, 0x1B
	call com1_send_byte
	mov al, '['
	call com1_send_byte
	mov al, '1'
	call com1_send_byte
	mov al, ';'
	call com1_send_byte
	mov al, '3'
	call com1_send_byte
	mov al, '3'
	call com1_send_byte
	mov al, 'm'
	call com1_send_byte

	mov al, '['
	call com1_send_byte

	mov eax, [timer_ticks]
	call hex_dword_to_string
	call com1_send

	mov al, ']'
	call com1_send_byte

.send:
	mov al, 0x1B
	call com1_send_byte
	mov al, '['
	call com1_send_byte
	mov al, '0'
	call com1_send_byte
	mov al, 'm'
	call com1_send_byte

	mov al, ' '
	call com1_send_byte

	pop esi
	call com1_send
	popa
	ret






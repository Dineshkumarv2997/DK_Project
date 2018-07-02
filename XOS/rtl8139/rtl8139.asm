
; RTL8139 Network Driver for xOS
; Copyright (c) 2017 by Omar Mohammad

use32
org 0x80000000		; drivers loaded at 2 GB

application_header:
	.id			db "XOS1"	; tell the kernel we are a valid application
	.type			dd 1		; driver
	.entry			dd main		; entry point
	.pci_ids		dd pci_ids	; list of supported PCI IDs
	.driver_name		dd driver_name
	.reserved0		dq 0

pci_ids:	; list of supported PCI vendor/device combinations, terminated by 0xFFFFFFFF
	dd 0x813910EC		; Realtek 8139, QEMU
	dd 0x81391065		; Texas 8139C, untested
	dd 0x813910BD		; Surecom 8139C, untested
	dd 0x13001186		; D-link 8139-compatible card, untested
	dd 0xAB0614EA		; Planex 8139-compatible card, untested

	; Need help: if anyone knows, help me enter more compatible combinations here!
	dd 0xFFFFFFFF

; Standard Driver Requests
; Requests 2 to 15 are reserved for future expansion
; Device-specific requests range from 16 to infinity..
STD_DRIVER_INIT			= 0x0000
STD_DRIVER_RESET		= 0x0001

; Network-Specific Driver Requests
NET_SEND_PACKET			= 0x0010
NET_RECEIVE_PACKET		= 0x0011
NET_GET_MAC			= 0x0012

RX_BUFFER_SIZE			= 32768		; 32 KB

include				"rtl8139/driver.asm"
include				"rtl8139/string.asm"
include				"rtl8139/registers.asm"
include				"rtl8139/transmit.asm"
include				"rtl8139/receive.asm"

; iowait:
; Waits for an I/O access

iowait:
	out 0x80, al
	out 0x80, al
	ret

; main:
; Entry point of the driver from the kernel
; In\	EAX = Request
; In\	EBX, ECX, EDX, ESI, EDI = Parameters 1, 2, 3, 4, 5
; Out\	EAX = Returned status

main:
	cmp eax, STD_DRIVER_INIT	; initialize the driver?
	je driver_init

	cmp eax, STD_DRIVER_RESET
	je driver_reset

	cmp eax, NET_SEND_PACKET
	je transmit

	cmp eax, NET_RECEIVE_PACKET
	je receive

	cmp eax, NET_GET_MAC
	je get_mac

	push eax

	; unknown request
	mov esi, unknown_msg
	mov ebp, XOS_KPRINT
	int 0x61

	pop eax
	call int_to_string
	mov ebp, XOS_KPRINT
	int 0x61

	mov esi, newline
	mov ebp, XOS_KPRINT
	int 0x61

	mov eax, -1
	ret

; driver_init:
; Initializes the driver
; In\	Nothing
; Out\	EAX = 0 on success, 1 if device not found

driver_init:
	; scan the PCI bus for the device
	mov esi, pci_ids

.loop:
	lodsd
	cmp eax, 0xFFFFFFFF
	je .no

	mov [.next], esi

	mov ebp, XOS_PCI_GET_VENDOR
	int 0x61

	cmp al, 0xFF
	je .next_device

	mov [pci_bus], al
	mov [pci_slot], ah
	mov [pci_function], bl

	mov esi, driver_name
	mov ebp, XOS_KPRINT
	int 0x61
	mov esi, newline
	mov ebp, XOS_KPRINT
	int 0x61

	mov esi, copyright
	mov ebp, XOS_KPRINT
	int 0x61

	mov esi, found_msg
	mov ebp, XOS_KPRINT
	int 0x61
	mov al, [pci_bus]
	call hex_byte_to_string
	mov ebp, XOS_KPRINT
	int 0x61
	mov esi, colon
	mov ebp, XOS_KPRINT
	int 0x61
	mov al, [pci_slot]
	call hex_byte_to_string
	mov ebp, XOS_KPRINT
	int 0x61
	mov esi, colon
	mov ebp, XOS_KPRINT
	int 0x61
	mov al, [pci_function]
	call hex_byte_to_string
	mov ebp, XOS_KPRINT
	int 0x61
	mov esi, newline
	mov ebp, XOS_KPRINT
	int 0x61

	mov al, [pci_bus]
	mov ah, [pci_slot]
	mov bl, [pci_function]
	mov bh, PCI_BAR0
	mov ebp, XOS_PCI_READ
	int 0x61

	and ax, 0xFFFC
	mov [io], ax

	mov esi, io_msg
	mov ebp, XOS_KPRINT
	int 0x61
	mov ax, [io]
	call hex_word_to_string
	mov ebp, XOS_KPRINT
	int 0x61
	mov esi, newline
	mov ebp, XOS_KPRINT
	int 0x61

	; enable bus mastering and I/O ports, disable interrupts
	mov al, [pci_bus]
	mov ah, [pci_slot]
	mov bl, [pci_function]
	mov bh, PCI_STATUS_COMMAND
	mov ebp, XOS_PCI_READ
	int 0x61

	mov edx, eax
	or edx, 0x405
	mov al, [pci_bus]
	mov ah, [pci_slot]
	mov bl, [pci_function]
	mov bh, PCI_STATUS_COMMAND
	mov ebp, XOS_PCI_WRITE
	int 0x61

	; allocate the RX buffer
	mov eax, 0
	mov ecx, (RX_BUFFER_SIZE+4095)/4096		; to pages
	mov dl, 0x13				; present, read/write, uncacheable
	mov ebp, XOS_VMM_ALLOC			; page-aligned memory
	int 0x61
	mov [rx_buffer], eax

	mov eax, 0
	ret

.next_device:
	mov esi, [.next]
	jmp .loop

.no:
	mov eax, 1
	ret

align 4
.next			dd 0

; driver_reset:
; Resets the device
; In\	Nothing
; Out\	EAX = 0 on success, 1 on error

driver_reset:
	; turn on the device
	mov dx, [io]
	add dx, RTL8139_CONFIG1
	mov al, 0
	out dx, al
	call iowait

	; reset the device
	mov dx, [io]
	add dx, RTL8139_COMMAND
	mov al, RTL8139_COMMAND_RESET
	out dx, al
	call iowait

	mov [.reset_times], 0

	mov dx, [io]
	add dx, RTL8139_COMMAND

.wait_reset:
	inc [.reset_times]
	cmp [.reset_times], 0xFFFFF
	jg .timeout

	in al, dx
	test al, RTL8139_COMMAND_RESET
	jnz .wait_reset

	; configure the multicast mask
	; spec says we can only access these 8 registers as 2 DWORDs
	mov dx, [io]
	add dx, RTL8139_MULTICAST_ADDRESS
	mov eax, 0xFFFFFFFF
	out dx, eax
	add dx, 4
	out dx, eax
	call iowait

	; configure the receiver
	mov eax, [rx_buffer]
	mov ebp, XOS_VIRTUAL_TO_PHYSICAL	; for DMA to be happy..
	int 0x61

	mov dx, [io]
	add dx, RTL8139_RX_START
	out dx, eax
	call iowait

	mov eax, [rx_buffer]
	mov [rx_buffer_current], eax

	mov dx, [io]
	add dx, RTL8139_RECEIVE_CONFIG

	; receive all packets
	mov eax, RTL8139_RECEIVE_CONFIG_ACCEPT_ALL or RTL8139_RECEIVE_CONFIG_ACCEPT_PHYSICAL or RTL8139_RECEIVE_CONFIG_ACCEPT_MULTICAST or RTL8139_RECEIVE_CONFIG_ACCEPT_BROADCAST
	or eax, 2 shl 11		; receive buffer is 64 KB
	or eax, 7 shl 13		; no receive threshold
	or eax, 7 shl 8			; max DMA burst - unlimited
	or eax, RTL8139_RECEIVE_CONFIG_WRAP
	out dx, eax
	call iowait

	; CAPR
	mov dx, [io]
	add dx, RTL8139_RX_CURRENT_ADDRESS
	mov ax, 0xFFF0			; 0 - 16
	out dx, ax
	call iowait

	; configure the transmitter
	mov [transmit_descriptor], 3

	mov dx, [io]
	add dx, RTL8139_TRANSMIT_CONFIG
	mov eax, RTL8139_TRANSMIT_CONFIG_CRC	; no CRC at end of packet
	or eax, 6 shl 8				; max DMA burst
	or eax, 2 shl 4				; max retries
	out dx, eax
	call iowait

	; disable all interrupts
	mov dx, [io]
	add dx, RTL8139_INTERRUPT_MASK
	mov ax, 0
	out dx, ax
	call iowait

	; clear the interrupt register
	mov dx, [io]
	add dx, RTL8139_INTERRUPT_STATUS
	in ax, dx
	out dx, ax
	call iowait

	; enable receiver and transmitter
	mov dx, [io]
	add dx, RTL8139_COMMAND
	in al, dx
	or al, RTL8139_COMMAND_TRANSMIT or RTL8139_COMMAND_RECEIVE
	out dx, al
	call iowait

	mov eax, 0
	ret

.timeout:
	mov esi, reset_timeout_msg
	mov ebp, XOS_KPRINT
	int 0x61

	mov eax, 1
	ret

align 4
.reset_times				dd 0

; get_mac:
; Returns the MAC address
; In\	EBX = 6-byte buffer to store MAC address
; Out\	EAX = 0

get_mac:
	mov edi, ebx
	mov dx, [io]
	in al, dx		; 0
	stosb

	inc dx
	in al, dx		; 1
	stosb

	inc dx
	in al, dx		; 2
	stosb

	inc dx
	in al, dx		; 3
	stosb

	inc dx
	in al, dx		; 4
	stosb

	inc dx
	in al, dx		; 5
	stosb

	mov eax, 0
	ret

	; Data Area
	newline				db 10,0
	driver_name			db "RTL8139 network driver for xOS",0
	copyright			db "Copyright (C) 2017 by Omar Mohammad.",10,0
	unknown_msg			db "rtl8139: unknown request ",0

	found_msg			db "rtl8139: found device on PCI slot ",0
	colon				db ":",0
	io_msg				db "rtl8139: base I/O port is 0x",0
	reset_timeout_msg		db "rtl8139: device reset timed out.",10,0

	pci_bus				db 0
	pci_slot			db 0
	pci_function			db 0

	align 2
	io				dw 0		; I/O port base

	align 4
	rx_buffer			dd 0
	rx_buffer_current		dd 0




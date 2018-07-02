
;; xOS32
;; Copyright (C) 2016-2017 by Omar Mohammad.

use32

; UHCI I/O Port Registers
UHCI_COMMAND			= 0x00		; word
UHCI_STATUS			= 0x02		; word
UHCI_INTERRUPT			= 0x04		; word
UHCI_FRAME			= 0x06		; word
UHCI_FRAMELIST			= 0x08		; dword
UHCI_SOF_MODIFY			= 0x0C		; byte
UHCI_PORT1			= 0x10		; word
UHCI_PORT2			= 0x12		; word

; UHCI Command Register Bitfield
UHCI_COMMAND_RUN		= 0x0001
UHCI_COMMAND_HOST_RESET		= 0x0002
UHCI_COMMAND_GLOBAL_RESET	= 0x0004
UHCI_COMMAND_GLOBAL_RESUME	= 0x0010
UHCI_COMMAND_MAX64		= 0x0080

; UHCI Status Register Bitfield
UHCI_STATUS_INTERRUPT		= 0x0001
UHCI_STATUS_ERROR_INTERRUPT	= 0x0002
UHCI_STATUS_ERROR_HOST		= 0x0008
UHCI_STATUS_ERROR_PROCESS	= 0x0010
UHCI_STATUS_HALTED		= 0x0020

; UHCI Port Registers Bitfield
UHCI_PORT_PLUG			= 0x0001
UHCI_PORT_PLUG_CHANGE		= 0x0002
UHCI_PORT_ENABLE		= 0x0004
UHCI_PORT_ENABLE_CHANGE		= 0x0008
UHCI_PORT_LOW_SPEED		= 0x0100
UHCI_PORT_RESET			= 0x0200

; Packet Types
UHCI_PACKET_SETUP		= 0x2D
UHCI_PACKET_IN			= 0x69
UHCI_PACKET_OUT			= 0xE1

UHCI_DESCRIPTORS_SIZE		= 8	; 32 KB of descriptors is much, much more than enough!

align 4
uhci_pci_list			dd 0
uhci_pci_count			dd 0
uhci_framelist			dd 0

; uhci_init:
; Detects and initializes UHCI controllers

uhci_init:
	; generate a list of PCI devices
	mov ah, 0x0C
	mov al, 0x03
	mov bl, 0x00
	call pci_generate_list

	; no UHCI?
	cmp ecx, 0
	je .done

	mov [uhci_pci_list], eax
	mov [uhci_pci_count], ecx

	mov esi, .starting
	call kprint
	mov eax, [uhci_pci_count]
	call int_to_string
	call kprint
	mov esi, .starting2
	call kprint

	mov eax, 0
	mov ecx, UHCI_DESCRIPTORS_SIZE
	mov dl, PAGE_PRESENT or PAGE_WRITEABLE or PAGE_NO_CACHE
	call vmm_alloc
	mov [uhci_framelist], eax

.loop:
	mov ecx, [.controller]
	cmp ecx, [uhci_pci_count]
	jge .done

	call uhci_init_controller
	inc [.controller]
	jmp .loop

.done:
	ret

align 4
.controller			dd 0
.starting			db "usb-uhci: found ",0
.starting2			db " UHCI controllers, initializing in order...",10,0

; uhci_init_controller:
; Initializes a single UHCI controller
; In\	ECX = Zero-based controller number
; Out\	Nothing

uhci_init_controller:
	mov [.controller], ecx

	shl ecx, 2	; mul 4
	add ecx, [uhci_pci_list]

	mov al, [ecx+PCI_DEVICE_BUS]
	mov [.bus], al
	mov al, [ecx+PCI_DEVICE_SLOT]
	mov [.slot], al
	mov al, [ecx+PCI_DEVICE_FUNCTION]
	mov [.function], al

	mov esi, .starting
	call kprint
	mov al, [.bus]
	call hex_byte_to_string
	call kprint
	mov esi, .colon
	call kprint
	mov al, [.slot]
	call hex_byte_to_string
	call kprint
	mov esi, .colon
	call kprint
	mov al, [.function]
	call hex_byte_to_string
	call kprint
	mov esi, newline
	call kprint

	; read I/O port
	mov al, [.bus]
	mov ah, [.slot]
	mov bl, [.function]
	mov bh, PCI_BAR4
	call pci_read_dword

	and ax, 0xFFFC
	mov [.io], ax

	mov esi, .io_msg
	call kprint
	mov ax, [.io]
	call hex_word_to_string
	call kprint
	mov esi, newline
	call kprint

	; enable I/O ports and DMA, disable interrupt line
	mov al, [.bus]
	mov ah, [.slot]
	mov bl, [.function]
	mov bh, PCI_STATUS_COMMAND
	call pci_read_dword

	or eax, 0x405

	mov edx, eax
	mov al, [.bus]
	mov ah, [.slot]
	mov bl, [.function]
	mov bh, PCI_STATUS_COMMAND
	call pci_write_dword

	; allocate memory for the device addresses
	mov ecx, USB_MAX_ADDRESSES
	call kmalloc
	mov [.memory], eax

	; register the controller...
	mov al, [.bus]
	mov ah, [.slot]
	mov bl, [.function]
	mov cl, USB_UHCI
	movzx edx, [.io]
	mov esi, [.memory]
	call usb_register

	; usb controller is now in eax
	call usb_reset_controller
	ret

align 4
.controller			dd 0
.memory				dd 0
.io				dw 0
.bus				db 0
.slot				db 0
.function			db 0

.starting			db "usb-uhci: initialize UHCI controller on PCI slot ",0
.colon				db ":",0
.io_msg				db "usb-uhci: base I/O port is 0x",0

; uhci_reset_controller:
; Resets an UHCI controller
; In\	EAX = Pointer to controller information
; Out\	Nothing

uhci_reset_controller:
	mov [.controller], eax

	mov edx, [eax+USB_CONTROLLER_BASE]
	mov [.io], dx		; I/O port

	; global reset
	mov dx, [.io]
	mov ax, UHCI_COMMAND_GLOBAL_RESET
	out dx, ax
	call iowait

	mov eax, 2
	call pit_sleep

	mov dx, [.io]
	xor ax, ax
	out dx, ax
	call iowait

	; host controller reset
	mov dx, [.io]
	mov ax, UHCI_COMMAND_HOST_RESET
	out dx, ax
	call iowait

.wait_host_reset:
	in ax, dx
	test ax, UHCI_COMMAND_HOST_RESET
	jnz .wait_host_reset

	mov dx, [.io]
	xor ax, ax
	out dx, ax
	call iowait

	; global resume
	mov dx, [.io]
	in ax, dx
	or ax, UHCI_COMMAND_GLOBAL_RESUME
	out dx, ax
	call iowait

	mov eax, 5
	call pit_sleep

	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_GLOBAL_RESUME
	out dx, ax
	call iowait

	; start of frame modify
	mov dx, [.io]
	add dx, UHCI_SOF_MODIFY
	mov al, 64
	out dx, al
	call iowait

	; port reset
	mov dx, [.io]
	add dx, UHCI_PORT1
	in ax, dx
	or ax, UHCI_PORT_RESET or UHCI_PORT_ENABLE
	and ax, not (3 shl 10)
	and ax, not (1 shl 12)
	and ax, not (1 shl 8)
	;and ax, not (1 shl 7)
	and ax, not (3 shl 4)
	and ax, not 1
	out dx, ax
	call iowait

	mov dx, [.io]
	add dx, UHCI_PORT2
	in ax, dx
	or ax, UHCI_PORT_RESET or UHCI_PORT_ENABLE
	and ax, not (3 shl 10)
	and ax, not (1 shl 12)
	and ax, not (1 shl 8)
	;and ax, not (1 shl 7)
	and ax, not (3 shl 4)
	and ax, not 1
	out dx, ax
	call iowait

	mov eax, 5
	call pit_sleep

	; end of reset --
	; -- enable ports
	mov dx, [.io]
	add dx, UHCI_PORT1
	in ax, dx
	or ax, UHCI_PORT_ENABLE
	and ax, not UHCI_PORT_RESET
	and ax, not (3 shl 10)
	and ax, not (1 shl 12)
	and ax, not (1 shl 8)
	;and ax, not (1 shl 7)
	and ax, not (3 shl 4)
	and ax, not 1
	out dx, ax
	call iowait

	mov dx, [.io]
	add dx, UHCI_PORT2
	mov ax, UHCI_PORT_ENABLE
	in ax, dx
	or ax, UHCI_PORT_ENABLE
	and ax, not UHCI_PORT_RESET
	and ax, not (3 shl 10)
	and ax, not (1 shl 12)
	and ax, not (1 shl 8)
	;and ax, not (1 shl 7)
	and ax, not (3 shl 4)
	and ax, not 1
	out dx, ax
	call iowait

	mov eax, 5
	call pit_sleep

	mov dx, [.io]
	add dx, UHCI_STATUS
	mov ax, 0x3F
	out dx, ax
	call iowait

	ret

align 4
.controller			dd 0
.io				dw 0

; uhci_setup:
; Sends a setup packet
; In\	EAX = Pointer to controller information
; In\	BL = Device address
; In\	BH = Endpoint
; In\	ESI = Setup packet data
; In\	EDI = Data stage, if present
; In\	ECX = Size of data stage, zero if not present, bit 31 is direction
;	Bit 31 = 0: host to device
;	Bit 31 = 1: device to host
; Out\	EAX = 0 on success

uhci_setup:
	mov [.controller], eax
	mov [.packet], esi
	mov [.data], edi
	mov [.data_size], ecx

	and bl, 0x7F
	mov [.address], bl
	and bh, 0x0F
	mov [.endpoint], bh

	mov eax, [.controller]
	mov edx, [eax+USB_CONTROLLER_BASE]
	mov [.io], dx		; I/O port

	; physical addresses for DMA
	mov eax, [.packet]
	call virtual_to_physical
	mov [.packet], eax

	cmp [.data_size], 0	; no data stage?
	je .skip_data

	mov eax, [.data]
	call virtual_to_physical
	mov [.data], eax

.skip_data:
	; construct the descriptors
	mov eax, [uhci_framelist]
	mov [.framelist], eax

	call virtual_to_physical
	mov [.framelist_phys], eax

	; construct the frame list
	mov edi, [.framelist]

	mov eax, [.framelist_phys]
	add eax, 64			; first queue head
	or eax, 2			; select QH
	stosd

	mov eax, 1			; terminate
	stosd

	; construct the first QH
	mov edi, [.framelist]
	add edi, 64
	mov eax, 1			; invalid pointer
	stosd
	mov eax, [.framelist_phys]
	add eax, 128			; first TD
	stosd
	mov eax, 0
	stosd
	stosd
	stosd
	stosd

	; construct the first TD
	mov edi, [.framelist]
	add edi, 128

	mov eax, [.framelist_phys]	; second TD
	add eax, 128+64
	stosd

	; 3 error limit, active, low speed
	mov eax, (3 shl 27) or (1 shl 23) or (1 shl 26)
	stosd

	; max data transfer
	mov eax, 7
	shl eax, 21
	movzx ebx, [.address]
	shl ebx, 8
	or eax, ebx
	movzx ebx, [.endpoint]
	shl ebx, 15
	or eax, ebx
	or eax, UHCI_PACKET_SETUP
	stosd

	mov eax, [.packet]		; data buffer
	stosd

	mov eax, 0
	stosd
	stosd
	stosd
	stosd

	; if there is a data packet, construct a packet for it
	cmp [.data_size], 0
	je .no_data

	; data packet is IN or OUT token?
	test [.data_size], 0x80000000
	jnz .data_in

.data_out:
	; Status is opposite direction of data
	mov [.data_token], UHCI_PACKET_OUT
	mov [.status_token], UHCI_PACKET_IN
	jmp .continue_descriptors

.data_in:
	mov [.data_token], UHCI_PACKET_IN
	mov [.status_token], UHCI_PACKET_OUT

.continue_descriptors:
	; construct second TD
	mov edi, [.framelist]
	add edi, 128+64
	mov eax, [.framelist_phys]
	add eax, 256			; third TD
	stosd

	mov eax, (3 shl 27) or (1 shl 23) or (1 shl 26)
	stosd

	mov eax, [.data_size]
	and eax, 0x7FFFFFFF
	dec eax
	shl eax, 21
	movzx ebx, [.address]
	shl ebx, 8
	or eax, ebx
	movzx ebx, [.endpoint]
	shl ebx, 15
	or eax, ebx
	or eax, [.data_token]
	or eax, 1 shl 19	; data 1
	stosd

	mov eax, [.data]	; data buffer
	stosd

	mov eax, 0
	stosd
	stosd
	stosd
	stosd

	; construct third TD
	mov edi, [.framelist]
	add edi, 256
	mov eax, 1		; invalid pointer
	stosd
	mov eax, (3 shl 27) or (1 shl 23) or (1 shl 24) or (1 shl 26)	; ioc
	stosd

	mov eax, 0x7FF
	shl eax, 21
	movzx ebx, [.address]
	shl ebx, 8
	or eax, ebx
	movzx ebx, [.endpoint]
	shl ebx, 15
	or eax, ebx
	or eax, [.status_token]
	stosd

	mov eax, 0	; buffer..
	stosd

	;mov eax, 0
	stosd
	stosd
	stosd
	stosd

	jmp .send_packet

.no_data:
	mov edi, [.framelist]
	add edi, 128+64

	mov eax, 1		; invalid pointer
	stosd
	mov eax, (3 shl 27) or (1 shl 23) or (1 shl 24) or (1 shl 26)
	stosd

	mov eax, 0x7FF
	shl eax, 21
	movzx ebx, [.address]
	shl ebx, 8
	or eax, ebx
	movzx ebx, [.endpoint]
	shl ebx, 15
	or eax, ebx
	or eax, UHCI_PACKET_IN
	stosd

	mov eax, 0	; buffer..
	stosd

	;mov eax, 0
	stosd
	stosd
	stosd
	stosd

.send_packet:
	;wbinvd

	; tell the uhci about the frame list
	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

	mov dx, [.io]
	add dx, UHCI_FRAMELIST
	mov eax, [.framelist_phys]
	out dx, eax

	mov dx, [.io]
	add dx, UHCI_FRAME
	mov ax, 0
	out dx, ax
	call iowait

	mov dx, [.io]
	in ax, dx
	or ax, UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

.wait:
	mov dx, [.io]
	add dx, UHCI_STATUS
	in ax, dx

	test ax, UHCI_STATUS_ERROR_INTERRUPT
	jnz .interrupt

	test ax, UHCI_STATUS_ERROR_PROCESS
	jnz .process

	test ax, UHCI_STATUS_ERROR_HOST
	jnz .host

	test ax, UHCI_STATUS_HALTED
	jnz .finish

	test ax, UHCI_STATUS_INTERRUPT
	jnz .finish

	jmp .wait

.interrupt:
	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

	; clear status
	mov dx, [.io]
	add dx, UHCI_STATUS
	mov ax, 0x3F
	out dx, ax
	;call iowait

	;mov esi, .interrupt_msg
	;call kprint

	mov eax, -1
	ret

.host:
	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

	; clear status
	mov dx, [.io]
	add dx, UHCI_STATUS
	mov ax, 0x3F
	out dx, ax
	;call iowait

	;mov esi, .host_msg
	;call kprint

	mov eax, -1
	ret

.process:
	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

	; clear status
	mov dx, [.io]
	add dx, UHCI_STATUS
	mov ax, 0x3F
	out dx, ax
	;call iowait

	;mov esi, .process_msg
	;call kprint

	mov eax, -1
	ret

.finish:
	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

	; clear status
	mov dx, [.io]
	add dx, UHCI_STATUS
	mov ax, 0x3F
	out dx, ax
	;call iowait

	mov eax, 0
	ret


align 4
.controller			dd 0
.packet				dd 0
.data				dd 0
.data_size			dd 0
.data_token			dd 0
.status_token			dd 0
.io				dw 0
.address			db 0
.endpoint			db 0

align 4
.framelist			dd 0
.framelist_phys			dd 0

.interrupt_msg			db "usb-uhci: interrupt error in setup packet.",10,0
.host_msg			db "usb-uhci: host error in setup packet.",10,0
.process_msg			db "usb-uhci: process error in setup packet.",10,0

; uhci_interrupt:
; Sends/receives an interrupt packet
; In\	EAX = Pointer to controller information
; In\	BL = Device address
; In\	BH = Endpoint
; In\	ESI = Interrupt packet
; In\	ECX = Bits 0-30: Size of interrupt packet, bit 31: direction
;	Bit 31 = 0: host to device
;	Bit 31 = 1: device to host
; Out\	EAX = 0 on success

uhci_interrupt:
	mov [.controller], eax
	mov [.packet], esi
	mov [.size], ecx

	and bl, 0x7F
	mov [.address], bl
	and bh, 0x0F
	mov [.endpoint], bh

	; if there is no data to be transferred, ignore the request
	;mov ecx, [.size]
	;and ecx, 0x7FFFFFFF
	;cmp ecx, 0
	;je .finish2

	mov eax, [.controller]
	mov edx, [eax+USB_CONTROLLER_BASE]
	mov [.io], dx		; I/O port

	; physical addresses for the DMA to be happy...
	mov eax, [.packet]
	call virtual_to_physical
	mov [.packet], eax

	mov eax, [uhci_framelist]
	mov [.framelist], eax
	call virtual_to_physical
	mov [.framelist_phys], eax

	; construct the frame list
	mov edi, [.framelist]
	mov eax, [.framelist_phys]	; pointer to first TD
	add eax, 32
	stosd
	mov eax, 1			; terminate list
	stosd

	; construct the first and only TD
	mov edi, [.framelist]
	add edi, 32

	mov eax, 1			; link pointer invalid
	stosd

	; 1 error limit, active, low speed, IOC
	mov eax, (1 shl 27) or (1 shl 23) or (1 shl 26) or (1 shl 24)
	stosd

	; data size and direction
	mov eax, [.size]
	dec eax
	and eax, 7	; maximum size of interrupt packet for low-speed device
	shl eax, 21
	movzx ebx, [.address]
	shl ebx, 8
	or eax, ebx
	movzx ebx, [.endpoint]
	shl ebx, 15
	or eax, ebx
	;or eax, 1 shl 19	; data 1

	test [.size], 0x80000000	; device to host?
	jnz .in_packet

.out_packet:
	or eax, UHCI_PACKET_OUT
	jmp .buffer_dword

.in_packet:
	or eax, UHCI_PACKET_IN

.buffer_dword:
	stosd

	; actual data buffer
	mov eax, [.packet]
	stosd

	mov eax, 0		; pad out remaining space...
	stosd
	stosd
	stosd
	stosd

.send_packet:
	;wbinvd

	; tell the uhci about the frame list
	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

	mov dx, [.io]
	add dx, UHCI_FRAMELIST
	mov eax, [.framelist_phys]
	out dx, eax

	mov dx, [.io]
	add dx, UHCI_FRAME
	mov ax, 0
	out dx, ax
	call iowait

	mov dx, [.io]
	in ax, dx
	or ax, UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

.wait:
	mov dx, [.io]
	add dx, UHCI_STATUS
	in ax, dx

	test ax, UHCI_STATUS_ERROR_INTERRUPT
	jnz .interrupt

	test ax, UHCI_STATUS_ERROR_PROCESS
	jnz .process

	test ax, UHCI_STATUS_ERROR_HOST
	jnz .host

	test ax, UHCI_STATUS_HALTED
	jnz .finish

	test ax, UHCI_STATUS_INTERRUPT
	jnz .finish

	jmp .wait

.interrupt:
	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

	; clear status
	mov dx, [.io]
	add dx, UHCI_STATUS
	mov ax, 0x3F
	out dx, ax
	;call iowait

	;mov esi, .interrupt_msg
	;call kprint

	mov eax, -1
	ret

.host:
	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

	; clear status
	mov dx, [.io]
	add dx, UHCI_STATUS
	mov ax, 0x3F
	out dx, ax
	;call iowait

	;mov esi, .host_msg
	;call kprint

	mov eax, -1
	ret

.process:
	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

	; clear status
	mov dx, [.io]
	add dx, UHCI_STATUS
	mov ax, 0x3F
	out dx, ax
	;call iowait

	;mov esi, .process_msg
	;call kprint

	mov eax, -1
	ret

.finish:
	mov dx, [.io]
	in ax, dx
	and ax, not UHCI_COMMAND_RUN
	out dx, ax
	;call iowait

	; clear status
	mov dx, [.io]
	add dx, UHCI_STATUS
	mov ax, 0x3F
	out dx, ax
	;call iowait

.finish2:
	mov eax, 0
	ret

align 4
.controller			dd 0
.packet				dd 0
.size				dd 0
.io				dw 0
.address			db 0
.endpoint			db 0

align 4
.framelist			dd 0
.framelist_phys			dd 0

.interrupt_msg			db "usb-uhci: interrupt error in interrupt packet.",10,0
.host_msg			db "usb-uhci: host error in interrupt packet.",10,0
.process_msg			db "usb-uhci: process error in interrupt packet.",10,0









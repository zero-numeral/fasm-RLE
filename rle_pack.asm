format PE
include 'win32a.inc'

entry start

section '.bss' data readable writeable
        argc dd ?
        argv dd ?
        envp dd ? ; unused, but is essential for calling the function properly

        file_name dd ?
        file_size dd ?

        hFile_read dd ?
        hFile_write dd ?

        lpBuffer_read dd ?
        lpBuffer_write dd ?

section '.data' data readable
        INVALID_FILE_SIZE = 0xffffffff

        usage_msg db "Usage: %s file_to_pack", 0
        error_msg db "An unknown error has occured.", 0
        open_read_msg db "Unable to open file for read.", 0
        open_write_msg db "Unable to open file for write.", 0
        file_size_error_msg db "Invalid file size.", 0

        out_file_name db "packed.bin", 0

section '.text' code readable executable
        start:
                ;==================SETUP====================

                invoke __getmainargs, argc, argv, envp, 0, 0 ; obtain command-line arguments
                cmp eax, 0                                   ; error occured?
                jnz unknown_error                            ; show error message if yes
                cmp [argc], 2                                ; have we passed file name to the program?
                jl  usage_tip                                ; print tip if not

                ; extract file name from arguments
                mov eax, [argv]
                mov eax, [eax + 4]
                mov [file_name], eax

                invoke CreateFile, [file_name], GENERIC_READ, 0, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0     ; open file for reading
                cmp eax, INVALID_HANDLE_VALUE                                                                   ; was file openning successful?
                jz  open_read_error                                                                             ; print error if not
                mov [hFile_read], eax                                                                           ; save file handle
                invoke GetFileSize, eax

                ; does file have valid size?
                ; print file size error if not
                cmp eax, INVALID_FILE_SIZE
                jz file_size_error
                cmp eax, 0
                jz file_size_error

                mov [file_size], eax                                                                            ; save file size

                invoke CreateFile, out_file_name, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0  ; open file for writing
                cmp eax, INVALID_HANDLE_VALUE                                                                   ; was file openning successful?
                jz  open_write_error                                                                            ; print error and close read file handle if not
                mov [hFile_write], eax                                                                          ; save file handle

                invoke VirtualAlloc, 0, [file_size], MEM_COMMIT + MEM_RESERVE, PAGE_READWRITE
                mov [lpBuffer_read], eax                                                                        ; allocate memory for file reading

                invoke ReadFile, [hFile_read], [lpBuffer_read], [file_size], 0, 0                               ; read file into buffer

                mov eax, [file_size]
                add eax, 50
                invoke VirtualAlloc, 0, eax, MEM_COMMIT + MEM_RESERVE, PAGE_READWRITE
                mov [lpBuffer_write], eax                                                                       ; allocate memory for file writing with 50 extra bytes

                ;===============COMPRESSION=================

                mov esi, [lpBuffer_read]
                mov edi, [lpBuffer_write]
                mov ecx, [file_size]
                mov [edi], ecx           ; write original file size into write buffer
                add edi, 4               ; shift buffer offset
                xor eax, eax             ; reset accumulator, ah -> sequence length (limit 127), al -> incoming byte

        check:
                cmp ecx, 0               ; check if we have finished file reading, then exit
                jnz pack_start

                jmp pack_exit

        pack_start:
                cmp ah, 127              ; check for marker overflow
                jz handle_singles        ; process sequence of singles if so

                lodsb                    ; load next byte into al

                dec ecx                  ; decrement counter
                cmp ecx, 0               ; was it last byte to read?
                jz last_byte             ; process it if yes, to avoid reading out of buffer bounds

                cmp al, [esi]            ; compare curent byte with next one
                jz handle_repeating      ; if they are equal -> process repeating sequence

                inc ah                   ; increment singles count

                jmp check

        last_byte:
                inc ah                   ; correcting counter and fall into handle_singles

        handle_singles:
                shr ax, 8                ; shift ah into al
                stosb                    ; save marker to write buffer

                push esi ecx             ; store source offset and counter
                movzx ecx, al            ; set new counter
                sub esi, ecx             ; shift back our source offset
                rep movsb                ; copy our sequence into write buffer
                pop ecx esi              ; restore source offset and counter

                jmp check

        handle_repeating:
                dec esi                  ; shift back source offset to go to the sequence beginning
                inc ecx                  ; correcting counter

                cmp ah, 0
                jnz handle_singles       ; we got signles which were not written to the write buffer, so lets process them

        @@:
                cmp al, [esi]            ; is same byte?
                jnz @f                   ; procces if not -> chain is broken

                inc esi                  ; shift source offset to next byte
                inc ah                   ; increase byte count
                dec ecx                  ; decrease counter

                cmp ah, 127              ; check for marker overflow
                jz @f                    ; proccess if so

                cmp ecx, 0               ; is it last byte?
                jz @f                    ; proccess if so

                jmp @b                   ; continue counting sequence length

        @@:
                or ah, 0x80              ; set marker msb
                xchg ah, al              ; now al -> marker with msb set, ah -> our byte
                stosb                    ; copy our marker into write buffer
                xchg ah, al              ; exchange back
                stosb                    ; copy our repeating byte into write buffer

                xor ah, ah               ; reset sequence length

                jmp check

        pack_exit:

                sub edi, [lpBuffer_write]                                    ; obtain packed file size
                invoke WriteFile, [hFile_write], [lpBuffer_write], edi, 0, 0 ; write packed data into the file

                ;=================CLEANUP===================

                ; not necessary, since OS will reclaim resources after process exit

                ; close file handles
                invoke CloseHandle, [hFile_read]
                invoke CloseHandle, [hFile_write]
                ; dealloc memory
                invoke VirtualFree, [lpBuffer_read], 0, MEM_RELEASE
                invoke VirtualFree, [lpBuffer_write], 0, MEM_RELEASE
                jmp exit

        open_read_error:
                cinvoke printf, open_read_msg
                jmp exit

        open_write_error:
                cinvoke printf, open_write_msg
                invoke CloseHandle, [hFile_read]
                jmp exit

        file_size_error:
                cinvoke printf, file_size_error_msg
                invoke CloseHandle, [hFile_read]
                jmp exit

        usage_tip:
                mov eax, [argv]
                cinvoke printf, usage_msg, [eax]
                jmp exit

        unknown_error:
                cinvoke printf, error_msg

        exit:
                invoke ExitProcess, 0

section '.idata' import data readable

        library kernel32, 'kernel32.dll', \
                msvcrt,   'msvcrt.dll'

        import kernel32, \
               ReadFile,     'ReadFile',     \
               WriteFile,    'WriteFile',    \
               ExitProcess,  'ExitProcess',  \
               CreateFile,   'CreateFileA',  \
               GetFileSize,  'GetFileSize',  \
               CloseHandle,  'CloseHandle',  \
               VirtualFree,  'VirtualFree',  \
               VirtualAlloc, 'VirtualAlloc'

        import msvcrt, \
               printf, 'printf', \
               __getmainargs, '__getmainargs'
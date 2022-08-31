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

        unpacked_file_size dd ?

section '.data' data readable
        INVALID_FILE_SIZE = 0xffffffff
        usage_msg db "Usage: %s file_to_unpack", 0
        error_msg db "An unknown error has occured.", 0
        open_read_msg db "Unable to open file for read.", 0
        open_write_msg db "Unable to open file for write.", 0
        file_size_error_msg db "Invalid file size.", 0

        out_file_name db "unpacked", 0

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

                mov eax, [lpBuffer_read]
                mov eax, [eax]
                mov [unpacked_file_size], eax                                                                   ; save unpacked file original size

                invoke VirtualAlloc, 0, [unpacked_file_size], MEM_COMMIT + MEM_RESERVE, PAGE_READWRITE
                mov [lpBuffer_write], eax                                                                       ; allocate memory for file writing

                ;==============DECOMPRESSION================

                mov esi, [lpBuffer_read]
                mov edi, [lpBuffer_write]
                mov ecx, [file_size]
                add esi, 4               ; skip original file size
                sub ecx, 4

                xor eax, eax

        unpack:
                lodsb

                test al, 0x80          ; does marker have msb set
                jnz handle_repeating   ; if yes -> process repeating sequence

                sub ecx, eax           ; update counter value before storing it
                push ecx               ; store counter

                movzx ecx, al          ; now marker is a counter
                rep movsb              ; copy our sequence to out buffer

                pop ecx                ; restore counter

                jmp unpack_exit

        handle_repeating:
                and al, 0x7f           ; unset msb

                push ecx
                movzx ecx, al          ; interpret marker as counter

                lodsb                  ; store repeating byte
                rep stosb              ; write repeating byte

                pop ecx                ; restore counter
                dec ecx                ; 1 byte readed so just decrement it once

        unpack_exit:
                loop unpack            ; continue file read if any bytes left

                invoke WriteFile, [hFile_write], [lpBuffer_write], [unpacked_file_size], 0, 0 ; write unpacked data into the file

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
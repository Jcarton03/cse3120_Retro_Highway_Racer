; ===========================================================
;RetroRacer.asm
;------------------------------------------------------------
; Controls:   A / D  or  ← / →  to change lanes.   ESC to quit. (Interrupts)
; Goal:       Dodge obstacles on the highway. Get the highest Score. 
;             Score increases over time, increasing faster with difficulty (Google Dino game-esque)
; Difficulty: Spawn chance, speed ramp automatically, and number of lanes with obstacles(maybe)
; ============================================================

.386
.model flat, stdcall
.stack 4096
ExitProcess PROTO, dwExitCode:DWORD

INCLUDE Irvine32.inc

; ======================= Constants =========================
LANES           EQU     3             ; # of lanes
MAX_OBS         EQU     32            ; max active obstacles tracked at once

BORDER_LEFT     EQU     12            ; left wall x-position, (col)
BORDER_RIGHT    EQU     44            ; right wall x-position, (row)
ROAD_TOP        EQU     2             ; first highway row
ROAD_BOTTOM     EQU     23            ; last highway row
PLAYER_ROW      EQU     ROAD_BOTTOM-1 ; where the car sits (second line from the bottom, might want higher, or the ability to go up and down)

COLOR_HUD       EQU     green + black*16      ; HUD text color on black background
COLOR_ROAD      EQU     white + black*16	  ; road text color 
COLOR_LANE	    EQU     yellow + black*16	  ; lane divide color
COLOR_CAR		EQU	    lightRed + black*16	  ; car text color
COLOR_OBS		EQU	    red + lightGray*16    ; obstacle text color

; ======================= DATA =======================
.data
; Column centers for each lane (Modify to make wider/narrower)
laneX           BYTE    18, 28, 38

; Variables for the ASCII character to display the road, obstacles, and car
PLAYER_CHAR     BYTE     0A4h
OB_CHAR         BYTE	 058h     
BORDER_CHAR     BYTE     07Ch
LANE_CHAR       BYTE     0A6h

; lane marker columns, computed at initially from laneX midpoints
marker1Col      BYTE    23
marker2Col      BYTE    33

; Game start state
playerLane      BYTE    1               ; start in middle lane
oldPlayerLane   BYTE    ?               ; for erasing old position
alive           BYTE    1               ; 1 = running, 0 = dead
score           DWORD   0               
highScore       DWORD   0               

; Game timing & difficulty, can modify later
tickDelay       WORD    60              ; The ms per frame, for speeding down/up
spawnOdds       BYTE    14              ; percentage (0..100). Spawn if roll < spawnOdds
tickCount       DWORD   0               ; tracks frames to know when to speed up/increase difficulty
obstacleRamp    DWORD   25000           ; amount of time required to increase the number of maximum lanes with obstacles  
rampCounter	    DWORD   0

; Obstacles are arrays [0..2] for simplicity:
obs_active      BYTE    MAX_OBS DUP(0)  ; 1 if in use, clears after user dodges
obs_lane        BYTE    MAX_OBS DUP(0)  ; lane index (0..LANES-1)
obs_row         BYTE    MAX_OBS DUP(0)  ; obstacle -> current row (0..ROAD_BOTTOM)

; Game HUD/UI strings
titleStr        BYTE    "RETRO HIGHWAY RACER",0
controlsStr     BYTE    "A/D or <-/-> to move, and X to quit",0
scoreStr        BYTE    "Score: ",0
highscoreStr    BYTE    "High Score: ",0
gameOverStr     BYTE    "GAME OVER! Press any key to continue...",0

; ======================= PROTOTYPES =======================
.code

InitGame            PROTO
PollInput           PROTO
ClearObstacles      PROTO
SpawnObstacle       PROTO
UpdateObstacles     PROTO
CheckCollision      PROTO
DrawFrame           PROTO
DrawHUD             PROTO
DrawRoad            PROTO
DrawPlayer          PROTO
DrawObstacles       PROTO
RampDifficulty      PROTO
GameOverScreen      PROTO

; ======================= Main =======================

main PROC
    ; Initialize random, colors, variables, clear screen.
    call InitGame

    ; Main loop runs while player is alive (alive = 1)

GameLoop:
    ; Check if car position is an obstacle, then alive = 0
    cmp alive, 1
    jne EndGame                 ; Check if player died, leave the loop

    ; Handle input (A/D --> left/right)
    call PollInput

    ; Spawn a new obstacle at top row in a random lane
    call SpawnObstacle

    ; Shift all active obstacles down by 1 row, and clear the ones off screen
    call UpdateObstacles

    ; If players hits an obstacle, they die.
    call CheckCollision
    cmp  alive, 1               ; game over immediately on crash
    jne  EndGame

    ; Draw everything for the current frame (HUD + road + player + obstacle)
    call DrawFrame

    ; Gradually increases the difficulty (faster ticks, more obstacle spawns)
    call RampDifficulty

    ; Increase score each tick (simple time-based survival scoring)
    add score, 1

    ; Wait until next frame, manage game speed/diff
    movzx eax, tickDelay
    call Delay

    jmp GameLoop            ; loop till they die

EndGame:
    ; Show game over screen, update high score if needed, wait for next key press.
    call GameOverScreen
    INVOKE ExitProcess, 0
main ENDP

; ===================================================================
; InitGame — sets start game state,  UI, colors and clear obstacle lists
; Set initial lanes as all blank to give player time to feel out the game at the beginning
; ===================================================================
InitGame PROC

    push eax
    push ebx

    call Randomize
    call Clrscr

    mov  score, 0
    mov  alive, 1
    mov  playerLane, 1
    mov  tickCount, 0
    mov  rampCounter, 0

    ; compute lane marker midpoints from laneX
    ; marker1 = (laneX[0] + laneX[1]) / 2
    ; marker2 = (laneX[1] + laneX[2]) / 2
    mov  al, [laneX]
    mov  ah, [laneX+1]
    add  al, ah
    shr  al, 1
    mov  marker1Col, al

    mov  al, [laneX+1]
    mov  ah, [laneX+2]
    add  al, ah
    shr  al, 1
    mov  marker2Col, al

    call ClearObstacles
    call DrawHUD
    call DrawRoad

    pop ebx
    pop eax
    ret

    ret
InitGame ENDP

; ===================================================================
; PollInput — read a key if present and adjust player lane.
; Uses Irvine ReadKey: ZF=1 if no key was available.
; - 'X' exits fast program via ExitProcess.
; - a, or Left arrow -> lane - 1 (min 0)
; - d, or Right arrow -> lane + 1 (max LANES-1)
; May want to include up and down controls later, depending on difficulty of game
; ===================================================================

PollInput PROC
    ; sets ZF = 1 if no input, else ZF = 0, ASCII inputs go to AL, other inputs go to AH
    call ReadKey
    jz NoKeyPressed  ; ZF = 1, no input

    cmp al, 0        ; if AL != 0, then there is ASCII input (important chars, a, d) 
    jne WASD         ; jump to reading ASCII chars

    cmp ah, 4Bh      ; 4Bh refers to Left-arrow, <-
    je MoveLeft      ; jump to controlling the 'car' left
    cmp ah, 4Dh      ; 4Dh refers to Right-arrow, ->
    je MoveRight     ; jump to controlling the 'car' right
    jmp DoneKey      ; finish taking input and return to game loop

WASD:

    cmp al, 'x'      ; 1Bh refers to 'esc'
    je ExitGame      ; jump to where exiting the game is handled
    cmp al, 'X'
    je ExitGame

    cmp al, 'a'      ; ReadKey puts ASCII chars into AL, checks for 'a'
    je MoveLeft      ; jump to controlling the 'car' left
    cmp al, 'A'
    je MoveLeft

    cmp al, 'd'      ; checks for 'd'
    je MoveRight     ; jump to controlling the 'car' right
    cmp al, 'D'
    je MoveRight
    jmp DoneKey      ; finished taking input and return to game loop

    ; Jump back to game loop

NoKeyPressed:
    jmp DoneKey

; Shift the 'car' left one lane, lane - 1, make sure it doesn't go beyond a boundary
; Checks if position moving to is an obstacle then go to GameOver
MoveLeft:
    mov al, playerLane
    cmp al, 0
    jbe DoneKey
    dec al
    mov playerLane, al
    jmp DoneKey

; Shift the 'car' right one lane, lane + 1, make sure it doesn't go beyond a boundary
; Checks if position moving to is an obstacle then go to GameOver
MoveRight:
    mov al, playerLane
    cmp al, (LANES-1)
    jae DoneKey
    inc al
    mov playerLane, al
    jmp DoneKey

; Jump back to game loop
DoneKey:
    ret

; Display some text like, "Exiting Retro Racer - Press any key to continue"
; Jump back to game loop, and carry over a flag or value to immediately exit the game
ExitGame:
    call GameOverScreen
    ret
PollInput ENDP

; ===================================================================
; ClearObstacles — sets all active obstacles (obs_active) entries to 0 (no obstacles).
; Change obstacle in last row to white space, we can have this always be blank
; ===================================================================
ClearObstacles PROC
    mov  ecx, MAX_OBS
    mov  edi, OFFSET obs_active
    xor  eax, eax
CLoop:
    mov  [edi], al
    inc  edi
    loop CLoop
    ret
ClearObstacles ENDP

; ===================================================================
; SpawnObstacle — pick random #, 0-99 and if pick < spawnOdds, activate a obstacle slot.
; - Picks first free slot
; - Spawns at row 0 in a random lane
; - Obstacle hex (white square ascii) - 0FEh
; ===================================================================

SpawnObstacle PROC
    ; Save registers that we modify
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; ---- - roll 0..99 and compare to spawnOdds---- -
    mov  eax, 100       ; range
    call RandomRange    ; EAX = 0..99
    cmp  al, spawnOdds
    jae  SO_Done        ; if roll >= spawnOdds, don't spawn

    ; ---- - find first free slot---- -
    mov  esi, OFFSET obs_active
    mov  ecx, MAX_OBS   ; # of obstacles to check
    xor edi, edi        ; edi = index

SO_FindSlot :
    cmp  BYTE PTR[esi], 0   ; is space free
    je   SO_Spawn           ; else go next entry
    inc  esi
    inc  edi                ; inc index counter
    loop SO_FindSlot        ; dec ecx and loop till 0
    jmp  SO_Done            ; stop spawning if no free slot

; mark activate the obstacle
SO_Spawn :
mov  BYTE PTR[esi], 1   ; mark active

; ---- - pick lane 0..LANES - 1 ---- -
mov  eax, LANES         ; range
call RandomRange        ; EAX = 0..LANES - 1
mov[obs_lane + edi], al

; ---- - start at top row---- -
mov  al, ROAD_TOP
mov[obs_row + edi], al  ; store in obs_row array

; reg cleanup
SO_Done :
pop  edi
pop  esi
pop  edx
pop  ecx
pop  ebx
pop  eax
ret
SpawnObstacle ENDP


; ===================================================================
; UpdateObstacles — all the active obstacle moves down by 1 row
; deactivate/clear when past ROAD_BOTTOM.
; Check to ensure a valid path for player 
; Example invalid path:
; │ ■ ¦   │             ; tested on terminal, vertical lines connect and 
; │   ¦ ■ │             ; lane markers are evenly spaced, all characters work
; ===================================================================

UpdateObstacles PROC
    push eax
    push ecx
    push edx
    push esi
    push edi

    mov esi, OFFSET obs_active
    mov edi, OFFSET obs_row
    mov ecx, MAX_OBS

NextObs:
    cmp BYTE PTR [esi], 1        ; only update active obstacles
    jne SkipObs

    ; increment row by 1
    mov al, [edi]
    inc al
    mov [edi], al

    ; check if past ROAD_BOTTOM
    cmp al, ROAD_BOTTOM
    jle SkipObs
    ; deactivate obstacle
    mov BYTE PTR [esi], 0
    mov BYTE PTR [edi], 0        ; reset row just for cleanliness

SkipObs:
    inc esi
    inc edi
    loop NextObs

    pop edi
    pop esi
    pop edx
    pop ecx
    pop eax
    ret
UpdateObstacles ENDP

; ===================================================================
; CheckCollision — if any obstacle is at the players row AND same lane,
; set alive = 0(player loses) and updates score/highScore.
; ===================================================================
CheckCollision PROC
    push eax
    push ecx
    push edx
    push esi
    push edi

    mov esi, OFFSET obs_active
    mov edi, OFFSET obs_lane
    mov edx, OFFSET obs_row
    mov ecx, MAX_OBS

CheckNext:
    cmp BYTE PTR [esi], 1        ; only active obstacles
    jne SkipCheck

    ; compare row with player
    mov al, [edx]
    cmp al, PLAYER_ROW
    jne SkipCheck

    ; compare lane with playerLane
    mov al, [edi]
    cmp al, playerLane
    jne SkipCheck

    ; collision detected
    mov alive, 0

SkipCheck:
    inc esi
    inc edi
    inc edx
    loop CheckNext

    pop edi
    pop esi
    pop edx
    pop ecx
    pop eax
    ret
CheckCollision ENDP


; ===================================================================
; DrawFrame — clears the screen and draws HUD, road, obstacle, player
; ===================================================================
DrawFrame PROC
    call DrawObstacles
    call DrawPlayer
    ret
DrawFrame ENDP


; ===================================================================
; DrawHUD — title, controls text, and score/highscore above the game board
; ===================================================================
DrawHUD PROC
    push eax
    push edx

    mov  eax, COLOR_HUD
    call SetTextColor

    ; Title (row 0, col 0)
    mov  dh, 0
    mov  dl, 0
    call Gotoxy
    mov  edx, OFFSET titleStr
    call WriteString

    ; Controls (row 1, col 0)
    mov  dh, 1
    mov  dl, 0
    call Gotoxy
    mov  edx, OFFSET controlsStr
    call WriteString

    ; Score (row 0, right-ish)
    mov  dh, 0
    mov  dl, 55
    call Gotoxy
    mov  edx, OFFSET scoreStr
    call WriteString
    mov  eax, score
    call WriteDec

    ; High Score (row 1, right-ish)
    ;mov  dh, 1
    ;mov  dl, 55
    ;call Gotoxy
    ;mov  edx, OFFSET highscoreStr
    ;call WriteString
    ;mov  eax, highScore
    ;call WriteDec

    pop edx
    pop eax
    ret
DrawHUD ENDP


; ===================================================================
; DrawRoad — draws left/right borders and dotted lane markers, like a highway
; Example: |   ¦   |
;          |   ¦   |
; Should play around with how many lanes are manageable
; ===================================================================
DrawRoad PROC
    push eax
    push ecx
    push edx        ; registers to modify
    
    mov  eax, COLOR_ROAD    ; set the color, white on black
    call SetTextColor

    ; Draw rows ROAD_TOP --> ROAD_BOTTOM
    mov  ecx, ROAD_BOTTOM - ROAD_TOP + 1
    mov  dh, ROAD_TOP

DR_RowLoop:
    ; left border
    mov  dl, BORDER_LEFT    ; DL = X col position
    call Gotoxy             ; move cursor to row=DH, col=DL
    mov  al, BORDER_CHAR    ; AL = '│'
    call WriteChar

    ; right border
    mov  dl, BORDER_RIGHT   ; right wall column
    call Gotoxy
    mov  al, BORDER_CHAR
    call WriteChar         

    ; Draw first marker (between lane 1 & lane 2)
    mov  dl, marker1Col     ; precomputed midpoint column
    call Gotoxy
    mov eax, COLOR_LANE
    call SetTextColor
    mov  al, LANE_CHAR      ; AL = '¦'
    call WriteChar

    ; Draw second marker (between lane 2 & lane 3)
    mov  dl, marker2Col
    call Gotoxy
    mov  al, LANE_CHAR
    call WriteChar
    mov eax, COLOR_ROAD
    call SetTextColor

DR_NextRow:
    inc  dh                 ; move to next row
    loop DR_RowLoop         ; ECX--, repeat until 0

    pop edx 
    pop ecx
    pop eax        ; restore registers
    ret
DrawRoad ENDP


; ===================================================================
; DrawPlayer — print the player icon at the fixed row and current lane 
; column, updates on moves, left/right
; row, when obstacles move down, since lanes don't move, car doesn't move vertically
; ===================================================================
DrawPlayer PROC
    push eax
    push edx

    mov  eax, COLOR_ROAD
    call SetTextColor

    mov  dh, PLAYER_ROW     ; DH = player’s fixed row near bottom
    movzx eax, playerLane   ; EAX = lane index 0,1,2
    mov  dl, [laneX + eax]  ; DL = column center of that lane
    call Gotoxy             ; move cursor to PLAYER_ROW, laneX
    mov eax, COLOR_CAR
    call SetTextColor
    mov  al, PLAYER_CHAR
    call WriteChar          ; print the player car

    pop edx
    pop eax
    ret
DrawPlayer ENDP


; ===================================================================
; DrawObstacles — print an obstacle for each active obstacle at (row, lane)
; ===================================================================
DrawObstacles PROC
    push eax
    push ebx 
    push ecx 
    push edx
    push esi
    push edi

    mov  eax, COLOR_ROAD
    call SetTextColor

    mov  esi, OFFSET obs_active
    mov  edi, OFFSET obs_lane
    mov  ebx, OFFSET obs_row
    mov  ecx, MAX_OBS           ; loop counter # obstacles

DO_Next:
    cmp  BYTE PTR [esi], 1      ; Is obstacle active?
    jne  DO_Skip                ; If not active, skip drawing

    ; get screen row
    mov  dh, [ebx]              ; DH = obstacle row

    ; get lane index and convert to column
    mov  al, [edi]              ; AL = lane index
    movzx eax, al               ; zero-extend to EAX
    mov  dl, [laneX + eax]      ; DL = column center of that lane

    call Gotoxy                ; move cursor to (row=DH, col=DL)
    mov eax, COLOR_OBS
    call SetTextColor
    mov  al, OB_CHAR
    call WriteChar
    mov eax, COLOR_ROAD
    call SetTextColor

DO_Skip:
    inc  esi        ; move to next obs_active[i+1]
    inc  edi        ; move to next obs_lane[i+1]
    inc  ebx        ; move to next obs_row[i+1]
    loop DO_Next    ; decrement ECX and repeat until ECX = 0

    pop edi
    pop esi
    pop edx 
    pop ecx
    pop ebx
    pop eax

    ret
DrawObstacles ENDP



; ===================================================================
; RampDifficulty — every 80-ish ticks, decrease the delay and increase the spawn rate.
; - tickDelay = max(55, tickDelay - 2)
; - spawnOdds = min(45, spawnOdds + 1)
; ===================================================================

RampDifficulty PROC
    push eax
    push ecx
    push edx

    ; increment ramp counter
    inc rampCounter

    ; every 80 ticks, adjust speed & spawn odds
    mov eax, rampCounter
    mov ecx, 80
    cdq
    div ecx          ; EAX = rampCounter / 80, EDX = remainder
    cmp edx, 0
    jne RD_Done      ; not yet 80 ticks, skip

    ; decrease tickDelay by 2 (min 20)
    movzx eax, tickDelay
    cmp eax, 22
    jl RD_SkipSpeed
    sub eax, 2
    mov tickDelay, ax
RD_SkipSpeed:

    ; increase spawnOdds by 1 (max 80)
    mov al, spawnOdds
    cmp al, 80
    jae RD_SkipSpawn
    inc al
    mov spawnOdds, al
RD_SkipSpawn:

RD_Done:
    pop edx
    pop ecx
    pop eax
    ret
RampDifficulty ENDP



; ===================================================================
; GameOverScreen — print game over text, update high score,
; then await key press before returning and ExitProcess
; have a way to print to a file, read from a file, and compare highscore on the file to last played score
; ===================================================================
GameOverScreen PROC
    push eax
    push edx

    ; highScore = max(highScore, score)
    mov  eax, highScore
    cmp  eax, score
    jae  GOS_Display
    mov  eax, score
    mov  highScore, eax

GOS_Display:
    mov  eax, COLOR_HUD
    call SetTextColor

    ; center-ish message
    mov  dh, 12
    mov  dl, 10
    call Gotoxy
    mov  edx, OFFSET gameOverStr
    call WriteString

    ; print final score below
    mov  dh, 14
    mov  dl, 10
    call Gotoxy
    mov  edx, OFFSET scoreStr
    call WriteString
    mov  eax, score
    call WriteDec

    ; wait for any key
    call ReadChar
    mov eax, COLOR_ROAD
    call SetTextColor
    call Clrscr

    pop edx
    pop eax

    ret
GameOverScreen ENDP


END main

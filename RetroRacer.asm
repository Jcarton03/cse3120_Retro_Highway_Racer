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
LANES           EQU     3           ; # of lanes (Need for flushing out a lane, |  :  |, |#:^|, | # : ^ |, ect)
MAX_OBS         EQU     32          ; max active obstacles tracked at once

BORDER_LEFT     EQU     12          ; left wall x-position, (col)
BORDER_RIGHT    EQU     44          ; right wall x-position, (row)
ROAD_TOP        EQU     2           ; first highway row
ROAD_BOTTOM     EQU     23          ; last highway row
PLAYER_ROW      EQU     (ROAD_BOTTOM-1) ; where the car sits (second line from the bottom, might want higher, or the ability to go up and down)

PLAYER_CHAR     EQU     '^'         ; player glyph
OB_CHAR         EQU     '#'         ; obstacle glyph
BORDER_CHAR     EQU     '|'         ; border glyph
LANE_CHAR       EQU     ':'         ; lane marker glyph

COLOR_HUD       EQU     (yellow)                 ; HUD text color on black background
COLOR_ROAD      EQU     (white + (black*16))     ; road text color 

; ======================= DATA =======================
.data
; Column centers for each lane (Modify to make wider/narrower)
laneX           BYTE    18, 28, 38

; lane marker columns, computed at initial from laneX midpoints
marker1Col      BYTE    23
marker2Col      BYTE    33

; Game start state
playerLane      BYTE    1               ; start in middle lane
alive           BYTE    1               ; 1 = running, 0 = dead
score           DWORD   0               ; 
highScore       DWORD   0               ; run per session

; Game timing & difficulty, can modify later
tickDelay       WORD    120             ; The ms per frame, for speeding down/up
spawnOdds       BYTE    14              ; percentage (0..100). Spawn if roll < spawnOdds
tickCount       DWORD   0               ; tracks frames to know when to speed up/increase difficulty
obstacleRamp    DWORD   25000           ; amount of time required to increase the number of maximum lanes with obstacles 

; Obstacles are arrays [0..2] for simplicity:
obs_active      BYTE    MAX_OBS DUP(0)  ; 1 if in use, clears after user dodges
obs_lane        BYTE    MAX_OBS DUP(0)  ; lane index (0..LANES-1)
obs_row         BYTE    MAX_OBS DUP(0)  ; obstacle -> current row (0..ROAD_BOTTOM)

; Game HUD/UI strings
titleStr        BYTE    "RETRO HIGHWAY RACER",0
controlsStr         BYTE    "A/D or <-/-> to move, and ESC to quit",0
scoreStr        BYTE    "Score: ",0
highscoreStr           BYTE    "High Score: ",0
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

    push eax ebx

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

    pop  ebx eax
    ret

    ret
InitGame ENDP

; ===================================================================
; PollInput — read a key if present and adjust player lane.
; Uses Irvine ReadKey: ZF=1 if no key was available.
; - ESC exits fast program via ExitProcess.
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

    cmp ah, 1Bh      ; 1Bh refers to 'esc'
    je ExitGame      jump to where exiting the game is handled

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
    mov alive, 0
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
; ===================================================================
SpawnObstacle PROC
    ; code...
    ret
SpawnObstacle ENDP


; ===================================================================
; UpdateObstacles — all the active obstacle moves down by 1 row
; deactivate/clear when past ROAD_BOTTOM.
; Check to ensure a valid path for player 
; Example invalid path:
; | # :   |
; |   : # |
; ===================================================================
UpdateObstacles PROC
    ; code...
    ret
UpdateObstacles ENDP


; ===================================================================
; CheckCollision — if any obstacle is at the players row AND same lane,
; set alive = 0(player loses) and updates score/highScore.
; Check, is obstacle in row above car when next game tick happens, so check then move obstacles
; ===================================================================
CheckCollision PROC
    ; code...
    ret
CheckCollision ENDP



; ===================================================================
; DrawFrame — clears the screen and draws HUD, road, obstacle, player
; ===================================================================
DrawFrame PROC
    ; code...
    ret
DrawFrame ENDP



; ===================================================================
; DrawHUD — title, controls text, and score/highscore above the game board
; ===================================================================
DrawHUD PROC
    ; code...
    ret
DrawHUD ENDP


; ===================================================================
; DrawRoad — draws left/right borders and dotted lane markers, like a highway
; Example: |   :   :   :   :   :   |
;          |   :   :   :   :   :   |
; Should play around with how many lanes are manageable
; ===================================================================
DrawRoad PROC
    ; code...
    ret
DrawRoad ENDP


; ===================================================================
; DrawPlayer — print the player icon at the fixed row and current lane 
; column, updates on moves, left/right
; row, when obstacles move down, since lanes don't move, car doesn't move vertically
; ===================================================================
DrawPlayer PROC
    ; code...
    ret
DrawPlayer ENDP



; ===================================================================
; DrawObstacles — print an obstacle for each active obstacle at (row, lane)
; ===================================================================
DrawObstacles PROC
    push eax ecx edx

    mov  eax, COLOR_ROAD
    call SetTextColor

    ; Draw rows ROAD_TOP..ROAD_BOTTOM
    mov  ecx, ROAD_BOTTOM - ROAD_TOP + 1
    mov  dh, ROAD_TOP
    

    ret
DrawObstacles ENDP


; ===================================================================
; RampDifficulty — every 80-ish ticks, decrease the delay and increase the spawn rate.
; - tickDelay = max(55, tickDelay - 2)
; - spawnOdds = min(45, spawnOdds + 1)
; ===================================================================
RampDifficulty PROC
    ; code...
    ret
RampDifficulty ENDP


; ===================================================================
; GameOverScreen — print game over text, update high score,
; then await key press before returning and ExitProcess
; have a way to print to a file, read from a file, and compare highscore on the file to last played score
; ===================================================================
GameOverScreen PROC
    ; code...
    ret
GameOverScreen ENDP

END main
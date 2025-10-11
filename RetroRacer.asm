; ===========================================================
;RetroRacer.asm
;------------------------------------------------------------
; Controls:   A / D  or  ← / →  to change lanes.   ESC to quit.
; Goal:       Dodge obstacles on the highway. Get the highest Score.
;             Score increases over time.
; Difficulty: Spawn chance and speed ramp automatically.
; ============================================================

.386
.model flat, stdcall
.stack 4096
ExitProcess PROTO, dwExitCode:DWORD

INCLUDE Irvine32.inc

; ======================= Constants =========================
LANES           EQU     3           ; # of lanes 
MAX_OBS         EQU     32          ; max active obstacles tracked at once

BORDER_LEFT     EQU     12          ; left wall x-position, (col)
BORDER_RIGHT    EQU     44          ; right wall x-position, (row)
ROAD_TOP        EQU     2           ; first highway row
ROAD_BOTTOM     EQU     23          ; last highway row
PLAYER_ROW      EQU     (ROAD_BOTTOM-1) ; where the car sits (second line from the bottom)

PLAYER_CHAR     EQU     '^'         ; player glyph
OB_CHAR         EQU     '#'         ; obstacle glyph
BORDER_CHAR     EQU     '|'         ; border glyph
LANE_CHAR       EQU     ':'         ; lane marker glyph

COLOR_HUD       EQU     (yellow)                 ; HUD text color on black background
COLOR_ROAD      EQU     (white + (black*16))     ; road text color 

; ======================= DATA =======================
.data
; Column centers for each lane (Modiofy to make wider/narrower)
laneX           BYTE    18, 28, 38

; Game start state
playerLane      BYTE    1               ; start in middle lane
alive           BYTE    1               ; 1 = running, 0 = dead
score           DWORD   0               ; 
highScore       DWORD   0               ; run per session

; Game timing & difficulty, can modify later
tickDelay       WORD    120             ; The ms per frame, for speeding down/up
spawnOdds       BYTE    14              ; percentage (0..100). Spawn if roll < spawnOdds
tickCount       DWORD   0               ; tracks frames to known when to speed up/increase difficulty

; Obstacles are arrays [0..2] for simplicity:
obs_active      BYTE    MAX_OBS DUP(0)  ; 1 if in use, clears after user dodges
obs_lane        BYTE    MAX_OBS DUP(0)  ; lane index (0..LANES-1)
obs_row         BYTE    MAX_OBS DUP(0)  ; obstacle -> current row (0..ROAD_BOTTOM)


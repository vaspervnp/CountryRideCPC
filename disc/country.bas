10 REM COUNTRY RIDE - loader
20 REM The screen the car is picked on (SELECT.SCR, tools/mkselect.py) shows
30 REM while the game loads: the road engine in banks 4, 5 and 6, the game in
40 REM bank 7 - each loaded at &4000 with that bank switched in over it - the
50 REM sound and the race's extras. The picked car's own code (CARn.BIN) then
60 REM goes at &1900, where BOOT.BIN finds it, and the rest, and puts them in place.
70 MODE 0:BORDER 1:FOR i=0 TO 15:INK i,0:NEXT
80 MEMORY &18FF
90 LOAD"SELECT.SCR",&C000
100 FOR i=0 TO 15:READ c:INK i,c:NEXT:INK 13,24,15
110 OUT &7F00,&C4:LOAD"ROADA.BIN",&4000
120 OUT &7F00,&C5:LOAD"ROADB.BIN",&4000
130 OUT &7F00,&C6:LOAD"ROADC.BIN",&4000
140 OUT &7F00,&C7:LOAD"GAME.BIN",&4000
145 LOAD"SOUND.BIN",&98C0:LOAD"RACE.BIN",&A0C0
150 OUT &7F00,&C0:INK 14,1:INK 15,26:s=0:p=13:GOSUB 500
160 REM 1-4 picks a car and starts; left, right, up, down move; fire starts
170 k$=INKEY$:IF k$>="1" AND k$<="4" THEN p=2:GOSUB 500:s=VAL(k$)-1:p=13:GOSUB 500:GOTO 300
180 j=JOY(0):d=0
190 IF INKEY(8)=0 OR INKEY(34)=0 OR (j AND 4) THEN d=3
200 IF INKEY(1)=0 OR INKEY(27)=0 OR (j AND 8) THEN d=1
210 IF INKEY(0)=0 OR INKEY(2)=0 OR (j AND 3) THEN d=2
220 IF d THEN p=2:GOSUB 500:s=(s+d) MOD 4:p=13:GOSUB 500:GOSUB 600
230 IF INKEY(47)=0 OR INKEY(18)=0 OR INKEY(6)=0 OR (j AND 48) THEN 300
240 GOTO 170
300 FOR i=0 TO 15:INK i,0:NEXT:BORDER 0
310 LOAD"CAR"+CHR$(48+s)+".BIN",&1900
320 LOAD"BOOT.BIN",&4000:CALL &4000
500 REM car s's frame in pen p (13: flashing, picked; 2: as the others)
510 x=4+320*(s MOD 2):y=360-158*(s\2)
520 MOVE x,y:DRAWR 308,0,p:DRAWR 0,-150:DRAWR -308,0:DRAWR 0,150
530 MOVE x,y-2:DRAWR 308,0:MOVE x,y-148:DRAWR 308,0:RETURN
600 IF INKEY(8)=0 OR INKEY(34)=0 OR INKEY(1)=0 OR INKEY(27)=0 OR INKEY(0)=0 OR INKEY(2)=0 OR JOY(0) THEN 600
610 RETURN
1000 REM the pens of SELECT.SCR (tools/mkselect.py writes them): the cars'
1010 REM colours, the picked car's frame (13), "loading" (14), the keys (15)
1020 DATA 0,1,2,11,14,26,13,6,3,15,24,16,23,24,26,1

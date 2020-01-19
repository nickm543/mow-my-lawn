%include "/usr/local/share/csc314/asm_io.inc"

; the file that stores the initial state
%define BOARD_FILE 'board.txt'

; how to represent everything
%define WALL_CHAR '&'
%define HOUSE_WALL_CHAR '|'
%define HOUSE_ROOF_LEFT_CHAR '/'
%define HOUSE_ROOF_RIGHT_CHAR '\'
%define HOUSE_FLOOR_CHAR '-'
%define REFUEL_CHAR '_'
%define PLAYER_CHAR_RIGHT '>'
%define PLAYER_CHAR_LEFT '<'
%define PLAYER_CHAR_UP '^'
%define PLAYER_CHAR_DOWN 'v'
%define EMPTY_CHAR ' '

%define FLOWER_CHAR '*'
%define ROCK_CHAR '@'

; the size of the game screen in characters
%define HEIGHT 20
%define WIDTH 40

; the player starting position.
; top left is considered (0,0)
%define STARTX 17
%define STARTY 1

; these keys do things
%define EXITCHAR 'x'
%define UPCHAR 'w'
%define LEFTCHAR 'a'
%define DOWNCHAR 's'
%define RIGHTCHAR 'd'


segment .data

	; used to fopen() the board file defined above
	board_file			db BOARD_FILE,0

	; used to change the terminal mode
	mode_r				db "r",0
	raw_mode_on_cmd		db "stty raw -echo",0
	raw_mode_off_cmd	db "stty -raw echo",0

	; called by system() to clear/refresh the screen
	clear_screen_cmd	db "clear",0

	title_str			db 27,"[92mMOW THE LAWN!",27,"[39m",13,10,0

	; things the program will print
	help_str			db 13,10,27,"[93mControls: ", \
							UPCHAR,"=UP / ", \
							LEFTCHAR,"=LEFT / ", \
							DOWNCHAR,"=DOWN / ", \
							RIGHTCHAR,"=RIGHT / ", \
							EXITCHAR,"=EXIT", \
							27,"[39m",13,10,10,0

	angry_flower_str		db 27,"[91mMom says: DON'T MOW OVER MY FLOWERS!!",27,"[39m",10,0

	broken_mower_str		db 27,"[91mYou hit a rock and broke your mower! Game Over!",27,"[39m",13,10,10,0

	score_str				db 27,"[93mScore: %d",27,"[39m",13,10,10,0

	mower_damage_str		db 27,"[91mYou damaged your mower from hitting a rock! Be careful!",27,"[39m",10,0

	mower_damage_level_str	db 27,"[93mMower Damage Level: %d",27,"[39m",13,10,10,0

	win_str		db 27,"[92mCongratulations! You mowed all the grass! :)",27,"[39m",13,10,10,0

	fuel_str	db	27,"[93mGas: %d",27,"[39m",13,10,10,0

	no_fuel_str	db	27,"[91mYou ran out of gas! :(",27,"[39m",13,10,10,0

	final_score_str		db 27,"[92mFinal Score: %d",27,"[39m",13,10,10,0

segment .bss

	; this array stores the current rendered gameboard (HxW)
	board	resb	(HEIGHT * WIDTH)

	; these variables store the current player position
	xpos	resd	1
	ypos	resd	1

	p_direction		resd	1		; store player direction

	score			resd	1		; store score

	mower_damage	resd	1		; store # of times mower has been damaged by rocks

	fuel	resd	1

segment .text

	global	asm_main
	global  raw_mode_on
	global  raw_mode_off
	global  init_board
	global  render

	extern	system
	extern	putchar
	extern	getchar
	extern	printf
	extern	fopen
	extern	fread
	extern	fgetc
	extern	fclose

	extern	usleep

asm_main:
	enter	0,0
	pusha
	;***************CODE STARTS HERE***************************

	; put the terminal in raw mode so the game works nicely
	call	raw_mode_on

	; read the game board file into the global variable
	call	init_board

	; set the player at the proper start position
	mov		DWORD [xpos], STARTX
	mov		DWORD [ypos], STARTY

	mov		DWORD [p_direction], 3		; start the player facing down

	mov		DWORD [score], 0		; set score

	mov		DWORD [mower_damage], 0		; set mower damage value

	mov		DWORD [fuel], 50

	; the game happens in this loop
	; the steps are...
	;   1. render (draw) the current board
	;   2. get a character from the user
	;	3. store current xpos,ypos in esi,edi
	;	4. update xpos,ypos based on character from user
	;	5. check what's in the buffer (board) at new xpos,ypos
	;	6. if it's a wall, reset xpos,ypos to saved esi,edi
	;	7. otherwise, just continue! (xpos,ypos are ok)
	game_loop:

		; draw the game board
		call	render

		; get an action from the user
		call	getchar

		; store the current position
		; we will test if the new position is legal
		; if not, we will restore these
		mov		esi, [xpos]
		mov		edi, [ypos]

		; check if we're out of gas
		cmp		DWORD [fuel], 0
		jle		game_loop_end

		; choose what to do
		cmp		eax, EXITCHAR
		je		game_loop_end
		cmp		eax, UPCHAR
		je 		move_up
		cmp		eax, LEFTCHAR
		je		move_left
		cmp		eax, DOWNCHAR
		je		move_down
		cmp		eax, RIGHTCHAR
		je		move_right
		jmp		input_end			; or just do nothing

		; move the player according to the input character
		move_up:
			mov		DWORD [p_direction], 2
			dec		DWORD [ypos]
			jmp		input_end
		move_left:
			mov		DWORD [p_direction], 0
			dec		DWORD [xpos]
			jmp		input_end
		move_down:
			mov		DWORD [p_direction], 3
			inc		DWORD [ypos]
			jmp		input_end
		move_right:
			mov		DWORD [p_direction], 1
			inc		DWORD [xpos]
		input_end:

		; (W * y) + x = pos

		; compare the current position to the wall character
		mov		eax, WIDTH
		mul		DWORD [ypos]
		add		eax, [xpos]
		lea		eax, [board + eax]
		cmp		BYTE [eax], WALL_CHAR
		jne		check_house_wall
			; opps, that was an invalid move, reset
			mov		DWORD [xpos], esi
			mov		DWORD [ypos], edi
		check_house_wall:
			mov		eax, WIDTH
			mul		DWORD [ypos]
			add		eax, [xpos]
			lea		eax, [board + eax]
			cmp		BYTE [eax], HOUSE_WALL_CHAR
			jne		check_house_roof_left
				; ran into the house
				mov		DWORD [xpos], esi
				mov		DWORD [ypos], edi
		check_house_roof_left:
			mov		eax, WIDTH
			mul		DWORD [ypos]
			add		eax, [xpos]
			lea		eax, [board + eax]
			cmp		BYTE [eax], HOUSE_ROOF_LEFT_CHAR
			jne		check_house_roof_right
				; ran into the house
				mov		DWORD [xpos], esi
				mov		DWORD [ypos], edi
		check_house_roof_right:
			mov		eax, WIDTH
			mul		DWORD [ypos]
			add		eax, [xpos]
			lea		eax, [board + eax]
			cmp		BYTE [eax], HOUSE_ROOF_RIGHT_CHAR
			jne		check_house_floor
				; ran into the house
				mov		DWORD [xpos], esi
				mov		DWORD [ypos], edi
		check_house_floor:
			mov		eax, WIDTH
			mul		DWORD [ypos]
			add		eax, [xpos]
			lea		eax, [board + eax]
			cmp		BYTE [eax], HOUSE_FLOOR_CHAR
			jne		check_refuel
				; ran into the house
				mov		DWORD [xpos], esi
				mov		DWORD [ypos], edi
		check_refuel:
			mov		eax, WIDTH
			mul		DWORD [ypos]
			add		eax, [xpos]
			lea		eax, [board + eax]
			cmp		BYTE [eax], REFUEL_CHAR
			jne		valid_move
				cmp		DWORD [fuel], 50
				jl		add_fuel
				mov		DWORD [xpos], esi
				mov		DWORD [ypos], edi
				jmp		valid_move
				add_fuel:
					add		DWORD [fuel], 50			; add the fuel
					mov		DWORD [xpos], esi			; don't let player go farther into house
					mov		DWORD [ypos], edi
		valid_move:

		mov		eax, WIDTH
		mul		DWORD [ypos]
		add		eax, [xpos]					; check if we're mowing over flower
		lea		eax, [board + eax]
		cmp		BYTE [eax], FLOWER_CHAR
		jne		check_rock
			; mow over flower
			dec		DWORD [fuel]
			mov		eax, WIDTH
			mul		DWORD [ypos]
			add		eax, DWORD [xpos]
			lea		eax, [board + eax]
			mov		BYTE [eax], EMPTY_CHAR

			sub		DWORD [score], 5

			push	angry_flower_str
			call	printf					; if we are, print angry flower string, in addition to mowing it, and dec score
			add		esp, 4

			push	1500000
			call	usleep
			add		esp, 4
		check_rock:
			mov		eax, WIDTH
			mul		DWORD [ypos]
			add		eax, DWORD [xpos]
			lea		eax, [board + eax]
			cmp		BYTE [eax], ROCK_CHAR
			jne		regular_mow
				; mow over rock
				dec		DWORD [fuel]
				mov		eax, WIDTH
				mul		DWORD [ypos]
				add		eax, DWORD [xpos]
				lea		eax, [board + eax]
				mov		BYTE [eax], EMPTY_CHAR

				cmp		DWORD [mower_damage], 2			; if mower has been damaged 3 times, break mower and end game
				jne		mower_not_broken
					; otherwise mower is broken
					push	broken_mower_str
					call	printf
					add		esp, 4

					push	1500000		; delay after printing
					call	usleep
					add		esp, 4

					jmp		game_loop_end
				mower_not_broken:

					inc		DWORD [mower_damage]		; increment mower damage value when rock is hit

					push	mower_damage_str
					call	printf
					add		esp, 4

					push	1500000
					call	usleep
					add		esp, 4
		regular_mow:
		; "mow" the "grass"
		dec		DWORD [fuel]
		inc		DWORD [score]
		mov		eax, WIDTH
		mul		DWORD [ypos]
		add		eax, DWORD [xpos]
		lea		eax, [board + eax]
		mov		BYTE [eax], EMPTY_CHAR

	jmp		game_loop
	game_loop_end:

	; check if out of fuel
	cmp		DWORD [fuel], 0
	jne		not_out_of_fuel
		push	no_fuel_str
		call	printf
		add		esp, 4
		jmp		end_win
	not_out_of_fuel:

	cmp		DWORD [score], 742		; check if all grass is mowed
	jge		win
	jmp		end_win
		win:
		push	win_str
		call	printf
		add		esp, 4
	end_win:

	push	DWORD [score]
	push	final_score_str
	call	printf
	add		esp, 8

	; restore old terminal functionality
	call raw_mode_off

	;***************CODE ENDS HERE*****************************
	popa
	mov		eax, 0
	leave
	ret

; === FUNCTION ===
raw_mode_on:

	push	ebp
	mov		ebp, esp

	push	raw_mode_on_cmd
	call	system
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

; === FUNCTION ===
raw_mode_off:

	push	ebp
	mov		ebp, esp

	push	raw_mode_off_cmd
	call	system
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

; === FUNCTION ===
init_board:

	push	ebp
	mov		ebp, esp

	; FILE* and loop counter
	; ebp-4, ebp-8
	sub		esp, 8

	; open the file
	push	mode_r
	push	board_file
	call	fopen
	add		esp, 8
	mov		DWORD [ebp-4], eax

	; read the file data into the global buffer
	; line-by-line so we can ignore the newline characters
	mov		DWORD [ebp-8], 0
	read_loop:
	cmp		DWORD [ebp-8], HEIGHT
	je		read_loop_end

		; find the offset (WIDTH * counter)
		mov		eax, WIDTH
		mul		DWORD [ebp-8]
		lea		ebx, [board + eax]

		; read the bytes into the buffer
		push	DWORD [ebp-4]
		push	WIDTH
		push	1
		push	ebx
		call	fread
		add		esp, 16

		; slurp up the newline
		push	DWORD [ebp-4]
		call	fgetc
		add		esp, 4

	inc		DWORD [ebp-8]
	jmp		read_loop
	read_loop_end:

	; close the open file handle
	push	DWORD [ebp-4]
	call	fclose
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

; === FUNCTION ===
render:

	push	ebp
	mov		ebp, esp

	; two ints, for two loop counters
	; ebp-4, ebp-8
	sub		esp, 8

	; clear the screen
	push	clear_screen_cmd
	call	system
	add		esp, 4

	; print the title string
	push	title_str
	call	printf
	add		esp, 4

	; print the help information
	push	help_str
	call	printf
	add		esp, 4

	; print score string
	push	DWORD [score]
	push	score_str
	call	printf
	add		esp, 4

	; print mower damage level string
	push	DWORD [mower_damage]
	push	mower_damage_level_str
	call	printf
	add		esp, 4

	; print fuel string
	push	DWORD [fuel]
	push	fuel_str
	call	printf
	add		esp, 4

	; outside loop by height
	; i.e. for(c=0; c<height; c++)
	mov		DWORD [ebp-4], 0
	y_loop_start:
	cmp		DWORD [ebp-4], HEIGHT
	je		y_loop_end

		; inside loop by width
		; i.e. for(c=0; c<width; c++)
		mov		DWORD [ebp-8], 0
		x_loop_start:
		cmp		DWORD [ebp-8], WIDTH
		je 		x_loop_end

			; check if (xpos,ypos)=(x,y)
			mov		eax, [xpos]
			cmp		eax, DWORD [ebp-8]
			jne		print_board
			mov		eax, [ypos]
			cmp		eax, DWORD [ebp-4]
			jne		print_board
				; if both were equal, print the player

				cmp		DWORD [p_direction], 1
				je		player_right
				cmp		DWORD [p_direction], 0
				je		player_left
				cmp		DWORD [p_direction], 2
				je		player_up
				cmp		DWORD [p_direction], 3
				je		player_down
				jmp		print_board
				player_right:
					push	PLAYER_CHAR_RIGHT
					jmp		print_end
				player_left:
					push	PLAYER_CHAR_LEFT
					jmp		print_end
				player_up:
					push	PLAYER_CHAR_UP
					jmp		print_end
				player_down:
					push	PLAYER_CHAR_DOWN
					jmp		print_end

			print_board:
				; otherwise print whatever's in the buffer
				mov		eax, [ebp-4]
				mov		ebx, WIDTH
				mul		ebx
				add		eax, [ebp-8]
				mov		ebx, 0
				mov		bl, BYTE [board + eax]
				push	ebx
			print_end:
			call	putchar
			add		esp, 4

		inc		DWORD [ebp-8]
		jmp		x_loop_start
		x_loop_end:

		; write a carriage return (necessary when in raw mode)
		push	0x0d
		call 	putchar
		add		esp, 4

		; write a newline
		push	0x0a
		call	putchar
		add		esp, 4

	inc		DWORD [ebp-4]
	jmp		y_loop_start
	y_loop_end:

	mov		esp, ebp
	pop		ebp
	ret

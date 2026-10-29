#!/bin/bash
# Phone-sized tweaks to mainui_cpp, the engine's menus (3rdparty/mainui) and
# Counter-Strike's copy of them, applied at build time so both submodules
# stay as upstream has them. Each fails loudly if upstream code moved.

# The top-right buttons are for desktop windows: on a phone minimize does
# nothing and close is too small to hit. No minimize, close twice the size.
patch_menu_buttons() {
	perl -pi -e 's/^\s*AddItem\( minimizeBtn \);\s*$//; s/quitButton\.SetRect\( uiStatic\.width - 36, 13, 32, 32 \);/quitButton.SetRect( uiStatic.width - 76, 10, 64, 64 );/' "$1/menus/Main.cpp"
	if grep -q 'AddItem( minimizeBtn )' "$1/menus/Main.cpp" || ! grep -q 'uiStatic.width - 76, 10, 64, 64' "$1/menus/Main.cpp"; then
		echo "menu buttons patch didn't apply to $1"
		return 1
	fi
}

# The menus are laid out for a 768 pixel tall screen; a phone held sideways
# is about half that, so their text comes out small. Text a quarter bigger.
MENU_TEXT_SCALE=${MENU_TEXT_SCALE:-1.25}
patch_menu_text() {
	local f="$1/font/FontRenderer.h"
	perl -pi -e 'if( /^(#define\s+UI_(CONSOLE|SMALL|SMALLER|TINY|MED|BIG)_CHAR_(WIDTH|HEIGHT)\s+)(\d+)/ ) { $_ = $1 . int( $4 * '"$MENU_TEXT_SCALE"' + 0.5 ) . "\n"; }' "$f"
	if grep -qE 'UI_MED_CHAR_HEIGHT\s+26\b' "$f"; then
		echo "menu text patch didn't apply to $f"
		return 1
	fi
}

# Counter-Strike's main menu: Play CS first, not under Training,
# Configuration and Load Game
patch_cs_play_first() {
	local f="$1/menus/Main.cpp"
	perl -0pi -e 's/(\tmultiPlayer\.SetCoord\( hoffset, yoffset \);\r?\n\tyoffset -= ygap;\r?\n)(.*?)(\tnewGame\.SetCoord\( hoffset, yoffset \);)/$2$1$3/s; s/(\tAddItem\( multiPlayer \);\r?\n)(.*?)(\tAddItem\( readme \);)/$2$3/s; s/(\tAddItem\( newGame \);\r?\n)/$1\tAddItem( multiPlayer );\n/' "$f"
	if ! perl -0ne 'exit( /multiPlayer\.SetCoord\( hoffset, yoffset \);\r?\n\tyoffset -= ygap;\r?\n\r?\n?\tnewGame\.SetCoord/ ? 0 : 1 )' "$f"; then
		echo "Play CS first patch didn't apply to $f"
		return 1
	fi
}

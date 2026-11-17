#!/bin/bash
# The iOS port's additions to hlsdk-portable's game code, applied at build
# time (as scripts/ios/patch_mainui.sh does for the menus) so the game
# branches build as upstream has them. Each fails loudly if upstream code moved.

# The cheat's ammo: while the engine's ios_cheat_ammo is on
# (engine/platform/ios/ios_cheats.c), every weapon the player has keeps a
# full magazine, so it never reloads, and full spare ammo (single player only). At the start of
# each frame's weapon think, before a weapon could start a reload.
patch_hlsdk_ammo() {
	local f="$1/dlls/player.cpp"
	perl -0pi -e 's/(\nvoid CBasePlayer::ItemPostFrame\(\s*(?:void)?\s*\)\r?\n\{\r?\n)/$1\tIOS_CheatAmmo( this );\n/' "$f"
	perl -0pi -e 's/(\nvoid CBasePlayer::ItemPostFrame\()/\n\/\/ the iOS port'"'"'s cheat ammo (xash3d-fwgs scripts\/ios\/patch_hlsdk.sh)\nstatic void IOS_CheatAmmo( CBasePlayer *pl )\n{\n\tstatic cvar_t *on;\n\n\tif( !on )\n\t\ton = CVAR_GET_POINTER( "ios_cheat_ammo" );\n\tif( !on || on->value <= 0.0f || gpGlobals->maxClients != 1 )\n\t\treturn;\n\n\tfor( int i = 0; i < MAX_ITEM_TYPES; i++ )\n\t{\n\t\tfor( CBasePlayerItem *it = pl->m_rgpPlayerItems[i]; it; it = it->m_pNext )\n\t\t{\n\t\t\tCBasePlayerWeapon *w = (CBasePlayerWeapon *)it->GetWeaponPtr();\n\t\t\tint a;\n\n\t\t\tif( !w )\n\t\t\t\tcontinue;\n\t\t\tif( w->iMaxClip() != WEAPON_NOCLIP && w->m_iClip < w->iMaxClip() )\n\t\t\t\tw->m_iClip = w->iMaxClip();\n\t\t\tif( w->pszAmmo1() && ( a = CBasePlayer::GetAmmoIndex( w->pszAmmo1() )) >= 0 && pl->m_rgAmmo[a] < w->iMaxAmmo1() )\n\t\t\t\tpl->m_rgAmmo[a] = w->iMaxAmmo1();\n\t\t\tif( w->pszAmmo2() && ( a = CBasePlayer::GetAmmoIndex( w->pszAmmo2() )) >= 0 && pl->m_rgAmmo[a] < w->iMaxAmmo2() )\n\t\t\t\tpl->m_rgAmmo[a] = w->iMaxAmmo2();\n\t\t}\n\t}\n}\n$1/' "$f"
	if [ "$(grep -c 'IOS_CheatAmmo' "$f")" -ne 2 ]; then
		echo "cheat ammo patch didn't apply to $f"
		return 1
	fi
}

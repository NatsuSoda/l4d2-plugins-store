/*
2.1.1 修复错误的增幅红点检测

2.1修复增幅模式关闭的情况下清空连喷连狙的红点问题、调整马格南连发速度
细化各项设置，重新建立autocfg
1.0和2.1都添加防重复读取机制

2.0更换实现方式，降低了些许性能消耗，增加对马格南及连喷的支持
简化插件结构，将全自动设置为默认模式，切换模式不再强制换弹
取消额外射速增幅值
根据left4dhooks的运行情况调整后坐力
*/
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <l4d2util>
#include <colors>
#undef REQUIRE_PLUGIN
#include <left4dhooks>

enum
{
	WP_Pistol,
	WP_Magnum,
	WP_AutoShotGun,
	WP_Sniper,
	WP_Size
};
static char g_sShortName[][] = {
	"手枪",
	"马格南",
	"连喷",
	"连狙"
};
static char g_sEngShortName[][] = {
	"pistol",
	"magnum",
	"autoshotgun",
	"sniper"
};
bool   g_bEnable[MAXPLAYERS + 1][WP_Size];
bool   g_bFired[MAXPLAYERS + 1][WP_Size];
bool   g_bFullAuto[WP_Size];
bool   g_bEnhancement[WP_Size];
int	   g_iLastBtn[MAXPLAYERS + 1];
bool   g_bPluginEnable, g_bVerticalPunch, g_bl4dhEnable;
ConVar g_hEnhancement[WP_Size];
ConVar g_hFullAuto[WP_Size];
ConVar g_hPluginEnable, g_hVerticalPunch;

public Plugin myinfo =
{
	name		= "Auto Weapon",
	author		= "Nepkey",
	description = "使得手枪系武器、连喷、连狙全自动, 按鼠标中键可切换",
	version		= "2.1 - 2025.3.2",
	url			= "https://space.bilibili.com/436650372"

};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();
	if (engine != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}
	if (LibraryExists("autopistol_nepkey"))
	{
		strcopy(error, err_max, "Did you repeatedly load this plugin? Or are both versions 1.0 and 2.0 being used simultaneously?");
		return APLRes_SilentFailure;
	}
	RegPluginLibrary("autopistol_nepkey");
	return APLRes_Success;
}

public void OnClientPutInServer(int client)
{
	g_iLastBtn[client] = 0;
	for (int i; i < WP_Size; i++)
	{
		g_bEnable[client][i] = true;
		g_bFired[client][i]	 = false;
	}
	SDKHook(client, SDKHook_WeaponSwitchPost, LaserCheck);
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_WeaponSwitchPost, LaserCheck);
}

public void OnPluginStart()
{
	g_hPluginEnable = CreateConVar("l4d2_autopistol_enable", "1", "1 = 启用插件, 0 = 禁用插件", 0, true, 0.0, true, 1.0);
	for (int i; i < WP_Size; i++)
	{
		char sBuffer[2][256];
		Format(sBuffer[0], sizeof(sBuffer[]), "l4d2_autopistol_%s_fullauto", g_sEngShortName[i]);
		Format(sBuffer[1], sizeof(sBuffer[]), "1 = 启用[%s]全自动射击, 0 = 禁用", g_sShortName[i]);
		g_hFullAuto[i] = CreateConVar(sBuffer[0], "1", sBuffer[1], 0, true, 0.0, true, 1.0);
		g_hFullAuto[i].AddChangeHook(OnCvarChanged);
		Format(sBuffer[0], sizeof(sBuffer[]), "l4d2_autopistol_%s_enhance", g_sEngShortName[i]);
		Format(sBuffer[1], sizeof(sBuffer[]), "1 = 启用[%s]增幅, 0 = 禁用", g_sShortName[i]);
		g_hEnhancement[i] = CreateConVar(sBuffer[0], "1", sBuffer[1], 0, true, 0.0, true, 1.0);
		g_hEnhancement[i].AddChangeHook(OnCvarChanged);
	}
	g_hVerticalPunch = CreateConVar("l4d2_autopistol_verticalpunch", "1", "1 = 启用后坐力修改, 0 = 禁用后坐力修改", 0, true, 0.0, true, 1.0);
	g_hPluginEnable.AddChangeHook(OnCvarChanged);
	g_hVerticalPunch.AddChangeHook(OnCvarChanged);

	HookEvent("weapon_fire", AfterWeaponFire, EventHookMode_Post);
	RegAdminCmd("sm_enhance", ModeChange_CMD, ADMFLAG_CONVARS, "Admin命令, 可打开或关闭增幅模式");

	AutoExecConfig(true, "autopistol_2x");
	GetCvars();
}

public void OnAllPluginsLoaded()
{
	g_bl4dhEnable = LibraryExists("left4dhooks");
	if (g_bl4dhEnable) SetPistolVerticalpunch(g_bVerticalPunch);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "left4dhooks")) g_bl4dhEnable = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "left4dhooks")) g_bl4dhEnable = false;
}

public void OnPlayerRunCmdPost(int client, int buttons)
{
	if (!g_bPluginEnable || !client) return;
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	int index  = EntFullAutoIndex(weapon);
	if (index > -1 && g_bFullAuto[index] && (buttons & IN_ATTACK) && g_bEnable[client][index] && g_bFired[client][index])
	{
		if (g_bEnhancement[index])
		{
			AdjustPistolFireSpeed(weapon);
		}
		if (HasEntProp(weapon, Prop_Send, "m_isHoldingFireButton"))
		{
			SetEntProp(weapon, Prop_Send, "m_isHoldingFireButton", 0);
			SetEntProp(weapon, Prop_Send, "m_releasedFireButton", 1);
		}
		// 防止反复设置下次开火
		g_bFired[client][index] = false;
	}
	else if (index > -1 && index != 3 && g_bFullAuto[index] && (buttons & IN_ZOOM) && !(g_iLastBtn[client] & IN_ZOOM))
	{
		g_bEnable[client][index] = !g_bEnable[client][index];
		PlayModeSound(g_bEnable[client][index], client);
		char info[128];
		FormatEx(info, sizeof(info), "%s 射击模式: %s 增幅状态: %s", g_sShortName[index], g_bEnable[client][index] ? "全自动" : "点射", g_bEnhancement[index] ? "开启" : "关闭");
		PrintHintText(client, "%s", info);
		SetLaser(client, weapon, index);
	}
	g_iLastBtn[client] = buttons;
}

void AfterWeaponFire(Event e, const char[] n, bool b)
{
	if (!g_bPluginEnable) return;
	int client = GetClientOfUserId(e.GetInt("userid"));
	int index  = FullAutoIndex(e.GetInt("weaponid"));
	if (!client || index < 0) return;
	g_bFired[client][index] = true;
}

Action ModeChange_CMD(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "用法: sm_enhance index || index从0到3依次代表 手枪、连喷、连狙");
		return Plugin_Handled;
	}
	int index = GetCmdArgInt(1);
	if (index < 0 || index >= WP_Size)
	{
		ReplyToCommand(client, "参数index无效，示例：sm_enhance 0");
		return Plugin_Handled;
	}
	SetConVarBool(g_hEnhancement[index], !g_bEnhancement[index]);
	CPrintToChatAll("{green}[AutoPistol]{olive} %s 增幅开关当前状态: %s", g_sShortName[index], g_bEnhancement[index] ? "启用" : "禁用");
	return Plugin_Handled;
}

void OnCvarChanged(ConVar c, const char[] n, const char[] o)
{
	GetCvars();
}

void GetCvars()
{
	g_bPluginEnable	 = g_hPluginEnable.BoolValue;
	g_bVerticalPunch = g_hVerticalPunch.BoolValue;
	if (g_bl4dhEnable) SetPistolVerticalpunch(g_bVerticalPunch);
	for (int i; i < WP_Size; i++)
	{
		g_bFullAuto[i]	  = g_hFullAuto[i].BoolValue;
		g_bEnhancement[i] = g_hEnhancement[i].BoolValue;
	}
}

void AdjustPistolFireSpeed(int weaponEnt)
{
	float fTime = GetGameTime();
	switch (IdentifyWeapon(weaponEnt))
	{
		case WEPID_PISTOL:
		{
			fTime += IsDualWielding(weaponEnt) ? 0.075 : 0.1;
		}
		case WEPID_PISTOL_MAGNUM:
		{
			fTime += 0.20;
		}
		case WEPID_AUTOSHOTGUN, WEPID_SHOTGUN_SPAS:
		{
			fTime += 0.15;
		}
		case WEPID_SNIPER_MILITARY, WEPID_HUNTING_RIFLE:
		{
			fTime += 0.20;
		}
		default:
		{
			return;
		}
	}
	SetEntPropFloat(weaponEnt, Prop_Send, "m_flNextPrimaryAttack", fTime);
}

void LaserCheck(int client, int weapon)
{
	int index = EntFullAutoIndex(weapon);
	if (index > -1)
	{
		SetLaser(client, weapon, index);
	}
}

void SetLaser(int client, int weapon, int index)
{
	if (g_bEnable[client][index] && g_bEnhancement[index])
	{
		SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", 4);
	}
}

void PlayModeSound(bool Enable, int client)
{
	char SoundPath[2][128] = { "player/orch_hit_csharp_short.wav", "ui/menu_click01.wav" };
	PrecacheSound(SoundPath[0]);
	PrecacheSound(SoundPath[1]);
	EmitSoundToClient(client, SoundPath[Enable ? 0 : 1]);
}

void SetPistolVerticalpunch(bool enhance)
{
	L4D2_SetFloatWeaponAttribute("weapon_pistol", view_as<L4D2FloatWeaponAttributes>(17), enhance ? 0.9 : 2.0);
	L4D2_SetFloatWeaponAttribute("weapon_pistol_magnum", view_as<L4D2FloatWeaponAttributes>(17), enhance ? 0.3 : 4.0);
	L4D2_SetFloatWeaponAttribute("weapon_sniper_military", view_as<L4D2FloatWeaponAttributes>(17), enhance ? 0.9 : 1.5);
}

int FullAutoIndex(int weaponID)
{
	switch (weaponID)
	{
		case WEPID_PISTOL:
		{
			return WP_Pistol;
		}
		case WEPID_PISTOL_MAGNUM:
		{
			return WP_Magnum;
		}
		case WEPID_AUTOSHOTGUN, WEPID_SHOTGUN_SPAS:
		{
			return WP_AutoShotGun;
		}
		case WEPID_SNIPER_MILITARY, WEPID_HUNTING_RIFLE:
		{
			return WP_Sniper;
		}
	}
	return -1;
}

int EntFullAutoIndex(int weaponEnt)
{
	int wepID = IdentifyWeapon(weaponEnt);
	return FullAutoIndex(wepID);
}

bool IsDualWielding(int weaponEnt)
{
	return GetEntProp(weaponEnt, Prop_Send, "m_isDualWielding") > 0;
}
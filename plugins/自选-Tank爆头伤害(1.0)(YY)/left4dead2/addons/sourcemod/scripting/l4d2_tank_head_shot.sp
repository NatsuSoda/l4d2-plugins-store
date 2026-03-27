#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <left4dhooks>

#define PLUGIN_NAME           "l4d2_tank_head_shot"
#define PLUGIN_AUTHOR         "YY"
#define PLUGIN_DESCRIPTION    "Set tank head shot damage"
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            ""


#define	PrintChat		(1 << 0)
#define PrintHint		(1 << 1)

ConVar g_tankhsEnable,g_tankhsPrompt,g_damageMultiple,g_numberMultiple,g_damageMultiple4,g_damageMultiple8;
bool g_btankhsEnable,g_bnumberMultiple;
int g_itankhsPrompt,g_realidamageMultiple,g_idamageMultiple,g_idamageMultiple4,g_idamageMultiple8;



public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	g_tankhsEnable = CreateConVar("sm_tankheadshot_enable",					"1",		"插件开关. 0=禁用, 1=启用", FCVAR_NONE, true, 0.0, true, 1.0 );
	g_tankhsPrompt		= CreateConVar("sm_tankheadshot_prompt", 			"3", 		"爆头坦克提示类型(启用多个就把数字相加). 0=禁用, 1=聊天窗, 2=屏幕中下.", FCVAR_NONE, true, 0.0, true, 3.0);

	g_numberMultiple = CreateConVar("sm_tankheadshot_numberMultiple",		"1",		"是否启用伤害倍数随人数变化,禁用将一直使用默认倍数. 0=禁用, 1=启用", FCVAR_NONE, true, 0.0, true, 1.0 );

	g_damageMultiple		= CreateConVar("sm_tankheadshot_damagemultiple","10",		"爆头坦克的默认伤害倍数(仅枪械,不包括榴弹)", _, true, 0.0);
	g_damageMultiple4		= CreateConVar("sm_tankheadshot_damagemultiple4", 		"20",	"超过4人时爆头坦克的伤害倍数(仅枪械,不包括榴弹)", _, true, 0.0);
	g_damageMultiple8		= CreateConVar("sm_tankheadshot_damagemultiple8", 		"40",	"超过8人时爆头坦克的伤害倍数(仅枪械,不包括榴弹)", _, true, 0.0);

	
	g_tankhsEnable.AddChangeHook(ConVarChanged);
	g_tankhsPrompt.AddChangeHook(ConVarChanged);


	//玩家队伍变化，包括断开
	//HookEvent("player_team",			Event_PlayerTeam);


	AutoExecConfig(true, PLUGIN_NAME);
}
public void OnConfigsExecuted()
{
	GetCvars();
}

public void ConVarChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_btankhsEnable = g_tankhsEnable.BoolValue;
	g_itankhsPrompt=g_tankhsPrompt.IntValue;
	g_idamageMultiple=g_damageMultiple.IntValue;

	g_bnumberMultiple=g_numberMultiple.BoolValue;
	g_idamageMultiple4=g_damageMultiple4.IntValue;
	g_idamageMultiple8=g_damageMultiple8.IntValue;

	g_realidamageMultiple=g_idamageMultiple;
}


public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_TraceAttack, Tank_TraceAttack);

}

public Action Tank_TraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	if (!g_btankhsEnable || !IsValidEntity(victim) || !isValidSurvivor(attacker)|| !IsTank(victim)) return Plugin_Continue;

	//PrintToChatAll("爆头触发前的伤害:  damage：%f damagetype：%x ammotype：%x", damage, damagetype, ammotype);


	if(g_realidamageMultiple>0 && hitgroup==1  &&ammotype!=-1){

		//PrintToChatAll("爆头触发后的伤害:  damage：%f damagetype：%x ammotype：%x", damage, damagetype, ammotype);

		damage=g_realidamageMultiple*damage;
		
		if(g_itankhsPrompt & PrintChat)
			//聊天窗提示.
			PrintToChat(attacker,"爆头坦克%.0f伤害(%d倍)",damage,g_realidamageMultiple);
			
		if(g_itankhsPrompt & PrintHint)
			//屏幕中下提示.
			PrintHintText(attacker,"爆头坦克%.0f伤害(%d倍)",damage,g_realidamageMultiple);

		return Plugin_Changed;
	}else
	{
		return Plugin_Continue;
	}
	

}



//玩家连接成功.
public void OnClientPostAdminCheck(int client)
{
	if(IsFakeClient(client)||!g_bnumberMultiple)
		return;
	int playerNumber=RealSurvival();

	if(playerNumber>4 && playerNumber<8){

		if(g_idamageMultiple4>0){
			
			g_realidamageMultiple=g_idamageMultiple4;
		}
		PrintToChatAll("玩家人数:%d,Tank爆头%d倍伤害",playerNumber,g_realidamageMultiple);
	}
	if(playerNumber>=8){
		if(g_idamageMultiple8>0){
			
			g_realidamageMultiple=g_idamageMultiple8;
		}
		PrintToChatAll("玩家人数:%d,Tank爆头%d倍伤害",playerNumber,g_realidamageMultiple);

	}
	
	
}



//玩家退出
public void OnClientDisconnect(int client)
{   
	if(IsFakeClient(client)||!g_bnumberMultiple)
		return;
	int playerNumber=RealSurvival();

	if(playerNumber>4 && playerNumber<8){

		if(g_idamageMultiple4>0){
			
			g_realidamageMultiple=g_idamageMultiple4;
			PrintToChatAll("玩家人数%d,Tank爆头%d倍伤害",playerNumber,g_realidamageMultiple);

		}
	}
	if(playerNumber>=8){
		if(g_idamageMultiple8>0){
			
			g_realidamageMultiple=g_idamageMultiple8;
			PrintToChatAll("玩家人数%d,Tank爆头%d倍伤害",playerNumber,g_realidamageMultiple);

		}

	}
}


int RealSurvival()
{
	int iCount=0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsClientConnected(i))
		{
			if(IsPlayerAlive(i))
			{
				iCount++;
			}
		}
	}
	return iCount;
}

bool isValidSurvivor(int client)
{
	return !(client <= 0 || client > MaxClients || !IsClientConnected(client) || !IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client));
}
bool IsTank(int victim)
{
	return victim > 0 && victim <= MaxClients && IsClientInGame(victim) && GetClientTeam(victim) == 3 && GetEntProp(victim, Prop_Send, "m_zombieClass") == 8;
}

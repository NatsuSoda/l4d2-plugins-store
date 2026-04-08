#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.2"
#define CUESOUND       "level/popup.wav"

#define CVAR_FLAGS     FCVAR_NOTIFY

ConVar hMode;
ConVar hflag;
ConVar hMultiplier;
ConVar hLimit;

bool   bCueAllowed[MAXPLAYERS + 1] = { false, ... };
int    bBunnyhopEnable[MAXPLAYERS + 1];
int    iOffset                         = 0;
int    iDirectionCache[MAXPLAYERS + 1] = { 0, ... };

public Plugin myinfo =
{
  name        = "bunnyhop+",
  author      = "coleo, laoyutang",
  description = "A fully featured bunnyhop plugin for Left",
  version     = PLUGIN_VERSION,
  url         = ""


}

public void
  OnPluginStart()
{
  CreateConVar("l4d_bunnyhop_version", PLUGIN_VERSION, "version of bunnyhop+", CVAR_FLAGS);

  hMode       = CreateConVar("l4d_bunnyhop_mode", "1", "插件模式 (0)禁用 (1)开启连跳 (2)连跳训练模式", CVAR_FLAGS, true, 0.0, true, 2.0);
  hflag       = CreateConVar("l4d_bunnyhop_enable", "0", "是否默认开启连跳功能(需要插件模式设置为1) (0)禁用 (1)默认开启连跳", CVAR_FLAGS, true, 0.0, true, 1.0);
  hMultiplier = CreateConVar("l4d_bunnyhop_multiplier", "50", "每次连跳成功后奖励玩家加速的值.", CVAR_FLAGS, true, 0.0, true, 200.0);
  hLimit      = CreateConVar("l4d_bunnyhop_limit", "500", "连跳速度上限", CVAR_FLAGS, true, 0.0, true, 10000.0);

  HookEvent("player_jump_apex", Event_PlayerJumpApex);

  RegAdminCmd("sm_rb", Command_Setflag, ADMFLAG_ROOT, "管理员打开或者关闭连跳总开关");

  RegConsoleCmd("sm_bhop", Command_Autobhop, "玩家开关自动连跳");
  RegConsoleCmd("sm_onrb", Command_Onbhop, "玩家开启自动连跳");
  RegConsoleCmd("sm_offrb", Command_Offbhop, "玩家关闭自动连跳");

  AutoExecConfig(true, "l4d_bunnyhop");
}

public void OnMapStart()
{
  PrecacheSound(CUESOUND, true);

  for (int i = 1; i <= MaxClients; i++)
  {
    if (IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i))
      bBunnyhopEnable[i] = hflag.IntValue;
  }
}

public Action Command_Setflag(int client, int args)
{
  if (hMode.IntValue != 1)
  {
    hMode.SetInt(1);
    hflag.SetInt(1);
    PrintToChatAll("\x04★ \x01管理员切换了连跳功能,输入指令 \x05!onrb \x01和 \x05!offrb \x01开启或关闭连跳.");
    return Plugin_Handled;
  }

  if (!hflag.IntValue)
  {
    hflag.SetInt(1);
    PrintToChatAll("\x04★ \x01管理员开启了连跳功能,输入指令 \x05!onrb \x01和 \x05!offrb \x01开启或关闭连跳.");
  }
  else
  {
    hflag.SetInt(0);
    PrintToChatAll("\x04★ \x05管理员关闭了连跳功能.");
  }
  return Plugin_Handled;
}

public Action Command_Autobhop(int client, int args)
{
  if (!hflag.IntValue || hMode.IntValue != 1)
  {
    PrintHintText(client, "管理员未开启连跳功能");
    return Plugin_Handled;
  }

  if (bBunnyhopEnable[client])
  {
    bBunnyhopEnable[client] = 0;
    PrintToChat(client, "\x04★ \x01连跳已关闭,输入指令 \x05!onrb \x01开启连跳.");
    PrintHintText(client, "连跳已关闭");
  }
  else
  {
    bBunnyhopEnable[client] = 1;
    PrintToChat(client, "\x04★ \x01连跳已开启,输入指令 \x05!offrb \x01关闭连跳.");
  }
  return Plugin_Handled;
}

public Action Command_Onbhop(int client, int args)
{
  if (!hflag.IntValue || hMode.IntValue != 1)
  {
    PrintHintText(client, "管理员未开启连跳功能");
    return Plugin_Handled;
  }

  bBunnyhopEnable[client] = 1;
  PrintToChat(client, "\x04★ \x01连跳已开启,输入指令 \x05!offrb \x01关闭连跳.");
  // PrintHintText(client, "连跳已开启,速度上限 %d", hLimit);
  return Plugin_Handled;
}

public Action Command_Offbhop(int client, int args)
{
  if (!hflag.IntValue || hMode.IntValue != 1)
  {
    PrintHintText(client, "管理员未开启连跳功能");
    return Plugin_Handled;
  }

  bBunnyhopEnable[client] = 0;
  PrintToChat(client, "\x04★ \x01连跳已关闭,输入指令 \x05!onrb \x01开启连跳.");
  // PrintHintText(client, "连跳已关闭");
  return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
  if (!hflag.IntValue || hMode.IntValue != 1 || !bBunnyhopEnable[client] || !IsClientInGame(client) || !IsPlayerAlive(client))
    return Plugin_Continue;

  if (buttons & IN_JUMP)
  {
    if (!(GetEntityFlags(client) & FL_ONGROUND) && !(GetEntityMoveType(client) & MOVETYPE_LADDER))
    {
      if (GetEntProp(client, Prop_Data, "m_nWaterLevel") < 2)
        buttons &= ~IN_JUMP;
    }
  }
  return Plugin_Continue;
}

public void OnGameFrame()
{
  if (!IsServerProcessing() || hMode.IntValue != 2)
    return;

  for (int i = 1; i <= MaxClients; i++)
  {
    if (IsClientInGame(i) && IsPlayerAlive(i) && bCueAllowed[i] && GetEntProp(i, Prop_Data, "m_nWaterLevel") < 1 + iOffset)
    {
      bCueAllowed[i] = false;
      EmitSoundToClient(i, CUESOUND);
    }
  }
}

public void Event_PlayerJumpApex(Event event, const char[] name, bool dontBroadcast)
{
  if (!hMode.IntValue) return;

  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  if (!IsClientInGame(client) || GetClientTeam(client) != 2 || IsFakeClient(client) || !IsPlayerAlive(client))
    return;

  if (hMode.IntValue == 2) bCueAllowed[client] = true;

  if (!hflag.IntValue || !bBunnyhopEnable[client]) return;
  if ((GetClientButtons(client) & IN_MOVELEFT) || (GetClientButtons(client) & IN_MOVERIGHT))
  {
    if (GetClientButtons(client) & IN_MOVELEFT)
    {
      if (iDirectionCache[client] > -1)
      {
        iDirectionCache[client] = -1;
        return;
      }
      else
        iDirectionCache[client] = -1;
    }
    else if (GetClientButtons(client) & IN_MOVERIGHT)
    {
      if (iDirectionCache[client] < 1)
      {
        iDirectionCache[client] = 1;
        return;
      }
      else
        iDirectionCache[client] = 1;
    }

    float fAngles[3];
    float fLateralVector[3];
    float fForwardVector[3];
    float fNewVel[3];

    GetEntPropVector(client, Prop_Send, "m_angRotation", fAngles);
    GetAngleVectors(fAngles, NULL_VECTOR, fLateralVector, NULL_VECTOR);
    NormalizeVector(fLateralVector, fLateralVector);

    if (GetClientButtons(client) & IN_MOVELEFT) NegateVector(fLateralVector);

    GetEntPropVector(client, Prop_Data, "m_vecVelocity", fForwardVector);
    if (RoundToNearest(GetVectorLength(fForwardVector)) > hLimit.IntValue)
      return;
    else
      ScaleVector(fLateralVector, GetVectorLength(fLateralVector) * hMultiplier.IntValue);

    GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fNewVel);
    for (int i = 0; i < 3; i++)
      fNewVel[i] += fLateralVector[i];

    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fNewVel);
  }
}
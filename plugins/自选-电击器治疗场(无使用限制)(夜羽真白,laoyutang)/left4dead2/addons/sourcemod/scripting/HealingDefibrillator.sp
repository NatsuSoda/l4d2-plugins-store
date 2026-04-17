#pragma semicolon 1
#pragma newdecls required

// 头文件
#include <sourcemod>
#include <sdktools>
#include <colors>

#define GLOWSPRITE     "materials/sprites/laserbeam.vmt"
#define HALOSPRITE     "materials/sprites/glow01.vmt"
#define SPRITE_GLOW    "sprites/blueglow1.vmt"
#define SOUNDEFFECT    "level/gnomeftw.wav"
#define SOUNDHIT       "ambient/energy/zap1.wav"
#define SOUNDCOUNTDOWN "ui/beep07.wav"
#define PARTICLEARC    "electrical_arc_01_system"
#define PARTICLEFIRE   "st_elmos_fire"

// ConVars
ConVar hCvar_FieldRange, hCvar_FieldSpeed, hCvar_FieldWidth, hCvar_Delay, hCvar_Shake, hCvar_ShakeDuration, hCvar_Health, hCvar_TempHealth, hCvar_ColorRed, hCvar_ColorBlue, hCvar_ColorGreen, hCvar_MessageType;
// Ints
int    iFieldDelay, iHealth, iTempHealth, iRed, iBlue, iGreen, iMessageType, GlowSprite,
  HaloSprite, iCountDown;
// Floats
float  fFieldRange, fFieldSpeed, fFieldWidth, fFieldShake, fFieldShakeDuration;
// Handles
Handle Timer_Check;
// Bools
bool   g_bTimer = false;

public Plugin myinfo =
{
  name        = "Defibrillator Healing Field (电击器治疗场)",
  author      = "夜羽真白, laoyutang",
  description = "电击器治疗场，按住E键，会触发治疗范围，范围内的多个对象皆可受到治疗",
  version     = "2.1.0",
  url         = "https://steamcommunity.com/id/saku_ra/"


}

public APLRes
  AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
  EngineVersion Engine = GetEngineVersion();
  if (Engine != Engine_Left4Dead2)
  {
    strcopy(error, err_max, "此插件仅适用于L4D2");
    return APLRes_SilentFailure;
  }
  return APLRes_Success;
}

public void OnPluginStart()
{
  // CreateConVar
  hCvar_FieldRange    = CreateConVar("l4d2_defibfield_range", "300.0", "治疗场的最大范围：50-500", FCVAR_NOTIFY, true, 50.0, true, 500.0);
  hCvar_FieldSpeed    = CreateConVar("l4d2_defibfield_speed", "0.5", "治疗场光圈的扩散速度，数值越小越快：0.1-10.0", FCVAR_NOTIFY, true, 0.1, true, 10.0);
  hCvar_FieldWidth    = CreateConVar("l4d2_defibfield_width", "100.0", "治疗场的光圈宽度，数值越大光圈宽度越大", FCVAR_NOTIFY, true, 1.0);
  hCvar_Delay         = CreateConVar("l4d2_defibfield_delay", "3", "需要等待多少秒才能触发治疗场", FCVAR_NOTIFY, true, 0.0, true, 60.0);
  hCvar_Shake         = CreateConVar("l4d2_defibfield_shake", "5.0", "治疗场触发时触发者与接受者屏幕抖动效果的强度，数值越大越强", FCVAR_NOTIFY, true, 0.0);
  hCvar_ShakeDuration = CreateConVar("l4d2_defibfield_shaketime", "2.0", "治疗场触发时触发者与接受者屏幕抖动的时间，数值越大越长", FCVAR_NOTIFY, true, 0.0);
  hCvar_Health        = CreateConVar("l4d2_defibfield_health", "40", "治疗场能为范围内生还者回复的实血", FCVAR_NOTIFY, true, 0.0);
  hCvar_TempHealth    = CreateConVar("l4d2_defibfield_temphealth", "0", "治疗场能为范围内生还者回复的虚血", FCVAR_NOTIFY, true, 0.0);
  hCvar_ColorRed      = CreateConVar("l4d2_defibfield_red", "0", "治疗场范围的红色颜色值（不会设置请查询RGB颜色表）", FCVAR_NOTIFY, true, 0.0, true, 255.0);
  hCvar_ColorGreen    = CreateConVar("l4d2_defibfield_green", "255", "治疗场范围的绿色颜色值（不会设置请查询RGB颜色表）", FCVAR_NOTIFY, true, 0.0, true, 255.0);
  hCvar_ColorBlue     = CreateConVar("l4d2_defibfield_blue", "0", "治疗场范围的蓝色颜色值（不会设置请查询RGB颜色表）", FCVAR_NOTIFY, true, 0.0, true, 255.0);
  hCvar_MessageType   = CreateConVar("l4d2_defibfield_message", "2", "是否开启治疗场消息提示，0=不提示，1=打印到聊天框，2=中间提示", FCVAR_NOTIFY, true, 0.0, true, 2.0);
  // AddConVarChangeHook

  AutoExecConfig(true, "HealingDefibrillator");

  hCvar_FieldRange.AddChangeHook(ConVarChanged_Cvars);
  hCvar_FieldSpeed.AddChangeHook(ConVarChanged_Cvars);
  hCvar_FieldWidth.AddChangeHook(ConVarChanged_Cvars);
  hCvar_Delay.AddChangeHook(ConVarChanged_Cvars);
  hCvar_Shake.AddChangeHook(ConVarChanged_Cvars);
  hCvar_ShakeDuration.AddChangeHook(ConVarChanged_Cvars);
  hCvar_Health.AddChangeHook(ConVarChanged_Cvars);
  hCvar_TempHealth.AddChangeHook(ConVarChanged_Cvars);
  hCvar_ColorRed.AddChangeHook(ConVarChanged_Cvars);
  hCvar_ColorGreen.AddChangeHook(ConVarChanged_Cvars);
  hCvar_ColorBlue.AddChangeHook(ConVarChanged_Cvars);
  hCvar_MessageType.AddChangeHook(ConVarChanged_Cvars);
  // GetDefaultCvarValue
  GetCvars();
}

public void OnMapStart()
{
  // 预加载模型与声音
  GlowSprite = PrecacheModel(GLOWSPRITE);
  HaloSprite = PrecacheModel(HALOSPRITE);
  PrecacheModel(SPRITE_GLOW, true);
  PrecacheSound(SOUNDEFFECT, true);
  PrecacheSound(SOUNDHIT, true);
  PrecacheSound(SOUNDCOUNTDOWN, true);
  PrecacheParticle(PARTICLEARC);
  PrecacheParticle(PARTICLEFIRE);
}

// ----------
// Main Events
// ----------
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon)
{
  if (!IsFakeClient(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client))
  {
    char sWeapon[64];
    GetClientWeapon(client, sWeapon, sizeof(sWeapon));
    if (strcmp(sWeapon, "weapon_defibrillator") == 0)
    {
      if (buttons & IN_USE)
      {
        if (!g_bTimer)
        {
          iCountDown  = iFieldDelay;
          Timer_Check = CreateTimer(1.0, Timer_Message, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
          g_bTimer    = true;
        }
      }
      else
      {
        g_bTimer = false;
        if (Timer_Check != INVALID_HANDLE)
        {
          KillTimer(Timer_Check);
          Timer_Check = INVALID_HANDLE;
        }
      }
    }
  }
  return Plugin_Continue;
}

public void GetMedic(int m_client)
{
  static float vPos[3], healerAngle[3], healerPos[3], receiverPos[3];
  GetEntPropVector(m_client, Prop_Data, "m_vecAbsOrigin", vPos);
  GetEntPropVector(m_client, Prop_Send, "m_angRotation", healerAngle);
  GetEntPropVector(m_client, Prop_Send, "m_vecOrigin", healerPos);
  healerPos[2] += 20.0;
  // 创建触发者的屏幕抖动效果
  CreateShake(fFieldShake, fFieldRange, vPos);
  // 创建实体圆环
  int iRGBA[4];
  iRGBA[0] = iRed;
  iRGBA[1] = iGreen;
  iRGBA[2] = iBlue;
  iRGBA[3] = 255;
  CreateBeamRing(m_client, iRGBA, 0.1, fFieldRange * 2);
  // 治疗效果
  int   iPostHealth;
  float fTempHealth, vEnd[3];
  for (int client = 1; client <= MaxClients; client++)
  {
    if (IsClientInGame(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client))
    {
      // 获取玩家当前位置向量，判断玩家位置与场中心位置距离是否小于限制距离
      GetClientAbsOrigin(client, vEnd);
      if (GetVectorDistance(vPos, vEnd) <= fFieldRange)
      {
        GetClientEyePosition(client, receiverPos);
        receiverPos[2] -= 15.0;
        // 创建闪电与接受者的屏幕抖动效果
        CreateElectric(m_client, client, healerPos, receiverPos);
        CreateShake(fFieldShake, fFieldRange, vEnd);
        // 计算生命值
        iPostHealth = GetClientHealth(client);
        if (iPostHealth < 100)
        {
          // 回复实血
          iPostHealth += iHealth;
          if (iPostHealth > 100)
          {
            iPostHealth = 100;
          }
          // 回复虚血
          fTempHealth = GetTempHealth(client) + iTempHealth;
          if (iPostHealth + fTempHealth > 100)
          {
            fTempHealth = 100.0 - iPostHealth;
            SetTempHealth(client, fTempHealth);
          }
          SetEntityHealth(client, iPostHealth);
          SetTempHealth(client, fTempHealth);
        }
        // 治疗场触发提示，发送给范围内的所有对象
        switch (iMessageType)
        {
          case 1:
          {
            CPrintToChat(client, "{LG}<DefibHealing>：治疗场已触发");
          }
          case 2:
          {
            PrintHintText(client, "治疗场已触发");
          }
        }
        EmitSoundToClient(client, SOUNDEFFECT);
      }
    }
  }
}

// ----------
// Function
// ----------
void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
  GetCvars();
}

void GetCvars()
{
  fFieldRange         = hCvar_FieldRange.FloatValue;
  fFieldSpeed         = hCvar_FieldSpeed.FloatValue;
  fFieldWidth         = hCvar_FieldWidth.FloatValue;
  fFieldShake         = hCvar_Shake.FloatValue;
  fFieldShakeDuration = hCvar_ShakeDuration.FloatValue;
  iFieldDelay         = hCvar_Delay.IntValue;
  iHealth             = hCvar_Health.IntValue;
  iTempHealth         = hCvar_TempHealth.IntValue;
  iRed                = hCvar_ColorRed.IntValue;
  iGreen              = hCvar_ColorGreen.IntValue;
  iBlue               = hCvar_ColorBlue.IntValue;
  iMessageType        = hCvar_MessageType.IntValue;
}

float GetTempHealth(int client)
{
  float temp = GetEntPropFloat(client, Prop_Send, "m_healthBuffer") - ((GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * GetConVarFloat(FindConVar("pain_pills_decay_rate")));
  return temp > 0 ? temp : 0.0;
}

void SetTempHealth(int client, float fTempHealth)
{
  SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
  SetEntPropFloat(client, Prop_Send, "m_healthBuffer", fTempHealth);
}

// 创建实体圆环
void CreateBeamRing(int client, int color[4], float vMin, float vMax)
{
  static float vPos[3];
  GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", vPos);
  // TE_SetupBeamRingPoint(const Float:center[3], Float:Start_Radius, Float:End_Radius, ModelIndex, HaloIndex, StartFrame, FrameRate, Float:Life, Float:Width, Float:Amplitude, const Color[4], Speed, Flags)
  TE_SetupBeamRingPoint(vPos, vMin, vMax, GlowSprite, HaloSprite, 0, 10, fFieldSpeed, fFieldWidth, 0.0, color, 50, 0);
  TE_SendToAll();
}

public Action Timer_Message(Handle timer, int client)
{
  if (iCountDown >= 1)
  {
    switch (iMessageType)
    {
      case 1:
      {
        CPrintToChat(client, "{LG}<DefibHealing>：即将在：{O}%d秒 {LG}后触发治疗场，请等待", iCountDown);
        EmitSoundToClient(client, SOUNDCOUNTDOWN);
      }
      case 2:
      {
        PrintHintText(client, "即将在：%d 秒后触发治疗场，请等待", iCountDown);
        EmitSoundToClient(client, SOUNDCOUNTDOWN);
      }
    }
    iCountDown -= 1;
  }
  else
  {
    GetMedic(client);
    // 由于执行到这里，时钟必然存在，所以不需要判断
    g_bTimer = false;
    KillTimer(Timer_Check);
    Timer_Check = INVALID_HANDLE;
    // 清除玩家所持电击器
    RemovePlayerItem(client, GetPlayerWeaponSlot(client, 3));
  }
  return Plugin_Continue;
}

void CreateShake(float intensity, float range, float vPos[3])
{
  if (intensity == 0)
  {
    return;
  }
  int entity = CreateEntityByName("env_shake");
  if (entity == -1)
  {
    LogError("无法创建效果'env_shake'");
    return;
  }
  static char sTemp[8];
  FloatToString(intensity, sTemp, sizeof(sTemp));
  DispatchKeyValue(entity, "amplitude", sTemp);
  DispatchKeyValue(entity, "frequency", "1.5");
  DispatchKeyValueFloat(entity, "duration", fFieldShakeDuration);
  FloatToString(range, sTemp, sizeof sTemp);
  DispatchKeyValue(entity, "radius", sTemp);
  DispatchKeyValue(entity, "spawnflags", "8");
  DispatchSpawn(entity);
  ActivateEntity(entity);
  AcceptEntityInput(entity, "Enable");
  TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
  AcceptEntityInput(entity, "StartShake");
  RemoveEdict(entity);
}

void CreateElectric(int healer, int receiver, float startpos[3], float endpos[3])
{
  char healername[10], cpoint1[10], receivername[10];
  // 创建闪电并为其赋予目标
  int  ent = CreateEntityByName("info_particle_target");
  DispatchSpawn(ent);
  Format(healername, sizeof(healername), "target%d", healer);
  Format(receivername, sizeof(receivername), "target%d", receiver);
  Format(cpoint1, sizeof(cpoint1), "target%d", ent);
  DispatchKeyValue(healer, "targetname", healername);
  DispatchKeyValue(receiver, "targetname", receivername);
  DispatchKeyValue(ent, "targetname", cpoint1);
  TeleportEntity(ent, endpos, NULL_VECTOR, NULL_VECTOR);
  SetVariantString(receivername);
  AcceptEntityInput(ent, "SetParent", ent, ent, 0);
  // 创建粒子特效
  int particle = CreateEntityByName("info_particle_system");
  DispatchKeyValue(particle, "effect_name", PARTICLEFIRE);
  DispatchKeyValue(particle, "cpoint1", cpoint1);
  DispatchKeyValue(particle, "parentname", healername);
  DispatchSpawn(particle);
  ActivateEntity(particle);
  SetVariantString(healername);
  AcceptEntityInput(particle, "SetParent", particle, particle, 0);
  SetVariantString("leye");
  AcceptEntityInput(particle, "SetParentAttachment");
  float vector[3];
  SetVector(vector, 0.0, 0.0, 0.0);
  TeleportEntity(particle, vector, NULL_VECTOR, NULL_VECTOR);
  AcceptEntityInput(particle, "start");
  CreateTimer(1.0, DeleteParticles, particle);
  CreateTimer(0.5, DeleteParticletargets, ent);
  // 为范围内对象播放电击音效
  EmitSoundToClient(healer, SOUNDHIT, 0, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, endpos, NULL_VECTOR, true, 0.0);
  EmitSoundToClient(receiver, SOUNDHIT, 0, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, startpos, NULL_VECTOR, true, 0.0);
}

void SetVector(float target[3], float x, float y, float z)
{
  target[0] = x;
  target[1] = y;
  target[2] = z;
}

public Action DeleteParticles(Handle timer, int particle)
{
  if (IsValidEntity(particle))
  {
    char sClassName[64];
    GetEdictClassname(particle, sClassName, sizeof(sClassName));
    if (StrEqual(sClassName, "info_particle_system", false))
    {
      AcceptEntityInput(particle, "stop");
      AcceptEntityInput(particle, "kill");
      RemoveEdict(particle);
    }
  }
  return Plugin_Continue;
}

public Action DeleteParticletargets(Handle timer, int target)
{
  if (IsValidEntity(target))
  {
    char sClassName[64];
    GetEdictClassname(target, sClassName, sizeof(sClassName));
    if (StrEqual(sClassName, "info_particle_target", false))
    {
      AcceptEntityInput(target, "stop");
      AcceptEntityInput(target, "kill");
      RemoveEdict(target);
    }
  }
  return Plugin_Continue;
}

void PrecacheParticle(char[] particlename)
{
  char particle = CreateEntityByName("info_particle_system");
  if (IsValidEntity(particle))
  {
    DispatchKeyValue(particle, "effect_name", particlename);
    DispatchSpawn(particle);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "start");
    CreateTimer(0.01, DeleteParticles, particle, TIMER_FLAG_NO_MAPCHANGE);
  }
}
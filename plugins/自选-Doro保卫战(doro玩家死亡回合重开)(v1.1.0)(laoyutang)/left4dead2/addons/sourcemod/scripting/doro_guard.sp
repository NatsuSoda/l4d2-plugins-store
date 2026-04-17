/**
 * =============================================================================
 *  Doro 保卫战 - Left 4 Dead 2 SourceMod 插件
 * =============================================================================
 *
 *  功能说明：
 *    实现 Doro 保卫战玩法，选出一名玩家担任 Doro，
 *    Doro 死亡则回合重启，Doro 全程高亮发光，倒地时醒目提示。
 *
 *  主要特性：
 *    - 玩家使用 !doro 报名，首个报名者触发10秒报名窗口
 *    - 管理员可随时使用 !setdoro 直接指定 Doro
 *    - Doro 死亡时回合重启（不影响战役进度）
 *    - Doro 倒地时全服醒目警告
 *    - Doro 全程金色轮廓发光，其他玩家可远距离看到
 *    - Doro 闲置时，闲置人机继承 Doro 身份和发光
 *    - Doro 离开游戏，身份取消，恢复正常游戏
 *    - Doro 身份在章节内保留，跨战役自动重置
 *
 * =============================================================================
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.1.0"
#define PLUGIN_TAG     "\x04[Doro]\x01"
#define SIGNUP_TIME    10   // 报名窗口持续时间（秒）
#define RESTART_DELAY  3.0  // Doro 死亡后延迟重启时间（秒）
#define GLOW_COLOR_R   255  // 发光颜色 - 红色分量
#define GLOW_COLOR_G   215  // 发光颜色 - 绿色分量
#define GLOW_COLOR_B   0    // 发光颜色 - 蓝色分量
#define REAPPLY_DELAY  1.0  // 回合开始后延迟重新应用发光的时间（秒）
#define RETRY_INTERVAL 5.0  // 跨章节查找 Doro 的重试间隔（秒）
#define RETRY_MAX      3    // 跨章节查找 Doro 的最大重试次数
public Plugin myinfo =
{
  name        = "Doro 保卫战",
  author      = "laoyutang",
  description = "Doro保卫战玩法：选出Doro，Doro死亡则回合重开",
  version     = PLUGIN_VERSION,
  url         = ""
};

/* ========================================================================
 *  全局变量
 * ======================================================================== */

int       g_iDoroClient;       // 当前 Doro 的 client index，0 表示无 Doro
char      g_sDoroSteamId[64];  // Doro 的 SteamID，用于跨关卡和闲置追踪
bool      g_bSignupActive;     // 报名窗口是否正在进行
Handle    g_hSignupTimer;      // 报名倒计时定时器句柄
ArrayList g_aSignupList;       // 报名玩家的 UserID 列表
bool      g_bRoundRestarting;  // 是否正在执行回合重启（防止重复触发）
bool      g_bMapTransition;    // 是否为章节内过图（map_transition 事件设置）
bool      g_bIsRoundRestart;   // 是否为回合重启触发的地图重载
int       g_iRetryCount;       // 跨章节查找 Doro 的当前重试次数

/* ========================================================================
 *  引擎检查
 * ======================================================================== */

/**
 * 插件加载前的引擎兼容性检查
 * 确保插件仅在 Left 4 Dead 2 引擎上运行
 *
 * @param myself    插件句柄
 * @param late      是否为延迟加载
 * @param error     错误信息缓冲区
 * @param err_max   错误信息最大长度
 * @return          APLRes_Success 允许加载，APLRes_SilentFailure 静默拒绝
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
  if (GetEngineVersion() != Engine_Left4Dead2)
  {
    strcopy(error, err_max, "本插件仅支持 Left 4 Dead 2");
    return APLRes_SilentFailure;
  }
  return APLRes_Success;
}

/* ========================================================================
 *  插件初始化
 * ======================================================================== */

/**
 * 插件启动时的初始化入口
 * 注册聊天指令、管理员指令、游戏事件钩子，并初始化全局变量
 */
public void OnPluginStart()
{
  // 注册玩家报名指令
  RegConsoleCmd("sm_doro", Command_Doro, "报名成为Doro");

  // 注册管理员设置指令
  RegAdminCmd("sm_setdoro", Command_SetDoro, ADMFLAG_GENERIC, "管理员直接设置Doro玩家");

  // 钩住游戏事件
  HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
  HookEvent("map_transition", Event_MapTransition, EventHookMode_PostNoCopy);
  HookEvent("player_death", Event_PlayerDeath);
  HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
  HookEvent("player_bot_replace", Event_PlayerBotReplace);
  HookEvent("bot_player_replace", Event_BotPlayerReplace);

  // 初始化全局变量
  g_iDoroClient      = 0;
  g_sDoroSteamId[0]  = '\0';
  g_bSignupActive    = false;
  g_hSignupTimer     = null;
  g_aSignupList      = new ArrayList();
  g_bRoundRestarting = false;
  g_bMapTransition   = false;
  g_bIsRoundRestart  = false;
  g_iRetryCount      = 0;
}

/* ========================================================================
 *  地图生命周期
 * ======================================================================== */

/**
 * 地图开始时的回调
 * 判断是章节内过图、回合重启还是新战役：
 *   - 章节内过图（g_bMapTransition=true）：保留 Doro，延迟多次重试查找玩家
 *   - 回合重启（g_bIsRoundRestart=true）：保留 Doro，快速重新应用发光
 *   - 新战役（两个标记都为false）：重置 Doro 状态
 */
public void OnMapStart()
{
  bool keepDoro      = g_bMapTransition || g_bIsRoundRestart;

  // 重置标记
  g_bMapTransition   = false;
  g_bIsRoundRestart  = false;
  g_bRoundRestarting = false;
  g_iRetryCount      = 0;

  if (!keepDoro && HasActiveDoro())
  {
    // 新战役开始，重置 Doro 状态
    ClearDoro(false);
  }
  else if (keepDoro && g_sDoroSteamId[0] != '\0')
  {
    // 章节内过图或回合重启，延迟查找 Doro 玩家
    CreateTimer(REAPPLY_DELAY + 2.0, Timer_ReapplyDoroOnMap);
  }
}

/**
 * 章节内过图事件回调（生还者进入安全屋触发）
 * 设置标记以区分章节内切换和新战役
 *
 * @param event   事件句柄
 * @param name    事件名称
 * @param dontBroadcast  是否不广播
 */
public void Event_MapTransition(Event event, const char[] name, bool dontBroadcast)
{
  g_bMapTransition = true;
}

/**
 * 地图结束时的清理回调
 * 清理报名状态和定时器，重置 client index（跨关卡后会变化）
 * 注意：不重置 g_bMapTransition 和 g_bIsRoundRestart，它们需要在 OnMapStart 中使用
 */
public void OnMapEnd()
{
  // 清理报名状态
  ResetSignup();

  // 重置 client index（跨关卡后会变化），SteamID 保留到 OnMapStart 判断
  g_iDoroClient      = 0;
  g_bRoundRestarting = false;
}

/* ========================================================================
 *  报名系统 (!doro 指令)
 * ======================================================================== */

/**
 * 玩家使用 !doro 指令的回调
 * 处理逻辑：
 *   1. 已有 Doro 时指令失效，提示玩家
 *   2. 报名窗口未开启时，首个使用者触发报名窗口
 *   3. 报名窗口已开启时，将玩家添加到报名名单
 *
 * @param client  使用指令的玩家 client index
 * @param args    指令参数（未使用）
 * @return        Plugin_Handled 阻止指令传播
 */
public Action Command_Doro(int client, int args)
{
  // 无效玩家检查
  if (client <= 0 || !IsClientInGame(client))
    return Plugin_Handled;

  // 已有 Doro 时指令失效
  if (HasActiveDoro())
  {
    PrintToChat(client, "%s 当前已有Doro在场，指令无效。管理员可使用 \x04!setdoro\x01 更换。", PLUGIN_TAG);
    return Plugin_Handled;
  }

  // 必须是生还者才能报名
  if (!IsValidSurvivor(client))
  {
    PrintToChat(client, "%s 只有生还者才能报名成为Doro！", PLUGIN_TAG);
    return Plugin_Handled;
  }

  // 如果报名窗口已开启，直接添加到名单
  if (g_bSignupActive)
  {
    AddToSignup(client);
    return Plugin_Handled;
  }

  // 首个报名者，开启报名窗口
  StartSignup(client);
  return Plugin_Handled;
}

/**
 * 开启 Doro 报名窗口
 * 将首个报名者加入名单，全服通知报名开启，启动10秒倒计时
 *
 * @param firstClient  首个发起报名的玩家 client index
 */
void StartSignup(int firstClient)
{
  g_bSignupActive = true;
  g_aSignupList.Clear();

  // 将首个报名者加入名单
  g_aSignupList.Push(GetClientUserId(firstClient));

  // 全服通知
  char sName[MAX_NAME_LENGTH];
  GetClientName(firstClient, sName, sizeof(sName));

  PrintToChatAll("%s \x04Doro报名已开启！\x01", PLUGIN_TAG);
  PrintToChatAll("%s \x05%s\x01 已报名！其他玩家有 \x04%d秒\x01 输入 \x04!doro\x01 报名", PLUGIN_TAG, sName, SIGNUP_TIME);

  // 启动倒计时定时器
  g_hSignupTimer = CreateTimer(float(SIGNUP_TIME), Timer_SignupEnd);
}

/**
 * 将玩家添加到报名名单
 * 检查是否重复报名，通知全服
 *
 * @param client  要添加的玩家 client index
 */
void AddToSignup(int client)
{
  int userId = GetClientUserId(client);

  // 检查是否已经报名
  if (g_aSignupList.FindValue(userId) != -1)
  {
    PrintToChat(client, "%s 你已经报名了，请等待报名结束。", PLUGIN_TAG);
    return;
  }

  g_aSignupList.Push(userId);

  char sName[MAX_NAME_LENGTH];
  GetClientName(client, sName, sizeof(sName));
  PrintToChatAll("%s \x05%s\x01 已加入Doro报名！当前 \x04%d\x01 人报名", PLUGIN_TAG, sName, g_aSignupList.Length);
}

/**
 * 报名倒计时结束回调
 * 从有效报名者中随机选出一名 Doro
 *
 * @param timer  定时器句柄
 * @return       Plugin_Stop 停止定时器
 */
public Action Timer_SignupEnd(Handle timer)
{
  g_hSignupTimer         = null;
  g_bSignupActive        = false;

  // 过滤无效玩家（已离开的）
  ArrayList validClients = new ArrayList();
  for (int i = 0; i < g_aSignupList.Length; i++)
  {
    int userId = g_aSignupList.Get(i);
    int client = GetClientOfUserId(userId);
    if (client > 0 && IsClientInGame(client) && IsValidSurvivor(client))
    {
      validClients.Push(client);
    }
  }

  // 无有效报名者
  if (validClients.Length == 0)
  {
    PrintToChatAll("%s 报名结束，但没有有效的报名者。", PLUGIN_TAG);
    delete validClients;
    return Plugin_Stop;
  }

  // 随机选出一名 Doro
  int randomIndex  = GetRandomInt(0, validClients.Length - 1);
  int chosenClient = validClients.Get(randomIndex);

  delete validClients;

  SetDoro(chosenClient);
  return Plugin_Stop;
}

/**
 * 重置报名状态
 * 清除报名列表、停止定时器、关闭报名窗口
 */
void ResetSignup()
{
  g_bSignupActive = false;

  if (g_hSignupTimer != null)
  {
    delete g_hSignupTimer;
    g_hSignupTimer = null;
  }

  if (g_aSignupList != null)
  {
    g_aSignupList.Clear();
  }
}

/* ========================================================================
 *  管理员设置系统 (!setdoro 指令)
 * ======================================================================== */

/**
 * 管理员使用 !setdoro 指令的回调
 * 弹出在线生还者玩家选择菜单，允许管理员直接指定 Doro
 *
 * @param client  使用指令的管理员 client index
 * @param args    指令参数（未使用）
 * @return        Plugin_Handled 阻止指令传播
 */
public Action Command_SetDoro(int client, int args)
{
  if (client <= 0 || !IsClientInGame(client))
    return Plugin_Handled;

  // 构建生还者选择菜单
  Menu menu = new Menu(MenuHandler_SetDoro);
  menu.SetTitle("选择Doro玩家：");

  char sUserId[16], sDisplay[64];
  int  count = 0;

  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsClientInGame(i) || IsFakeClient(i))
      continue;

    if (GetClientTeam(i) != 2)
      continue;

    char sName[MAX_NAME_LENGTH];
    GetClientName(i, sName, sizeof(sName));

    // 标记当前 Doro
    if (i == g_iDoroClient)
      Format(sDisplay, sizeof(sDisplay), "%s [当前Doro]", sName);
    else
      Format(sDisplay, sizeof(sDisplay), "%s", sName);

    IntToString(GetClientUserId(i), sUserId, sizeof(sUserId));
    menu.AddItem(sUserId, sDisplay);
    count++;
  }

  // 也检查观察者中的玩家（可能是闲置的生还者）
  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsClientInGame(i) || IsFakeClient(i))
      continue;

    if (GetClientTeam(i) != 1)  // 观察者队伍
      continue;

    // 检查是否是闲置的生还者（有对应的 bot）
    if (!IsIdleSurvivor(i))
      continue;

    char sName[MAX_NAME_LENGTH];
    GetClientName(i, sName, sizeof(sName));
    Format(sDisplay, sizeof(sDisplay), "%s [闲置]", sName);

    IntToString(GetClientUserId(i), sUserId, sizeof(sUserId));
    menu.AddItem(sUserId, sDisplay);
    count++;
  }

  if (count == 0)
  {
    PrintToChat(client, "%s 当前没有可选择的生还者玩家。", PLUGIN_TAG);
    delete menu;
    return Plugin_Handled;
  }

  menu.Display(client, 20);
  return Plugin_Handled;
}

/**
 * 管理员设置 Doro 菜单的选择回调
 * 处理菜单选项选择，将选中的玩家设为 Doro
 *
 * @param menu    菜单句柄
 * @param action  菜单动作类型
 * @param param1  选择者 client index
 * @param param2  选择的菜单项索引
 * @return        0
 */
public int MenuHandler_SetDoro(Menu menu, MenuAction action, int param1, int param2)
{
  if (action == MenuAction_Select)
  {
    char sUserId[16];
    menu.GetItem(param2, sUserId, sizeof(sUserId));

    int userId = StringToInt(sUserId);
    int target = GetClientOfUserId(userId);

    if (target <= 0 || !IsClientInGame(target))
    {
      PrintToChat(param1, "%s 该玩家已离开游戏。", PLUGIN_TAG);
      return 0;
    }

    // 记录报名状态，SetDoro 内部会清理报名
    bool wasSignupActive = g_bSignupActive;

    // 统一调用 SetDoro，内部会自动处理闲置玩家的 bot 发光
    SetDoro(target);

    if (wasSignupActive)
    {
      PrintToChatAll("%s 管理员已直接设置Doro，报名已取消。", PLUGIN_TAG);
    }
  }
  else if (action == MenuAction_End)
  {
    delete menu;
  }

  return 0;
}

/* ========================================================================
 *  Doro 状态管理
 * ======================================================================== */

/**
 * 设置指定玩家为 Doro
 * 清除旧的 Doro 状态，记录新 Doro 的 SteamID 和 client index，
 * 应用发光效果并全服通知
 *
 * @param client  要设为 Doro 的玩家 client index
 */
void SetDoro(int client)
{
  // 清除旧 Doro 可能残留的发光效果（遍历所有生还者，只移除 Doro 专属颜色的发光）
  ClearAllDoroGlow();

  // 清除可能正在进行的报名
  ResetSignup();

  // 记录新 Doro 的信息
  g_iDoroClient = client;
  GetClientAuthId(client, AuthId_Steam2, g_sDoroSteamId, sizeof(g_sDoroSteamId));

  // 应用发光效果到实际控制的实体上
  int doroEntity = GetDoroEntity();
  if (doroEntity > 0 && IsClientInGame(doroEntity))
  {
    ApplyDoroGlow(doroEntity);
  }

  // 全服通知
  char sName[MAX_NAME_LENGTH];
  GetClientName(client, sName, sizeof(sName));

  PrintToChatAll(" ");
  PrintToChatAll("%s ★★★ \x05%s\x01 成为了 \x04Doro\x01！★★★", PLUGIN_TAG, sName);
  PrintToChatAll("%s Doro倒地将发出警告，Doro死亡则回合重开！", PLUGIN_TAG);
  PrintToChatAll(" ");
}

/**
 * 清除当前 Doro 状态
 * 移除发光效果，重置所有 Doro 相关全局变量，并根据需要全服通知
 *
 * @param notify  是否发送全服通知
 * @param reason  通知中显示的原因文本
 */
void ClearDoro(bool notify = true, const char[] reason = "")
{
  // 移除所有可能存在的 Doro 发光
  ClearAllDoroGlow();

  // 重置全局变量
  g_iDoroClient     = 0;
  g_sDoroSteamId[0] = '\0';

  if (notify && reason[0] != '\0')
  {
    PrintToChatAll("%s %s", PLUGIN_TAG, reason);
    PrintToChatAll("%s 游戏恢复正常模式。", PLUGIN_TAG);
  }
}

/**
 * 检查当前是否有活跃的 Doro
 * 通过 SteamID 是否非空来判断，因为 Doro 身份跨关卡保留
 *
 * @return  true 表示有 Doro，false 表示没有
 */
bool HasActiveDoro()
{
  return g_sDoroSteamId[0] != '\0';
}

/**
 * 获取 Doro 当前实际控制的游戏实体（client index）
 * 如果 Doro 玩家在线且为生还者，返回其 client index
 * 如果 Doro 闲置，返回其闲置 bot 的 client index
 *
 * @return  Doro 实体的 client index，0 表示未找到
 */
int GetDoroEntity()
{
  // 首先检查 Doro 玩家自身
  if (g_iDoroClient > 0 && IsClientInGame(g_iDoroClient))
  {
    if (GetClientTeam(g_iDoroClient) == 2 && IsPlayerAlive(g_iDoroClient))
      return g_iDoroClient;

    // Doro 可能闲置了（在观察者队伍），查找其 bot
    if (GetClientTeam(g_iDoroClient) == 1)
    {
      int bot = GetBotOfIdlePlayer(g_iDoroClient);
      if (bot > 0)
        return bot;
    }
  }

  // 通过 SteamID 遍历查找（处理跨关卡后 client index 变化的情况）
  if (g_sDoroSteamId[0] != '\0')
  {
    for (int i = 1; i <= MaxClients; i++)
    {
      if (!IsClientInGame(i))
        continue;

      if (IsFakeClient(i))
      {
        // 检查 bot 背后是否有 Doro 闲置
        int humanClient = GetIdlePlayerOfBot(i);
        if (humanClient > 0)
        {
          char sSteamId[64];
          GetClientAuthId(humanClient, AuthId_Steam2, sSteamId, sizeof(sSteamId));
          if (StrEqual(sSteamId, g_sDoroSteamId))
            return i;  // 返回 bot
        }
        continue;
      }

      char sSteamId[64];
      GetClientAuthId(i, AuthId_Steam2, sSteamId, sizeof(sSteamId));
      if (StrEqual(sSteamId, g_sDoroSteamId))
      {
        if (GetClientTeam(i) == 2 && IsPlayerAlive(i))
          return i;

        // 闲置
        if (GetClientTeam(i) == 1)
        {
          int bot = GetBotOfIdlePlayer(i);
          if (bot > 0)
            return bot;
        }
      }
    }
  }

  return 0;
}

/**
 * 通过 SteamID 查找 Doro 玩家的 client index（人类玩家）
 * 用于在跨关卡或重连后重新定位 Doro 玩家
 *
 * @return  Doro 玩家的 client index，0 表示未找到
 */
int FindDoroClientBySteamId()
{
  if (g_sDoroSteamId[0] == '\0')
    return 0;

  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsClientInGame(i) || IsFakeClient(i))
      continue;

    char sSteamId[64];
    GetClientAuthId(i, AuthId_Steam2, sSteamId, sizeof(sSteamId));
    if (StrEqual(sSteamId, g_sDoroSteamId))
      return i;
  }

  return 0;
}

/* ========================================================================
 *  视觉高亮（发光效果）
 * ======================================================================== */

/**
 * 为指定实体应用 Doro 金色轮廓发光效果
 * 使用 L4D2 内置的实体发光系统，设置常亮轮廓、无限距离、金色
 *
 * @param entity  要应用发光效果的 client index
 */
void ApplyDoroGlow(int entity)
{
  if (entity <= 0 || entity > MaxClients || !IsClientInGame(entity))
    return;

  // 设置发光类型为常亮轮廓（类型3）
  SetEntProp(entity, Prop_Send, "m_iGlowType", 3);

  // 设置发光可视距离为无限（0 = 无限远）
  SetEntProp(entity, Prop_Send, "m_nGlowRange", 0);

  // 设置发光颜色为金色（RGB 打包为整数）
  int color = PackColor(GLOW_COLOR_R, GLOW_COLOR_G, GLOW_COLOR_B);
  SetEntProp(entity, Prop_Send, "m_glowColorOverride", color);
}

/**
 * 移除指定实体的发光效果
 * 将所有发光属性重置为默认值
 *
 * @param entity  要移除发光效果的 client index
 */
void RemoveDoroGlow(int entity)
{
  if (entity <= 0 || entity > MaxClients || !IsClientInGame(entity))
    return;

  SetEntProp(entity, Prop_Send, "m_iGlowType", 0);
  SetEntProp(entity, Prop_Send, "m_nGlowRange", 0);
  SetEntProp(entity, Prop_Send, "m_glowColorOverride", 0);
}

/**
 * 清除所有可能存在的 Doro 发光效果
 * 遍历所有生还者（包括 bot），移除发光
 * 用于 Doro 变更或清除时确保没有残留发光
 */
void ClearAllDoroGlow()
{
  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsClientInGame(i))
      continue;

    if (GetClientTeam(i) != 2)
      continue;

    // 检查是否有发光，有则移除
    if (GetEntProp(i, Prop_Send, "m_iGlowType") == 3)
    {
      int currentColor = GetEntProp(i, Prop_Send, "m_glowColorOverride");
      int doroColor    = PackColor(GLOW_COLOR_R, GLOW_COLOR_G, GLOW_COLOR_B);
      if (currentColor == doroColor)
      {
        RemoveDoroGlow(i);
      }
    }
  }
}

/**
 * 将 RGB 颜色值打包为 SourceEngine 发光颜色整数
 * 格式：r | (g << 8) | (b << 16)
 *
 * @param r  红色分量 (0-255)
 * @param g  绿色分量 (0-255)
 * @param b  蓝色分量 (0-255)
 * @return   打包后的颜色整数值
 */
int PackColor(int r, int g, int b)
{
  return r | (g << 8) | (b << 16);
}

/* ========================================================================
 *  核心事件处理
 * ======================================================================== */

/**
 * 回合开始事件回调
 * 重置回合状态标志，如果有保留的 Doro，延迟查找并重新应用发光效果
 * 如果没有 Doro，延迟提示玩家可以使用 !doro 报名
 *
 * @param event   事件句柄
 * @param name    事件名称
 * @param dontBroadcast  是否不广播
 */
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
  g_bRoundRestarting = false;

  // 有保留的 Doro 身份，延迟重新应用
  if (g_sDoroSteamId[0] != '\0')
  {
    CreateTimer(REAPPLY_DELAY, Timer_ReapplyDoro);
  }
  else
  {
    // 没有 Doro，延迟提示玩家可以报名（等待玩家完全加载）
    CreateTimer(REAPPLY_DELAY + 3.0, Timer_HintNoDoro);
  }
}

/**
 * 延迟提示无 Doro 的定时器回调
 * 在回合开始后，如果仍然没有 Doro 且没有报名进行中，提示玩家可以报名
 *
 * @param timer  定时器句柄
 * @return       Plugin_Stop 停止定时器
 */
public Action Timer_HintNoDoro(Handle timer)
{
  // 如果已经有 Doro 或者正在报名中，不再提示
  if (HasActiveDoro() || g_bSignupActive)
    return Plugin_Stop;

  PrintToChatAll("%s Doro保卫战，输入 \x04!doro\x01 报名成为Doro！", PLUGIN_TAG);

  return Plugin_Stop;
}

/**
 * 延迟重新应用 Doro 状态的定时器回调
 * 在回合开始后等待玩家完全加载后，查找并恢复 Doro 的发光效果
 *
 * @param timer  定时器句柄
 * @return       Plugin_Stop 停止定时器
 */
public Action Timer_ReapplyDoro(Handle timer)
{
  if (g_sDoroSteamId[0] == '\0')
    return Plugin_Stop;

  // 查找 Doro 玩家
  int doroClient = FindDoroClientBySteamId();
  if (doroClient > 0)
  {
    g_iDoroClient  = doroClient;

    // 应用发光到实际控制的实体
    int doroEntity = GetDoroEntity();
    if (doroEntity > 0)
    {
      ApplyDoroGlow(doroEntity);
    }
  }

  return Plugin_Stop;
}

/**
 * 地图切换后延迟重新应用 Doro 状态的定时器回调
 * 支持多次重试（RETRY_INTERVAL 间隔 × RETRY_MAX 次），
 * 应对玩家网络较慢连接延迟的情况
 * 如果所有重试都未找到 Doro，清除状态并允许重新报名
 *
 * @param timer  定时器句柄
 * @return       Plugin_Stop 停止定时器
 */
public Action Timer_ReapplyDoroOnMap(Handle timer)
{
  if (g_sDoroSteamId[0] == '\0')
    return Plugin_Stop;

  int doroClient = FindDoroClientBySteamId();
  if (doroClient > 0)
  {
    // 找到了 Doro 玩家
    g_iDoroClient  = doroClient;

    int doroEntity = GetDoroEntity();
    if (doroEntity > 0)
    {
      ApplyDoroGlow(doroEntity);
    }

    char sName[MAX_NAME_LENGTH];
    GetClientName(doroClient, sName, sizeof(sName));
    PrintToChatAll("%s \x05%s\x01 继续担任 \x04Doro\x01", PLUGIN_TAG, sName);

    g_iRetryCount = 0;
    return Plugin_Stop;
  }

  // 未找到，进行重试
  g_iRetryCount++;
  if (g_iRetryCount < RETRY_MAX)
  {
    PrintToChatAll("%s 正在等待Doro玩家连接... (%d/%d)", PLUGIN_TAG, g_iRetryCount, RETRY_MAX);
    CreateTimer(RETRY_INTERVAL, Timer_ReapplyDoroOnMap);
  }
  else
  {
    // 重试次数耗尽，清除 Doro 并允许重新报名
    g_iRetryCount = 0;
    ClearDoro(true, "Doro玩家未能在新章节中重新连接。");
    PrintToChatAll("%s 玩家可使用 \x04!doro\x01 重新报名。", PLUGIN_TAG);
  }

  return Plugin_Stop;
}

/**
 * 玩家死亡事件回调
 * 判断死者是否为 Doro，如果是则全服通知并延迟重启回合
 *
 * @param event   事件句柄
 * @param name    事件名称
 * @param dontBroadcast  是否不广播
 */
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
  // 如果正在重启，忽略
  if (g_bRoundRestarting)
    return;

  // 没有 Doro 时忽略
  if (!HasActiveDoro())
    return;

  int userId = event.GetInt("userid");
  int client = GetClientOfUserId(userId);

  if (client <= 0 || !IsClientInGame(client))
    return;

  // 检查死者是否为 Doro
  if (!IsClientDoro(client))
    return;

  // 确认是生还者死亡（不是特感）
  if (GetClientTeam(client) != 2)
    return;

  // Doro 死亡！全服醒目提示
  char sName[MAX_NAME_LENGTH];
  GetClientName(client, sName, sizeof(sName));

  g_bRoundRestarting = true;

  PrintToChatAll(" ");
  PrintToChatAll("\x04========================================");
  PrintToChatAll("%s \x03★ Doro %s 已阵亡！★\x01", PLUGIN_TAG, sName);
  PrintToChatAll("%s \x03回合将在 %.0f 秒后重新开始...\x01", PLUGIN_TAG, RESTART_DELAY);
  PrintToChatAll("\x04========================================");
  PrintToChatAll(" ");

  // 延迟重启回合
  CreateTimer(RESTART_DELAY, Timer_RestartRound);
}

/**
 * left4dhooks 倒地后回调（Forward）
 * 当 Doro 倒地时，发送全服醒目的聊天警告
 *
 * @param client     倒地的玩家 client index
 * @param inflictor  造成倒地的实体
 * @param attacker   攻击者 client index
 * @param damage     伤害值
 * @param damagetype 伤害类型
 */
public void L4D_OnIncapacitated_Post(int client, int inflictor, int attacker, float damage, int damagetype)
{
  if (!HasActiveDoro())
    return;

  if (!IsClientDoro(client))
    return;

  char sName[MAX_NAME_LENGTH];
  GetClientName(client, sName, sizeof(sName));

  // 醒目的倒地警告 - 聊天框多行强调
  PrintToChatAll(" ");
  PrintToChatAll("\x04========================================");
  PrintToChatAll("%s \x03!!! 警告 !!! Doro \x05%s\x03 已经倒地！\x01", PLUGIN_TAG, sName);
  PrintToChatAll("%s \x04快去救援Doro！否则回合将重新开始！\x01", PLUGIN_TAG);
  PrintToChatAll("\x04========================================");
  PrintToChatAll(" ");

  // 屏幕中央醒目提示（所有玩家可见）
  PrintHintTextToAll("!!! 警告 !!! %s 已经倒地！\n快去救援！", sName);
}

/**
 * 玩家断开连接事件回调（Pre模式，在实际断开前触发）
 * 判断离开的玩家是否为 Doro，如果是则清除 Doro 状态并通知全服
 *
 * @param event   事件句柄
 * @param name    事件名称
 * @param dontBroadcast  是否不广播
 */
public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
  if (!HasActiveDoro())
    return;

  int userId = event.GetInt("userid");
  int client = GetClientOfUserId(userId);

  if (client <= 0 || !IsClientInGame(client))
    return;

  // 只检查真人玩家
  if (IsFakeClient(client))
    return;

  // 检查是否为 Doro
  char sSteamId[64];
  GetClientAuthId(client, AuthId_Steam2, sSteamId, sizeof(sSteamId));

  if (!StrEqual(sSteamId, g_sDoroSteamId))
    return;

  // Doro 离开了游戏
  char sName[MAX_NAME_LENGTH];
  GetClientName(client, sName, sizeof(sName));

  // 先移除 bot 上可能的发光
  ClearAllDoroGlow();

  ClearDoro(true, "Doro玩家已离开游戏，Doro身份已取消。");
}

/**
 * 玩家闲置事件回调（人类被 bot 替换）
 * 当 Doro 闲置时，将发光效果从人类转移到接替的 bot 上
 *
 * @param event   事件句柄
 * @param name    事件名称
 * @param dontBroadcast  是否不广播
 */
public void Event_PlayerBotReplace(Event event, const char[] name, bool dontBroadcast)
{
  if (!HasActiveDoro())
    return;

  int playerUserId = event.GetInt("player");
  int botUserId    = event.GetInt("bot");

  int player       = GetClientOfUserId(playerUserId);
  int bot          = GetClientOfUserId(botUserId);

  if (player <= 0 || bot <= 0)
    return;

  // 检查闲置的是否为 Doro
  if (!IsClientDoro(player))
    return;

  // 将发光从人类转移到 bot
  RemoveDoroGlow(player);
  ApplyDoroGlow(bot);

  char sName[MAX_NAME_LENGTH];
  GetClientName(player, sName, sizeof(sName));
  PrintToChatAll("%s \x05%s\x01 (Doro) 已闲置，人机将代替守护。", PLUGIN_TAG, sName);
}

/**
 * 玩家回归事件回调（bot 被人类替换）
 * 当 Doro 从闲置状态回归时，将发光效果从 bot 转移回人类
 *
 * @param event   事件句柄
 * @param name    事件名称
 * @param dontBroadcast  是否不广播
 */
public void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
  if (!HasActiveDoro())
    return;

  int botUserId    = event.GetInt("bot");
  int playerUserId = event.GetInt("player");

  int bot          = GetClientOfUserId(botUserId);
  int player       = GetClientOfUserId(playerUserId);

  if (bot <= 0 || player <= 0)
    return;

  if (!IsClientInGame(player))
    return;

  // 检查回来的是否为 Doro
  char sSteamId[64];
  GetClientAuthId(player, AuthId_Steam2, sSteamId, sizeof(sSteamId));

  if (!StrEqual(sSteamId, g_sDoroSteamId))
    return;

  // 更新 Doro client index
  g_iDoroClient = player;

  // 将发光从 bot 转移到人类
  RemoveDoroGlow(bot);
  ApplyDoroGlow(player);

  char sName[MAX_NAME_LENGTH];
  GetClientName(player, sName, sizeof(sName));
  PrintToChatAll("%s \x05%s\x01 (Doro) 已回归，继续守护！", PLUGIN_TAG, sName);
}

/* ========================================================================
 *  回合重启
 * ======================================================================== */

/**
 * 延迟回合重启的定时器回调
 * 获取当前地图名并调用 L4D_RestartScenarioFromVote 重启当前回合
 * 仅重启回合，不影响整个战役进度
 *
 * @param timer  定时器句柄
 * @return       Plugin_Stop 停止定时器
 */
public Action Timer_RestartRound(Handle timer)
{
  RestartRound();
  return Plugin_Stop;
}

/**
 * 执行回合重启
 * 通过杀死所有生还者触发游戏自然的团灭重启流程，更有代入感
 * 不需要额外设置 g_bIsRoundRestart 标记，因为团灭重启不会触发 OnMapStart
 */
void RestartRound()
{
  PrintToChatAll("%s 回合重新开始！", PLUGIN_TAG);

  // 杀死所有存活的生还者，触发游戏自然的团灭重启
  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsClientInGame(i))
      continue;

    if (GetClientTeam(i) != 2)
      continue;

    if (!IsPlayerAlive(i))
      continue;

    ForcePlayerSuicide(i);
  }
}

/* ========================================================================
 *  辅助函数
 * ======================================================================== */

/**
 * 检查指定 client 是否为当前的 Doro
 * 通过 SteamID 匹配来判断，同时支持直接检查 bot 背后的闲置玩家
 *
 * @param client  要检查的 client index
 * @return        true 表示是 Doro，false 表示不是
 */
bool IsClientDoro(int client)
{
  if (!HasActiveDoro())
    return false;

  if (client <= 0 || !IsClientInGame(client))
    return false;

  // 直接比较 client index
  if (client == g_iDoroClient)
    return true;

  // 真人玩家：比较 SteamID
  if (!IsFakeClient(client))
  {
    char sSteamId[64];
    GetClientAuthId(client, AuthId_Steam2, sSteamId, sizeof(sSteamId));
    return StrEqual(sSteamId, g_sDoroSteamId);
  }

  // Bot：检查背后的闲置玩家是否为 Doro
  int humanClient = GetIdlePlayerOfBot(client);
  if (humanClient > 0)
  {
    char sSteamId[64];
    GetClientAuthId(humanClient, AuthId_Steam2, sSteamId, sizeof(sSteamId));
    return StrEqual(sSteamId, g_sDoroSteamId);
  }

  return false;
}

/**
 * 检查指定 client 是否为有效的生还者玩家
 * 验证 client 有效性、在游戏中、非 bot、生还者队伍
 *
 * @param client  要检查的 client index
 * @return        true 表示是有效的生还者，false 表示不是
 */
bool IsValidSurvivor(int client)
{
  if (client <= 0 || client > MaxClients)
    return false;

  if (!IsClientInGame(client))
    return false;

  if (IsFakeClient(client))
    return false;

  if (GetClientTeam(client) != 2)
    return false;

  return true;
}

/**
 * 检查指定观察者玩家是否为闲置的生还者
 * 通过检查是否有对应的 bot 在控制来判断
 *
 * @param client  要检查的观察者 client index
 * @return        true 表示是闲置的生还者，false 表示不是
 */
bool IsIdleSurvivor(int client)
{
  if (client <= 0 || !IsClientInGame(client))
    return false;

  if (GetClientTeam(client) != 1)
    return false;

  return GetBotOfIdlePlayer(client) > 0;
}

/**
 * 获取闲置玩家对应的 bot
 * 遍历所有生还者 bot，检查 m_humanSpectatorUserID 属性匹配
 *
 * @param client  闲置的人类玩家 client index
 * @return        对应 bot 的 client index，0 表示未找到
 */
int GetBotOfIdlePlayer(int client)
{
  if (client <= 0 || !IsClientInGame(client))
    return 0;

  int userId = GetClientUserId(client);

  for (int i = 1; i <= MaxClients; i++)
  {
    if (!IsClientInGame(i) || !IsFakeClient(i))
      continue;

    if (GetClientTeam(i) != 2)
      continue;

    if (!HasEntProp(i, Prop_Send, "m_humanSpectatorUserID"))
      continue;

    if (GetEntProp(i, Prop_Send, "m_humanSpectatorUserID") == userId)
      return i;
  }

  return 0;
}

/**
 * 获取 bot 背后的闲置人类玩家
 * 通过读取 bot 的 m_humanSpectatorUserID 属性获取对应的人类玩家
 *
 * @param bot  bot 的 client index
 * @return     对应的人类玩家 client index，0 表示没有闲置玩家
 */
int GetIdlePlayerOfBot(int bot)
{
  if (bot <= 0 || !IsClientInGame(bot) || !IsFakeClient(bot))
    return 0;

  if (!HasEntProp(bot, Prop_Send, "m_humanSpectatorUserID"))
    return 0;

  int humanUserId = GetEntProp(bot, Prop_Send, "m_humanSpectatorUserID");
  if (humanUserId <= 0)
    return 0;

  int humanClient = GetClientOfUserId(humanUserId);
  if (humanClient <= 0 || !IsClientInGame(humanClient))
    return 0;

  return humanClient;
}

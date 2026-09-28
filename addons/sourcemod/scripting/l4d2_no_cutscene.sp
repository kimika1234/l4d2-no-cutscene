/*
*	[L4D2] No Cutscene - 删除所有过场动画（含中途运镜）
*	基于 SilverShot 的 "First Map - Skip Intro Cutscenes" (v1.13, GPLv3) 扩展
*
*	功能：
*	1. 跳过开场运镜动画（gameinstructor_nodraw 事件触发的 intro cutscene）
*	2. 压制中途运镜动画（point_viewcontrol / point_viewcontrol_survivor /
*	   point_viewcontrol_multiplayer 激活时立即打断）
*
*	ConVar:
*	l4d2_no_cutscene_allow	0/1	插件总开关（默认 1）
*	l4d2_no_cutscene_mode	1=只跳开场  2=跳开场+杀所有中途运镜（默认 2）
*	l4d2_no_cutscene_intro_time	开场保护窗口秒数（默认 8.0，期间交给 FinishIntro 解锁，之后开始杀运镜实体）
*	l4d2_no_cutscene_kill_ghostanim	0/1 是否同时删除 ghostanim 演出实体（默认 1）
*
*	ghostanim 说明：官方"透明动画替身"模型（models/ghostanim.mdl / models/ghostanim/ghostanim_dlc.mdl），
*	地图用 prop_dynamic 加载并 SetAnimation 播放过场演出（如 c1m1 开场直升机、c2m3 过山车提示）。
*	开启后这些实体会被直接 Kill，配合 viewcontrol 击杀可完全跳过过场。
*/

#define PLUGIN_VERSION		"1.0.0"

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define CVAR_FLAGS			FCVAR_NOTIFY

ConVar g_hCvarAllow, g_hCvarMode, g_hCvarIntroTime, g_hCvarKillGhostanim;
bool g_bCvarAllow, g_bCvarKillGhostanim;
bool g_bInIntro;        // 开场保护窗口内
bool g_bIntroDone;      // 本图开场保护已完成（之后 gameinstructor_nodraw 不再进保护窗口）
bool g_bFaded, g_bOutput1, g_bOutput2;

// ====================================================================================================
//					PLUGIN INFO / START
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D2] No Cutscene - 删除所有过场动画",
	author = "SilverShot (modified by jufu)",
	description = "Skips intro cutscenes and kills mid-map camera sequences (point_viewcontrol*).",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=321993"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if( test != Engine_Left4Dead && test != Engine_Left4Dead2 )
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hCvarAllow = CreateConVar(	"l4d2_no_cutscene_allow",		"1",	"0=Plugin off, 1=Plugin on.", CVAR_FLAGS );
	g_hCvarMode = CreateConVar(		"l4d2_no_cutscene_mode",		"2",	"1=Only skip intro cutscene, 2=Skip intro AND kill mid-map viewcontrols.", CVAR_FLAGS );
	g_hCvarIntroTime = CreateConVar(	"l4d2_no_cutscene_intro_time",	"8.0",	"Seconds after intro starts before killing viewcontrol entities.", CVAR_FLAGS );
	g_hCvarKillGhostanim = CreateConVar(	"l4d2_no_cutscene_kill_ghostanim",	"1",	"0=Keep ghostanim entities, 1=Kill ghostanim (models/ghostanim*.mdl) cutscene actors.", CVAR_FLAGS );
	CreateConVar(					"l4d2_no_cutscene_version",		PLUGIN_VERSION,	"No Cutscene plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig(true,			"l4d2_no_cutscene");

	g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
	g_hCvarKillGhostanim.AddChangeHook(ConVarChanged_Allow);

	// 开场动画开始（官方图 gameinstructor 提示消失时触发）
	HookEvent("gameinstructor_nodraw", Event_NoDraw, EventHookMode_PostNoCopy);
	// 开场结束标志：玩家离开安全室
	HookEvent("player_left_safe_area", Event_LeftSafeArea, EventHookMode_PostNoCopy);

	// 周期性扫描运镜实体
	CreateTimer(0.3, TimerScanViewControls, _, TIMER_REPEAT);
}

public void OnConfigsExecuted()
{
	g_bCvarAllow = g_hCvarAllow.BoolValue;
	g_bCvarKillGhostanim = g_hCvarKillGhostanim.BoolValue;
}

public void OnMapEnd()
{
	g_bInIntro = false;
	g_bIntroDone = false;
}

void ConVarChanged_Allow(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_bCvarAllow = g_hCvarAllow.BoolValue;
	g_bCvarKillGhostanim = g_hCvarKillGhostanim.BoolValue;
}

// ====================================================================================================
//					EVENTS
// ====================================================================================================
void Event_NoDraw(Event event, const char[] name, bool dontBroadcast)
{
	if( !g_bCvarAllow )
		return;

	// 开场保护已完成：中途 gameinstructor_nodraw（路障/事件提示等）不再进保护窗口
	if( g_bIntroDone )
		return;

	// 开场保护窗口开始
	g_bInIntro = true;
	g_bFaded = false;
	g_bOutput1 = false;
	g_bOutput2 = false;

	// 多次触发确保生效
	CreateTimer(1.0, TimerFinishIntro);
	CreateTimer(5.0, TimerFinishIntro);
	CreateTimer(6.0, TimerFinishIntro);
	CreateTimer(6.5, TimerFinishIntro);
	CreateTimer(7.0, TimerFinishIntro);
	CreateTimer(8.0, TimerFinishIntro);

	// 保护窗口兜底：若 intro_time 秒后仍未离开安全室，强制结束保护窗口
	CreateTimer(g_hCvarIntroTime.FloatValue, TimerEndIntro);
}

void Event_LeftSafeArea(Event event, const char[] name, bool dontBroadcast)
{
	// 玩家离开安全室 = 开场流程必然结束
	g_bInIntro = false;
	g_bIntroDone = true;
}

Action TimerEndIntro(Handle timer)
{
	g_bInIntro = false;
	g_bIntroDone = true;
	return Plugin_Continue;
}

// ====================================================================================================
//					开场跳过（沿用 l4d_skip_intro 逻辑）
// ====================================================================================================
Action TimerFinishIntro(Handle timer)
{
	char buffer[128];
	char director[32];
	int entity = FindEntityByClassname(-1, "info_director");
	if( entity != -1 )
	{
		GetEntPropString(entity, Prop_Data, "m_iName", director, sizeof(director));

		for( int i = 0; i < 2; i++ )
		{
			entity = -1;
			while( (entity = FindEntityByClassname(entity, i == 0 ? "point_viewcontrol_survivor" : "point_viewcontrol_multiplayer")) != INVALID_ENT_REFERENCE )
			{
				// ALLOW CONTROL
				if( (i == 0 && !g_bOutput1) || (i == 1 && !g_bOutput2) )
				{
					FormatEx(buffer, sizeof(buffer), "OnUser1 %s:ReleaseSurvivorPositions::0:-1", director);
					SetVariantString(buffer);
					AcceptEntityInput(entity, "AddOutput");

					FormatEx(buffer, sizeof(buffer), "OnUser1 %s:FinishIntro::0:-1", director);
					SetVariantString(buffer);
					AcceptEntityInput(entity, "AddOutput");

					AcceptEntityInput(entity, "FireUser1");

					if( i == 0 )			g_bOutput1 = true;
					else if( i == 1 )		g_bOutput2 = true;
				} else {
					AcceptEntityInput(entity, "FireUser1");
				}

				// STOP SCENE
				SetVariantString("!self");
				AcceptEntityInput(entity, "StartMovement");
			}
		}

		// FADE IN
		if( (g_bOutput1 || g_bOutput2 ) && !g_bFaded )
		{
			g_bFaded = true;

			entity = CreateEntityByName("env_fade");
			DispatchKeyValue(entity, "spawnflags", "1");
			DispatchKeyValue(entity, "rendercolor", "0 0 0");
			DispatchKeyValue(entity, "renderamt", "255");
			DispatchKeyValue(entity, "holdtime", "1");
			DispatchKeyValue(entity, "duration", "1");
			DispatchSpawn(entity);
			AcceptEntityInput(entity, "Fade");

			SetVariantString("OnUser1 !self:Kill::2.5:-1");
			AcceptEntityInput(entity, "AddOutput");
			AcceptEntityInput(entity, "FireUser1");
		}
	}

	return Plugin_Continue;
}

// ====================================================================================================
//					中途运镜杀手
// ====================================================================================================
Action TimerScanViewControls(Handle timer)
{
	if( !g_bCvarAllow )
		return Plugin_Continue;

	if( g_hCvarMode.IntValue < 2 )
		return Plugin_Continue;

	// 开场保护窗口内不动运镜实体（交给 FinishIntro 正常解锁）
	if( g_bInIntro )
		return Plugin_Continue;

	char sClass[][] = { "point_viewcontrol", "point_viewcontrol_survivor", "point_viewcontrol_multiplayer" };
	int entity = -1;

	for( int i = 0; i < sizeof(sClass); i++ )
	{
		entity = -1;
		while( (entity = FindEntityByClassname(entity, sClass[i])) != INVALID_ENT_REFERENCE )
		{
			KillViewControl(entity);
		}
	}

	// ghostanim 演出实体（透明动画替身，可能用 prop_dynamic / prop_dynamic_override 等类）
	if( g_bCvarKillGhostanim )
	{
		char sPropClass[][] = { "prop_dynamic", "prop_dynamic_override", "prop_physics" };
		for( int i = 0; i < sizeof(sPropClass); i++ )
		{
			entity = -1;
			while( (entity = FindEntityByClassname(entity, sPropClass[i])) != INVALID_ENT_REFERENCE )
			{
				if( IsGhostanimEntity(entity) )
					KillGhostanimEntity(entity);
			}
		}
	}

	// 新生成的运镜实体由 OnEntityCreated 兜底
	return Plugin_Continue;
}

bool IsGhostanimEntity(int entity)
{
	if( !HasEntProp(entity, Prop_Data, "m_ModelName") )
		return false;

	char model[128];
	GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));

	// models/ghostanim.mdl 或 models/ghostanim/ghostanim_dlc.mdl 等
	if( StrContains(model, "ghostanim", false) == -1 )
		return false;

	return true;
}

void KillViewControl(int entity)
{
	// 停止运镜、释放玩家、禁用实体
	AcceptEntityInput(entity, "StopMovement");
	AcceptEntityInput(entity, "ReleasePlayer");
	AcceptEntityInput(entity, "Disable");

	KillEntityDeferred(entity);
}

void KillGhostanimEntity(int entity)
{
	// prop_dynamic 无 StopMovement/ReleasePlayer/Disable 输入，直接删除
	KillEntityDeferred(entity);
}

void KillEntityDeferred(int entity)
{
	// 引擎级删除（等价 ent_remove，实测 viewcontrol 不吃实体 "Kill" 输入、
	// 但 RemoveEntity 有效；原版 l4d_skip_intro 注释 "Kill works good" 指的就是 RemoveEntity）
	RemoveEntity(entity);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if( !g_bCvarAllow )
		return;

	if( g_hCvarMode.IntValue < 2 )
		return;

	if( g_bInIntro )
		return;

	// 中途动态生成的运镜实体立即压制
	if( strcmp(classname, "point_viewcontrol") == 0 ||
		strcmp(classname, "point_viewcontrol_survivor") == 0 ||
		strcmp(classname, "point_viewcontrol_multiplayer") == 0 )
	{
		RequestFrame(FrameKillViewControl, EntIndexToEntRef(entity));
	}

	// 中途动态生成的 ghostanim 演出实体（模型可能尚未加载，延迟一帧再判）
	if( g_bCvarKillGhostanim &&
		(strcmp(classname, "prop_dynamic") == 0 ||
		 strcmp(classname, "prop_dynamic_override") == 0 ||
		 strcmp(classname, "prop_physics") == 0) )
	{
		RequestFrame(FrameKillGhostanim, EntIndexToEntRef(entity));
	}
}

void FrameKillGhostanim(int ref)
{
	int entity = EntRefToEntIndex(ref);
	if( entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity) )
		return;

	if( !IsGhostanimEntity(entity) )
		return;

	KillGhostanimEntity(entity);
}

void FrameKillViewControl(int ref)
{
	int entity = EntRefToEntIndex(ref);
	if( entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity) )
		return;

	// 再确认一次实体类型
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	if( strcmp(classname, "point_viewcontrol") != 0 &&
		strcmp(classname, "point_viewcontrol_survivor") != 0 &&
		strcmp(classname, "point_viewcontrol_multiplayer") != 0 )
		return;

	KillViewControl(entity);
}
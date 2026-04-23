// mapspawn.nut
// 拦截 ZKPSuperTanks 的 HUD 调用，保留其他插件功能

local _HUDSetLayout = ::HUDSetLayout;
local _HUDPlace = ::HUDPlace;

::HUDSetLayout <- function(layout)
{
    // 精准识别：ZKPSuperTanks 的 HUD 布局包含 speaker1 字段
    if (layout != null && typeof(layout) == "table" && "Fields" in layout)
    {
        local fields = layout.Fields;
        if (typeof(fields) == "table" && "speaker1" in fields)
        {
            return; // 直接丢弃，不执行任何 HUD 设置
        }
    }
    _HUDSetLayout(layout);
}

::HUDPlace <- function(slot, x, y, width, height)
{
    // 获取 HUD_LEFT_TOP 常量值（如果引擎已初始化）
    local leftTop = 0;
    if ("g_ModeScript" in getroottable() && "HUD_LEFT_TOP" in g_ModeScript)
    {
        leftTop = g_ModeScript.HUD_LEFT_TOP;
    }
    else if ("DirectorScript" in getroottable() && "HUD_LEFT_TOP" in DirectorScript)
    {
        leftTop = DirectorScript.HUD_LEFT_TOP;
    }
    
    // 拦截 ZKPSuperTanks 的固定参数组合 (0, 0, 0.6, 0.1)
    // 这个尺寸特征高度特异，误伤概率极低
    if (slot == leftTop && x == 0.0 && y == 0.0 && width == 0.6 && height == 0.1)
    {
        return; // 不放置，插槽留给其他插件
    }
    _HUDPlace(slot, x, y, width, height);
}
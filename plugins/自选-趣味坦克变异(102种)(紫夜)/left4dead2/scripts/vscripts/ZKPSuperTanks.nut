function ShowTankHUD()
{

ModeHUD <-
{
    Fields = 
    {
        speaker = 
        {
            slot = g_ModeScript.HUD_LEFT_TOP,
            dataval = "",
            flags = g_ModeScript.HUD_FLAG_ALIGN_LEFT | g_ModeScript.HUD_FLAG_NOBG,
            name = "speaker" 
        }
    }
}

HUDSetLayout( ModeHUD )
HUDPlace( g_ModeScript.HUD_LEFT_TOP, 0, 0, 0.6, 0.1)
}

Pictures for Visual note backgrounds.

1. Make one from a screenshot or a downloaded map (PNG/JPG):
   right-click Tools\img2tga.ps1 > Run with PowerShell, or
   powershell -ExecutionPolicy Bypass -File Tools\img2tga.ps1 -Src C:\path\map.png -Name wailing_caverns
   It writes Images\wailing_caverns.tga (1024x512) and adds it to the picture menu.
2. RESTART WoW (a /reload does not find new files).
3. Visual note > Picture > pick it in the menu.

Copied a .tga or .blp in here yourself? Run Tools\update-images.ps1 so it shows in the menu.

Everyone who should see the picture needs the same file in their Images folder
(share it on Discord). The visual note itself only sends the name.

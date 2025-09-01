# wow-healer-ui

## how to install

only manual installation, nowhere published yet

copy this folder `wow-healer-ui` into your local wow folder `World of Warcraft\_retail_\Interface\AddOns\wow-healer-ui`, e.g. `D:\Blizzard\World of Warcraft\_retail_\Interface\AddOns/wow-healer-ui`

```powershell
$ADDON_DIR = 'D:\Blizzard\World of Warcraft\_retail_\Interface\AddOns\wow-healer-ui';
Remove-Item -LiteralPath $ADDON_DIR -Recurse -Force -ErrorAction SilentlyContinue;
New-Item -ItemType Directory -Path $ADDON_DIR -Force | Out-Null;
Copy-Item -Path .\* -Destination $ADDON_DIR -Recurse -Force
```

## how to see errors

```
/console scriptErrors 1
/reload
```

## which version is the current wow client?

```
/dump GetBuildInfo()
```

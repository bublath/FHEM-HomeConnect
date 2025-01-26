# FHEM-HomeConnect
FHEM Module to integrate your Home Connect household appliances

Enter this command in your FHEM command line to install the Home Connect plugin:

update all https://raw.githubusercontent.com/bublath/FHEM-HomeConnect/master/controls_homeconnect.txt

The 48_HomeConnect.pm modules has been completely rewritten compared to the original repository this was forked from.
## Upgrade from the previous version:
Edit the file FHEM/controls.txt and replace "sw-home" by "bublath".
If you rely on reading names and values, you may want to set the attributes "namePrefix" and "valuePrefix" to "1" to retain backwards compatibility, though I strongly recommend to go with the new naming scheme as it is much more readable and compact (and better tested)

Then check the device descriptions in your FHEM Commandref.

Key changes/improvements:

## 48_HomeConnectConnection.pm:
- make current accessScope visible as reading
- configurable timeout
- fetch German names if global language=DE
- improved documentation

## HomeConnectConf.pm
- New file, moving static definitions out of the main module

## 48_HomeConnect:
- Complete rewrite based on the version from Prof. Dr. Peter Henning
- Shorten Reading and Value names (can be switched off for backwards compatibility) typically removing the first two bullets (e.g. BSH.Common) or the complete path for values (e.g. LaundryCare.Dryer.EnumType.DryingTarget.CupboardDry -> CupboardDry)
- Option to translate readings and program names to German
- Support more commands like PauseProgram, ResumeProgram, OpenDoor, PartlyOpenDoor
- Ability to Power On/Off devices if supported via API
- Ability to start a program with delay or change an already defined delay
- Ability to start favorite on dishwasher
- Defined defaults (programs etc.) for all currently known appliance types
- Ability to change all program options supported by the API before starting a program (e.g LaundryCare.Dryer.Option.DryingTarget )
- Ability to change runtime program options if supported by the device (e.g. Dishcare.Dishwasher.Option.SilenceOnDemand )
- Continuous status updates during running programs reflected in various readings (e.g. Progress, Remaining Time, Elapsed Time, Temperatures ...) if supported by the API
- Translations into German if global language=DE
- Set/Unset Childlock
- Support for a special logfile to record communication/events between FHEM and the API to troubleshoot/improve the module
- Automatic detection of settings/options that don't work and dynamic entry into an exclude list
- Improved startup and handling of offline devices

## Limitations:
We still need to use the Home Connect Developer API which has severe restrictions compared to the Home Connect App, e.g.
- On some appliances not all programs can be selected/started (e.g. downloaded programs, certain appliances) , on the tested washdryer so far no programs work at all
- Not all options/settings from the APP are available in FHEM
- Regular updates during runtime are limited (e.g. ProcessPhase) or even wrong (e.g. Temperature for some ovens)
- The API is not very consistent and the developers for each device seems to have a different understanding how to use it. The module tries to avoid model specific workarounds as much as possible, but that could lead to a different behaviour on different devices of the same type which is not foreseeable

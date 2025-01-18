#########################################################################
#
#  HomeConnectConf.pm
#
#  $Id: xx $
#
#  Version 1.0
#
#  Configuration parameters for HomeConnect devices.
#
#########################################################################

package HomeConnectConf;
use strict;
use warnings;

use vars qw(%HomeConnect_Translation);
use vars qw(%HomeConnect_Iconmap);
use vars qw(%HomeConnect_DeviceDefaults);

%HomeConnect_Translation = (
	"DE" => {
  "ok"          => "OK",
  "notok"       => "Nicht OK",
  "at"          => "um",
  "program"     => "Programm",
  "active"      => "aktiv",
  "inactive"    => "inaktiv",
  "offline"     => "Offline",
  "open"        => "offen",
  "closed"      => "geschlossen",
  "locked"      => "verriegelt",
  "still"       => "noch",
  "remaining"   => "verbleiben",
  "whichis"     => "dieses ist zu",
  "endingat"    => "und endet um",
  "remotestart" => "Fernstart",
  "running"     => "Läuft",
  "inactiveC"   => "Ruhezustand",
  "ready"       => "Bereit",
  "delayedstart"  => "Start um",
  "delayend"    => "Ende um",
  "pause"       => "Pause",
  "actionreq"   => "Eingriff nötig",
  "finished"    => "Fertig",
  "error"       => "Fehlerzustand",
  "abort"       => "Abbruch",
  "standby"     => "Standby",
  "childlock"   => "Kindersicherung",
  "door"        => "Tür",
  "alarm"       => "Kurzzeitwecker um",
  "delayed"     => "Verzögert",
  "action"      => "Eingriff nötig",
  "done"        => "Fertig",
  "idle"        => "Bereit",
  "door"        => "Tür",
  "on"			=> "An",
  "off"			=> "Aus",
  "autostart"   => "Autostart",
  "temperature" => "Temperatur",
  "SpinningFinal" => "Endschleudern"
	},
	"EN" => {
  "ok"          => "OK",
  "notok"       => "Not OK",
  "at"          => "at",
  "program"     => "program",
  "active"      => "active",
  "inactive"    => "inactive",
  "offline"     => "offline",
  "open"        => "open",
  "closed"      => "closed",
  "locked"      => "locked",
  "still"       => "still",
  "remaining"   => "remaining",
  "whichis"     => "which is",
  "endingat"    => "and ending at",
  "remotestart" => "remote start",
  "running"     => "running",
  "inactiveC"   => "inactive",
  "ready"       => "ready",
  "delayedstart"  => "Start at",
  "delayend"    => "end at",
  "pause"       => "pause",
  "actionreq"   => "action required",
  "finished"    => "finished",
  "error"       => "error",              #state
  "abort"       => "aborting",           #state
  "standby"     => "standby",
  "childlock"   => "child lock",
  "door"        => "door",
  "alarm"       => "alarm at",
  "delayed"     => "delayed",            #state
  "action"      => "action required",    #state
  "done"        => "done",               #state
  "idle"        => "idle",               #state
  "door"        => "door",
  "on"			=> "on",
  "off"			=> "off",
  "autostart"   => "autostart",
  "temperature" => "temperature",
  "SpinningFinal" => "final spin"
	}
);

%HomeConnect_Iconmap = (
  "Dishwasher"    => "scene_dishwasher",
  "Hob"           => "scene_cooktop",
  "Oven"          => "scene_baking_oven",
  "FridgeFreezer" => "scene_wine_cellar",
  "Washer"        => "scene_washing_machine",
  "Dryer"         => "scene_clothes_dryer",
  "CoffeeMaker"   => "max_heizungsthermostat"
);

#-- Dishwasher
#   known settings ChildLock,PowerState
#   known programs Intensiv70,Auto2,Eco50,Quick45,PreRinse,NightWash,Kurz60,MachineCare
#   program downwloads: LearningDishwasher,QuickD
#   known problems: Option SilenceOnDemand only available when program is running
$HomeConnect_DeviceDefaults{"Dishwasher"} = {
	"settings" => [ "ChildLock:On,Off", "PowerState" ],
	"prefix" => "Dishcare.Dishwasher",
	"poweroff" => "PowerOff",
	"activeoptions" => ["SilenceOnDemand"],
	"events" => [ "SaltNearlyEmpty", "RinseAidNearlyEmpty" ],
	"programs_DE" => {
		"Eco50"              => "Eco50",
		"Auto2"              => "Auto45-65",
		"Quick45"            => "Speed45",
		"Intensiv70"         => "Intensiv70",
		"PreRinse"           => "Vorspülen",
		"Kurz60"             => "Speed60",
		"MachineCare"        => "Maschinenpflege",
		"GlassShine"         => "BrilliantShine",
		"Favorite.001"       => "Favorit",
		"NightWash"          => "Leise",
		"LearningDishwasher" => "LearningDishwasher",
		"QuickD"             => "QuickD"
	}
};

#-- Hob
#   known settings AlarmClock,PowerState,(TemperatureUnit)
#   known programs PowerLevelMode,FryingsensorMode,PowerMoveMode
$HomeConnect_DeviceDefaults{"Hob"} = {
	"settings" => [ "AlarmClock", "PowerState" ],
	"prefix" => "Cooking.Hob",
	"poweroff" => undef,
	"events" => [],
	"programs_DE" => {
	  "PowerLevelMode"   => "Leistung",
	  "FryingSensorMode" => "Sensor",
	  "PowerMoveMode"    => "Bewegung"
	}
};

#-- Hood
#   known settings PowerState, Lighting, LightingBrightness
#   known programs (Cooking.Common.Program.) Hood.Automatic, Hood.Venting, Hood.DelayedShutoff, CleaningModes.ApplianceOnRinsing
#   known problems: program has additional useless prefix Hood
$HomeConnect_DeviceDefaults{"Hood"} = {
	"settings" => [ "PowerState", "Lighting", "LightingBrightness" ],
	"prefix" => "Cooking.Common",
	"poweroff" => undef,
	"events" => ["GreaseFilterMaxSaturationNearlyReached", "GreaseFilterMaxSaturationReached" ],
	"programs_DE" => {
		"Lighting"            => "Beleuchtung",
		"LightingBrightness"  => "Helligkeit",
		"Hood.Venting"        => "Lüften",
		"Hood.Automatic"      => "Automatikbetrieb",
		"Hood.DelayedShutOff" => "Lüfternachlauf",
		"VentingLevel"        => "Lüfterstufe",
		"IntensiveLevel"      => "Intensivstufe"
	}
};

#-- Oven
#   known settings
#   known programs (Cooking.Oven.Program.HeatingMode.) HotAir,HotAirGentle,PizzaSetting,KeepWarm,Defrost,Pyrolysis,PROGRAMMED,SlowCook,GrillLargeArea,HotAirGrilling,TopBottomHeating
#     in PROGRAMS 24 programs, like 01 = (Dish.Automatic.Conv.) FrozenThinCrustPizza, 02 = FrozenDeepPanPizza, 03 = FrozenLasagne, ...
#   known problems: program has additional useless prefixes HeatingMode and Dish.Automatic.Conv (to distinguish from programs?)
$HomeConnect_DeviceDefaults{"Oven"} = {
	"settings" => [ "AlarmClock", "PowerState" ],
	"prefix" => "Cooking.Oven",
	"poweroff" => "PowerStandby",
	"events" => [],
	"programs_DE" => {
	  "HeatingMode.TopBottomHeating" => "Ober/Unterhitze",
	  "HeatingMode.GrillLargeArea"   => "Flächengrill",
	  "HeatingMode.SlowCook"         => "LangsamGaren",
	  "HeatingMode.Defrost"          => "Auftauen",
	  "HeatingMode.KeepWarm"         => "Warmhalten",
	  "HeatingMode.PizzaSetting"     => "Pizza",
	  "HeatingMode.HotAir"           => "Heißluft",
	  "HeatingMode.HotAirGentle"     => "HeißluftSchonend",
	  "HeatingMode.HotAirGrilling"   => "Heißluftgrill",
	  "Cleaning.Pyrolysis"           => "Pyrolyse"
	}
};

#-- Refrigerator
#  known settings SetpointTemperatureRefrigerator,SuperModeRefrigerator,AssistantFridge,AssistantForceFridge
#  no programs !
$HomeConnect_DeviceDefaults{"Refrigerator"} = {
	"settings" => [ "ChildLock:On,Off", "PowerState" ],
	"prefix" => "Refrigeration.FridgeFreezer",
	"powerOff" => undef,
	"events" => ["DoorAlarmRefrigerator"],
	"programs_DE" => {
	  "SetpointTemperatureRefrigerator" => "Temperatur",
	  "SuperModeRefrigerator"           => "SuperMode",
	  "AssistantFridge"                 => "TürAssistent",
	  "AssistantForceFridge"            => "TürKraft"
	}
};

#-- FridgeFreezer
#  known settings
#  no programs !
$HomeConnect_DeviceDefaults{"FridgeFreezer"} = {
	"settings" => [ "ChildLock:On,Off", "PowerState" ],
	"prefix" => "Refrigeration.FridgeFreezer",
	"poweroff" => undef,
	"events" => [ "DoorAlarmFreezer", "DoorAlarmRefrigerator", "TemperatureAlarmFreezer" ],
	"programs_DE" => {}
};

#-- Washer
#  known settings ChildLock, PowerState
#  known programs Cotton.Eco4060,Cotton,EasyCare,Mix,DelicatesSilk,Wool,Super153045.Super1530,SportFitness,Sensitive,ShirtsBlouses,DarkWash,Towels
#  known programs NEW: Mix.NightWash,Towels,DownDuvet.Duvet,DrumClean
#  known problems: program contains "."
#  special types (LaundryCare.Washer.EnumType.) SpinSpeed, Temperature
$HomeConnect_DeviceDefaults{"Washer"} = {
	"settings" => [ "ChildLock:On,Off", "PowerState" ],
	"prefix" => "LaundryCare.Washer",
	"poweroff" => "MainsOff",
	"events" => [ "IDos1FillLevelPoor", "IDos2FillLevelPoor" ],
	"programs_DE" => {
	  "Cotton"                => "Baumwolle",
	  "Cotton.Eco4060"        => "Baumwolle_Eco5060",
	  "Cotton.CottonEco"      => "Baumwolle_Eco",
	  "Super153045.Super1530" => "Super15/30",
	  "EasyCare"              => "Pflegeleicht",
	  "Mix"                   => "Schnell/Mix",
	  "DelicatesSilk"         => "Fein/Seide",
	  "Wool"                  => "Wolle",
	  "SportFitness"          => "Sportsachen",
	  "Outdoor"               => "Outdoor",
	  "Sensitive"             => "Empfindliche_Wäsche",
	  "ShirtsBlouses"          => "Hemden",
	  "DarkWash"              => "Dunkle_Wäsche",
	  "Mix.Nightwash"         => "Nachtwäsche",
	  "Towels"                => "Handtücher",
	  "DownDuvet.Duvet"       => "Bettdecke",
	  "DrumClean"             => "Trommelreinigung",
	  "PowerSpeed59"		  => "powerSpeed59",
	  "SpinDrain"			  => "Schleudern/Abpumpen",
	  "Spin"				  => "Schleudern"
	}
};

#-- Dryer
#   known settings
#   known programs Cotton,Syntetic,Mix,Dessous,TimeCold,TimeWarm,Hygiene,Super40,Towels,Outdoor,Pillow,Blankets,BusinessShirts
# special types: (LaundryCare.Dryer.EnumType.)DryingTarget.CupboardDry,WrinkleGuard.Min60
$HomeConnect_DeviceDefaults{"Dryer"} = {
	"settings" => [ "ChildLock:On,Off", "PowerState" ],
	"prefix" => "LaundryCare.Dryer",
	"poweroff" => "PowerOff",
	"events" => [],
	"finished" => "DryingProcessFinished",
	"programs_DE" => {
	  "Cotton"         => "Baumwolle",
	  "Cotton.CottonEco" => "Baumwolle Eco",
	  "Synthetic"      => "Pflegeleicht",
	  "Mix"            => "Schnell/Mix",
	  "Dessous"        => "Unterwäsche",
	  "Delicates"	   => "ExtraFein",
	  "TimeCold"       => "Kalt",
	  "TimeWarm"       => "Warm",
	  "Hygiene"        => "Hygiene",
	  "Super40"        => "Super40",
	  "Towels"         => "Handtücher",
	  "Outdoor"        => "Outdoor",
	  "Pillow"         => "Kopfkissen",
	  "Blankets"       => "Laken",
	  "Bedlinens"	   => "Bettwäsche",
	  "Hygiene"        => "Hygiene",
	  "TimeWarm"	   => "Warm/Zeit",
	  "ShirtBlouses"   => "Hemden",
	}
};

#-- WasherDryer
#  known settings ChildLock, PowerState
#  known programs Eco4060,Cotton,EasyCare,Mix,DelicatesSilk,Wool,FastWashDry45,SportFitness,Synthetics,Refresh,SpinDrain,Rinse
#  known problems: program contains "."
#  special types (LaundryCare.WasherDryer.EnumType.) SpinSpeed, Temperature
$HomeConnect_DeviceDefaults{"WasherDryer"} = {
	"settings" => [ "ChildLock:On,Off", "PowerState" ],
	"prefix" => "LaundryCare.WasherDryer",
	"poweroff" => "PowerOff",
	"events" => [],
	"programs_DE" => {
	  "Mix.HHMix.HHMix"                           => "Schnell/Mix",
	  "EasyCare.HHSynthetics.HHSynthetics"        => "Pflegeleicht",
	  "DelicatesSilk.DelicatesSilk.DelicatesSilk" => "Fein/Seide",
	  "Sensitive.Sensitive.Sensitiv"              => "HygienePlus",
	  "RefreshWD.Refresh.Refresh"                 => "IronAssist",
	  "FastWashDry.WD45.WD45"                     => "ExtraKurz15/Wash&Dry45",
	  "SportFitness.SportFitness.SportFitness"    => "Sportswear",
	  "Wool.Wool.Wool"                            => "Wolle",
	  "Cotton.Cotton.Cotton"                      => "Baumwolle",
	  "LabelEU19.LabelEU19.Eco4060"               => "Eco40-60",
	  "Rinse.Rinse.Rinse"                         => "Spülen",
	  "Spin.Spin.SpinDrain"                       => "Schleudern/Abpumpen"
	}
};

#CookProcessor
$HomeConnect_DeviceDefaults{"CookProcessor"} = {
	"settings" => [ "BrightnessDisplay", "SoundVolume", "PowerState" ],
	"prefix" => "ConsumerProducts.CookProcessor",
	"poweroff" => "PowerOff",
	"events" => ["StepFinished"],
	"programs_DE" => {
		"BuildingBlock.AutomaticWarmingUpViscousDishes" => "AutomaticWarmingUpViscousDishes",
		"BuildingBlock.Beating" => "Beating",
		"BuildingBlock.Boiling" => "Boiling",
		"BuildingBlock.BraisingBigParts" => "BraisingBigParts",
		"BuildingBlock.Caramelizing" => "Caramelizing",
		"BuildingBlock.ColdPreCleaning" => "ColdPreCleaning",
		"BuildingBlock.CookingSugarSirup" => "CookingSugarSirup",
		"BuildingBlock.DoughProving" => "DoughProving",
		"BuildingBlock.FryingRoastingSearing" => "FryingRoastingSearing",
		"BuildingBlock.HeatingManualMode1" => "HeatingManualMode1",
		"BuildingBlock.HeatingManualMode3" => "HeatingManualMode3",
		"BuildingBlock.KeepWarmHighViscous" => "KeepWarmHighViscous",
		"BuildingBlock.KneadingHeavyDough" => "KneadingHeavyDough",
		"BuildingBlock.LeaveToCulture" => "LeaveToCulture",
		"BuildingBlock.ManualCookingParameter" => "ManualCookingParameter",
		"BuildingBlock.Melting" => "Melting",
		"BuildingBlock.MixingBatter" => "MixingBatter",
		"BuildingBlock.Pureeing" => "Pureeing",
		"BuildingBlock.ServingOrKeepWarmHighViscous" => "ServingOrKeepWarmHighViscous",
		"BuildingBlock.SimmeringFruitSpread" => "SimmeringFruitSpread",
		"BuildingBlock.SimmeringLiquidDishes" => "SimmeringLiquidDishes",
		"BuildingBlock.Soaking" => "Soaking",
		"BuildingBlock.SteamingHigh" => "SteamingHigh",
		"BuildingBlock.SteamingHighReduced" => "SteamingHighReduced",
		"BuildingBlock.SteamingLow" => "SteamingLow",
		"BuildingBlock.SteamingTowerCooking" => "SteamingTowerCooking",
		"BuildingBlock.Stewing" => "Stewing",
		"BuildingBlock.StewingSensibleDishes" => "StewingSensibleDishes",
		"BuildingBlock.Stirring" => "Stirring",
		"BuildingBlock.Sweating" => "Sweating",
		"BuildingBlock.WarmingMilk" => "WarmingMilk",
		"BuildingBlock.WarmingUpLiquidDishes" => "WarmingUpLiquidDishes",
		"BuildingBlock.WaterFastBoiling" => "WaterFastBoiling",
		"BuildingBlock.WeighingVolume" => "WeighingVolume",
		"Manual" => "Manual"
	}
};

#-- CoffeeMaker
#   known settings settings ChildLock,PowerState,CupWarmer
#   known programs (ConsumerProducts.CoffeeMaker.Program.Beverage.) Coffee,... (ConsumerProducts.CoffeeMaker.Program.CoffeeWorld.)KleinerBrauner
#   special types (ConsumerProducts.CoffeeMaker.EnumType.) BeanAmount, FlowRate, BeanContainerSelection
$HomeConnect_DeviceDefaults{"CoffeeMaker"} = {
	"settings" => [ "ChildLock:On,Off", "PowerState", "CupWarmer" ],
	"prefix" => "ConsumerProducts.CoffeeMaker",
	"poweroff" => "PowerStandby",
	"events" => [ "BeanContainerEmpty", "WaterTankEmpty", "DripTrayFull" ],
	"programs_DE" => {
	  "Beverage.Ristretto"             => "Ristretto",
	  "Beverage.EspressoDoppio "       => "Espresso_Doppio",
	  "Beverage.Espresso"              => "Espresso",
	  "Beverage.EspressoMacchiato"     => "Espresso_Macchiato",
	  "Beverage.Coffee"                => "Kaffee",
	  "Beverage.Cappuccino"            => "Cappuccino",
	  "Beverage.LatteMacchiato"        => "Latte_Macchiato",
	  "Beverage.CaffeLatte"            => "Milchkaffee",
	  "Beverage.MilkFroth"             => "Milchschaum",
	  "Beverage.WarmMilk"              => "Warme_Milch",
	  "CoffeeWorld.KleinerBrauner"     => "Kleiner_Brauner",
	  "CoffeeWorld.GrosserBrauner"     => "Großer_Brauner",
	  "CoffeeWorld.Verlaengerter"      => "Verlängerter",
	  "CoffeeWorld.VerlaengerterBraun" => "Verlängerter_Braun",
	  "CoffeeWorld.WienerMelange"      => "Wiener_Melange",
	  "CoffeeWorld.FlatWhite"          => "Flat_White",
	  "CoffeeWorld.Cortado"            => "Cortado",
	  "CoffeeWorld.CafeCortado"        => "Cafe_cortado",
	  "CoffeeWorld.CafeConLeche"       => "Cafe_con_leche",
	  "CoffeeWorld.CafeAuLait"         => "Cafe_au_lait",
	  "CoffeeWorld.Kaapi"              => "Kaapi",
	  "CoffeeWorld.KoffieVerkeerd"     => "Koffie_verkeerd",
	  "CoffeeWorld.Galao"              => "Galao",
	  "CoffeeWorld.Garoto"             => "Garoto",
	  "CoffeeWorld.Americano"          => "Americano",
	  "CoffeeWorld.RedEye"             => "Red_Eye",
	  "CoffeeWorld.BlackEye"           => "Black_Eye",
	  "CoffeeWorld.DeadEye"            => "Dead_Eye",
	  "Favorite.001"                   => "Favorit_1",
	  "Favorite.002"                   => "Favorit_2",
	  "Favorite.003"                   => "Favorit_3",
	  "Favorite.004"                   => "Favorit_4",
	  "Favorite.005"                   => "Favorit_5"
	}
};

#-- Cleaning Robot
$HomeConnect_DeviceDefaults{"CleaningRobot"} = {
	"setting" => ["PowerState"],
	"prefix" => "ConsumerProducts.CleaningRobot",
	"poweroff" => "PowerOff",
	"events" => [ "EmptyDustBoxAndCleanFilter", "RobotIsStuck", "DockingStationNotFound" ],
	"programs_DE" => {}
};

########################################################################################
#
# 48_HomeConnect.pm
#
# Bosch Siemens Home Connect Module for FHEM
#
# Stefan Willmeroth 09/2016
# Major rebuild Prof. Dr. Peter A. Henning 2023
# Major re-rebuild by Adimarantis 2024
# Version 1.1beta vom 23.12.2024
#
# $Id: xx $
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
########################################################################################
#
package main;

use strict;
use warnings;
use JSON;
use Switch;
use Scalar::Util qw(looks_like_number);
use Encode;

use vars qw(%defs);
require 'HttpUtils.pm';

##############################################
my $HCversion = "1.1beta";

my %HC_table = (
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
  "off"			=> "Aus"
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
  "off"			=> "off"
	}
);

my %HomeConnect_Iconmap = (
  "Dishwasher"    => "scene_dishwasher",
  "Hob"           => "scene_cooktop",
  "Oven"          => "scene_baking_oven",
  "FridgeFreezer" => "scene_wine_cellar",
  "Washer"        => "scene_washing_machine",
  "Dryer"         => "scene_clothes_dryer",
  "CoffeeMaker"   => "max_heizungsthermostat"
);

my %HomeConnect_DeviceSettings;
my %HomeConnect_DevicePrefix;
my %HomeConnect_DevicePowerOff;
my %HomeConnect_DeviceEvents;
my %HomeConnect_DeviceTrans_DE;

#-- Dishwasher
#   known settings ChildLock,PowerState
#   known programs Intensiv70,Auto2,Eco50,Quick45,PreRinse,NightWash,Kurz60,MachineCare
#   program downwloads: LearningDishwasher,QuickD
#   known problems: Option SilenceOnDemand only available when program is running
$HomeConnect_DeviceSettings{"Dishwasher"} = [ "ChildLock", "PowerState" ];
$HomeConnect_DevicePrefix{"Dishwasher"}   = "Dishcare.Dishwasher";
$HomeConnect_DevicePowerOff{"Dishwasher"} = "PowerOff";
$HomeConnect_DeviceEvents{"Dishwasher"} = [ "SaltNearlyEmpty", "RinseAidNearlyEmpty" ];
$HomeConnect_DeviceTrans_DE{"Dishwasher"} = {
  "Eco50"              => "Eco 50",
  "Auto2"              => "Auto 45-65",
  "Quick45"            => "Speed 45",
  "Intensiv70"         => "Intensiv 70",
  "PreRinse"           => "Vorspülen",
  "Kurz60"             => "Speed 60",
  "MachineCare"        => "Maschinenpflege",
  "GlassShine"         => "Brilliant Shine",
  "Favorite.001"       => "Favorit",
  "NightWash"          => "Leise",
  "LearningDishwasher" => "LearningDishwasher",
  "QuickD"             => "QuickD"
};

#-- Hob
#   known settings AlarmClock,PowerState,(TemperatureUnit)
#   known programs PowerLevelMode,FryingsensorMode,PowerMoveMode
$HomeConnect_DeviceSettings{"Hob"} = [ "AlarmClock", "PowerState" ];
$HomeConnect_DevicePrefix{"Hob"}   = "Cooking.Hob";
$HomeConnect_DevicePowerOff{"Hob"} = undef;
$HomeConnect_DeviceEvents{"Hob"}   = [];
$HomeConnect_DeviceTrans_DE{"Hob"} = {
  "PowerLevelMode"   => "Leistung",
  "FryingSensorMode" => "Sensor",
  "PowerMoveMode"    => "Bewegung"
};

#-- Hood
#   known settings PowerState, Lighting, LightingBrightness
#   known programs (Cooking.Common.Program.) Hood.Automatic, Hood.Venting, Hood.DelayedShutoff, CleaningModes.ApplianceOnRinsing
#   known problems: program has additional useless prefix Hood
$HomeConnect_DeviceSettings{"Hood"} = [ "PowerState", "Lighting", "LightingBrightness" ];
$HomeConnect_DevicePrefix{"Hood"}   = "Cooking.Common";
$HomeConnect_DevicePowerOff{"Hood"} = undef;
$HomeConnect_DeviceEvents{"Hood"}   = ["GreaseFilterMaxSaturationNearlyReached", "GreaseFilterMaxSaturationReached" ];
$HomeConnect_DeviceTrans_DE{"Hood"} = {
  "Lighting"            => "Beleuchtung",
  "LightingBrightness"  => "Helligkeit",
  "Hood.Venting"        => "Lüften",
  "Hood.Automatic"      => "Automatikbetrieb",
  "Hood.DelayedShutOff" => "Lüfternachlauf",
  "VentingLevel"        => "Lüfterstufe",
  "IntensiveLevel"      => "Intensivstufe"
};

#-- Oven
#   known settings
#   known programs (Cooking.Oven.Program.HeatingMode.) HotAir,HotAirGentle,PizzaSetting,KeepWarm,Defrost,Pyrolysis,PROGRAMMED,SlowCook,GrillLargeArea,HotAirGrilling,TopBottomHeating
#     in PROGRAMS 24 programs, like 01 = (Dish.Automatic.Conv.) FrozenThinCrustPizza, 02 = FrozenDeepPanPizza, 03 = FrozenLasagne, ...
#   known problems: program has additional useless prefixes HeatingMode and Dish.Automatic.Conv (to distinguish from programs?)
$HomeConnect_DeviceSettings{"Oven"} = [ "AlarmClock", "PowerState" ];
$HomeConnect_DevicePrefix{"Oven"}   = "Cooking.Oven";
$HomeConnect_DevicePowerOff{"Oven"} = "PowerStandby";
$HomeConnect_DeviceEvents{"Oven"}   = ();
$HomeConnect_DeviceTrans_DE{"Oven"} = {
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
};

#-- Refrigerator
#  known settings SetpointTemperatureRefrigerator,SuperModeRefrigerator,AssistantFridge,AssistantForceFridge
#  no programs !
$HomeConnect_DeviceSettings{"Refrigerator"} = [ "ChildLock", "PowerState" ];
$HomeConnect_DevicePrefix{"Refrigerator"}   = "Refrigeration.FridgeFreezer";
$HomeConnect_DevicePowerOff{"Refrigerator"} = undef;
$HomeConnect_DeviceEvents{"Refrigerator"}   = ["DoorAlarmRefrigerator"];
$HomeConnect_DeviceTrans_DE{"Refrigerator"} = {
  "SetpointTemperatureRefrigerator" => "Temperatur",
  "SuperModeRefrigerator"           => "SuperMode",
  "AssistantFridge"                 => "TürAssistent",
  "AssistantForceFridge"            => "TürKraft"
};

#-- FridgeFreezer
#  known settings
#  no programs !
$HomeConnect_DeviceSettings{"FridgeFreezer"} = [ "ChildLock", "PowerState" ];
$HomeConnect_DevicePrefix{"FridgeFreezer"}   = "Refrigeration.FridgeFreezer";
$HomeConnect_DevicePowerOff{"FridgeFreezer"} = undef;
$HomeConnect_DeviceEvents{"FridgeFreezer"} = [ "DoorAlarmFreezer", "DoorAlarmRefrigerator", "TemperatureAlarmFreezer" ];
$HomeConnect_DeviceTrans_DE{"FridgeFreezer"} = {};

#-- Washer
#  known settings ChildLock, PowerState
#  known programs Cotton.Eco4060,Cotton,EasyCare,Mix,DelicatesSilk,Wool,Super153045.Super1530,SportFitness,Sensitive,ShirtsBlouses,DarkWash,Towels
#  known programs NEW: Mix.NightWash,Towels,DownDuvet.Duvet,DrumClean
#  known problems: program contains "."
#  special types (LaundryCare.Washer.EnumType.) SpinSpeed, Temperature
$HomeConnect_DeviceSettings{"Washer"} = [ "ChildLock", "PowerState" ];
$HomeConnect_DevicePrefix{"Washer"}   = "LaundryCare.Washer";
$HomeConnect_DevicePowerOff{"Washer"} = "PowerOff";
$HomeConnect_DeviceEvents{"Washer"} = [ "IDos1FillLevelPoor", "IDos2FillLevelPoor" ];
$HomeConnect_DeviceTrans_DE{"Washer"} = {
  "Cotton"                => "Baumwolle",
  "Cotton.Eco4060"        => "Baumwolle.Eco5060",
  "Super153045.Super1530" => "Super",
  "EasyCare"              => "Leichte Pflege",
  "Mix"                   => "Gemischt",
  "DelicateSilk"          => "Feine Seide",
  "Wool"                  => "Wolle",
  "SportFitness"          => "Sportsachen",
  "Sensitive"             => "Empfindliche Wäsche",
  "ShirtsBlouses"         => "Hemden",
  "DarkWash"              => "Dunkle Wäsche",
  "Mix.Nightwash"         => "Nachtwäsche",
  "Towels"                => "Handtücher",
  "DownDuvet.Duvet"       => "Bettdecke",
  "DrumClean"             => "Trommelreinigung"
};

#-- Dryer
#   known settings
#   known programs Cotton,Syntetic,Mix,Dessous,TimeCold,TimeWarm,Hygiene,Super40,Towels,Outdoor,Pillow,Blankets,BusinessShirts
# special types: (LaundryCare.Dryer.EnumType.)DryingTarget.CupboardDry,WrinkleGuard.Min60
$HomeConnect_DeviceSettings{"Dryer"} = [ "ChildLock", "PowerState" ];
$HomeConnect_DevicePrefix{"Dryer"}   = "LaundryCare.Dryer";
$HomeConnect_DevicePowerOff{"Dryer"} = "PowerOff";
$HomeConnect_DeviceEvents{"Dryer"}   = [];
$HomeConnect_DeviceTrans_DE{"Dryer"} = {
  "Cotton"         => "Baumwolle",
  "Synthetic"      => "Synthetik",
  "Mix"            => "Mix",
  "Dessous"        => "Unterwäsche",
  "TimeCold"       => "Kalt",
  "TimeWarm"       => "Warm",
  "Hygiene"        => "Hygiene",
  "Super40"        => "Super40",
  "Towels"         => "Handtücher",
  "Outdoor"        => "Außen",
  "Pillow"         => "Kopfkissen",
  "Blankets"       => "Laken",
  "BusinessShirts" => "Hemden"
};

#-- WasherDryer
#  known settings ChildLock, PowerState
#  known programs Eco4060,Cotton,EasyCare,Mix,DelicatesSilk,Wool,FastWashDry45,SportFitness,Synthetics,Refresh,SpinDrain,Rinse
#  known problems: program contains "."
#  special types (LaundryCare.WasherDryer.EnumType.) SpinSpeed, Temperature
$HomeConnect_DeviceSettings{"WasherDryer"} = [ "ChildLock", "PowerState" ];
$HomeConnect_DevicePrefix{"WasherDryer"}   = "LaundryCare.WasherDryer";
$HomeConnect_DevicePowerOff{"WasherDryer"} = "PowerOff";
$HomeConnect_DeviceEvents{"WasherDryer"}   = [];
$HomeConnect_DeviceTrans_DE{"WasherDryer"} = {
  "Mix.HHMix.HHMix"                           => "Schnell/Mix",
  "EasyCare.HHSynthetics.HHSynthetics"        => "Pflegeleicht",
  "DelicatesSilk.DelicatesSilk.DelicatesSilk" => "Fein/Seide",
  "Sensitive.Sensitive.Sensitiv"              => "Hygiene Plus",
  "RefreshWD.Refresh.Refresh"                 => "Iron Assist",
  "FastWashDry.WD45.WD45"                     => "Extra Kurz 15/Wash & Dry 45",
  "SportFitness.SportFitness.SportFitness"    => "Sportswear",
  "Wool.Wool.Wool"                            => "Wolle",
  "Cotton.Cotton.Cotton"                      => "Baumwolle",
  "LabelEU19.LabelEU19.Eco4060"               => "Eco 40-60",
  "Rinse.Rinse.Rinse"                         => "Spülen",
  "Spin.Spin.SpinDrain"                       => "Schleudern/Abpumpen"
};

#LaundryCare.WasherDryer.Option.ProgramMode
#LaundryCare.WasherDryer.EnumType.ProgramMode.WashingAndDrying
#LaundryCare.Common.Option.ProcessPhase
#LaundryCare.Common.EnumType.ProcessPhase.RinsingSoftener

#-- CoffeeMaker
#   known settings settings ChildLock,PowerState,CupWarmer
#   known programs (ConsumerProducts.CoffeeMaker.Program.Beverage.) Coffee,... (ConsumerProducts.CoffeeMaker.Program.CoffeeWorld.)KleinerBrauner
#   special types (ConsumerProducts.CoffeeMaker.EnumType.) BeanAmount, FlowRate, BeanContainerSelection
$HomeConnect_DeviceSettings{"CoffeeMaker"} = [ "ChildLock", "PowerState", "CupWarmer" ];
$HomeConnect_DevicePrefix{"CoffeeMaker"}   = "ConsumerProducts.CoffeeMaker";
$HomeConnect_DevicePowerOff{"CoffeeMaker"} = "PowerStandby";
$HomeConnect_DeviceEvents{"CoffeeMaker"} = [ "BeanContainerEmpty", "WaterTankEmpty", "DripTrayFull" ];
$HomeConnect_DeviceTrans_DE{"CoffeeMaker"} = {
  "Beverage.Ristretto"             => "Ristretto",
  "Beverage.EspressoDoppio "       => " Espresso doppio",
  "Beverage.Espresso"              => "Espresso",
  "Beverage.EspressoMacchiato"     => "Espresso Macchiato",
  "Beverage.Coffee"                => "Caffè crema",
  "Beverage.Cappuccino"            => "Cappuccino",
  "Beverage.LatteMacchiato"        => "Latte Macchiato",
  "Beverage.CaffeeLatte "          => "Milchkaffee",
  "Beverage.MilkFroth"             => "Milchschaum",
  "Beverage.WarmMilk"              => "Warme Milch",
  "CoffeeWorld.KleinerBrauner"     => "Kleiner Brauner",
  "CoffeeWorld.GrosserBrauner"     => "Großer Brauner",
  "CoffeeWorld.Verlaengerter"      => "Verlängerter",
  "CoffeeWorld.VerlaengerterBraun" => "Verlängerter Braun",
  "CoffeeWorld.WienerMelange"      => "Wiener Melange",
  "CoffeeWorld.FlatWhite"          => "Flat White",
  "CoffeeWorld.Cortado"            => "Cortado",
  "CoffeeWorld.CafeCortado"        => "Café cortado",
  "CoffeeWorld.CafeConLeche"       => "Café con leche",
  "CoffeeWorld.CafeAuLait"         => "Café au lait",
  "CoffeeWorld.Kaapi"              => "Kaapi",
  "CoffeeWorld.KoffieVerkeerd"     => "Koffie verkeerd",
  "CoffeeWorld.Galao"              => "Galão",
  "CoffeeWorld.Garoto"             => "Garoto",
  "CoffeeWorld.Americano"          => "Americano",
  "CoffeeWorld.RedEye"             => "Red Eye",
  "CoffeeWorld.BlackEye"           => "Black Eye",
  "CoffeeWorld.DeadEye"            => "Dead Eye",
  "Favorite.001"                   => "Favorit 1",
  "Favorite.002"                   => "Favorit 2",
  "Favorite.003"                   => "Favorit 3",
  "Favorite.004"                   => "Favorit 4",
  "Favorite.005"                   => "Favorit 5"
};

#Was ich noch komisch finde: In der App und an der Maschine kann ich noch die Programme "Heißwasser" und "Kaffeekanne" auswählen, in Fhem gibts die aber nicht

#-- Cleaning Robot
$HomeConnect_DeviceSettings{"CleaningRobot"} = ["PowerState"];
$HomeConnect_DevicePrefix{"CleaningRobot"}   = "ConsumerProducts.CleaningRobot";
$HomeConnect_DevicePowerOff{"CleaningRobot"} = "PowerOff";
$HomeConnect_DeviceEvents{"CleaningRobot"} =  [ "EmptyDustBoxAndCleanFilter", "RobotIsStuck", "DockingStationNotFound" ];
$HomeConnect_DeviceTrans_DE{"CleaningRobot"} = {};

#-- some global parameters
my $HC_delayed_PS;

###############################################################################
#
#   Initialize
#
###############################################################################

sub HomeConnect_Initialize($) {
  my ($hash) = @_;
  $hash->{SetFn}  = "HomeConnect_Set";
  $hash->{DefFn}  = "HomeConnect_Define";
  $hash->{AttrFn} = "HomeConnect_Attr";
  $hash->{StateFn} = "HomeConnect_State";
  $hash->{NotifyFn} = "HomeConnect_Notify";
  $hash->{GetFn}  = "HomeConnect_Get";
  $hash->{AttrList} =
	  "disable:0,1 "
	. "namePrefix:0,1 "
	. "valuePrefix:0,1 "
	. "updateTimer "
	. "translate: "
	. "logfile: "
	. "excludeSetting: "
	. $readingFnAttributes;
  return;
}

###############################################################################
#
#   Define
#
###############################################################################

sub HomeConnect_Define($$) {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
  Log3 $hash->{NAME}, 1, "[HomeConnect_define] called";
  my $u = "[HomeConnect_Define] wrong syntax: define <dev-name> HomeConnect <conn-name> <haId> to add appliances";

  return $u if ( int(@a) < 4 );

  $hash->{hcconn} = $a[2];
  $hash->{haId}   = $a[3];

  return undef if !defined( $defs{ $hash->{hcconn} } );
  return undef if $defs{ $hash->{hcconn} } ne "Connected";

  #-- Delay init if not yet connected - not working
  #return undef if(Value($hash->{hcconn}) ne "Logged in");

  return HomeConnect_Init($hash);
}

###############################################################################
#
#   Init
#
###############################################################################

sub HomeConnect_Init($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $hash->{NAME}, 1, "[HomeConnect_Init] for $name called";
  $Data::Dumper::Indent = 0;

  $hash->{helper}->{init}="start";
  HomeConnect_CloseEventChannel($hash);
  RemoveInternalTimer($hash);
  InternalTimer( gettimeofday() + int(rand(5))+1, "HomeConnect_InitWatcher", $hash, 0 );
  #Keep a counter to avoid potential endless loop
  $hash->{helper}->{init_count}=0;
  $hash->{helper}->{total_count}=0;
  #-- Read list of appliances, find my haId
  my $data = {
	callback => \&HomeConnect_ResponseInit,
	uri      => "/api/homeappliances"
  };
  HomeConnect_request( $hash, $data );
}

sub HomeConnect_InitWatcher($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $state=$hash->{helper}->{init};
  my $count=$hash->{helper}->{init_count};

  HomeConnect_FileLog($hash, "Init Watch $name stage $state count $hash->{helper}->{init_count}\n");

  # Call the initial asynchronous calls one by one to avoid issues, retry after 3 times
  if ($state eq "start" and $count>3) {
	HomeConnect_Init($hash);
	$count=0;
  } elsif ($state eq "init_done" or ($state eq "settings" and $count>3)) {
	$hash->{helper}->{init}="settings";
	HomeConnect_GetSettings($hash);
	$count=0;
	} elsif ($state eq "settings_done" or ($state eq "programs" and $count>3)) {
	  HomeConnect_GetPrograms($hash);
	  $hash->{helper}->{init}="programs";
	  $count=0;
	} elsif ($state eq "programs_done" or ($state eq "status" and $count>3)) {
	  HomeConnect_UpdateStatus($hash);
	  $hash->{helper}->{init}="status";
	  $count=0;
	}
  $hash->{helper}->{init_count}=++$count;
  $hash->{helper}->{total_count}++;
  # Check updates more frequently
  if ($state ne "status_done" and $hash->{helper}->{total_count}<10) {
    RemoveInternalTimer($hash);
	InternalTimer( gettimeofday() + int(rand(5))+1, "HomeConnect_InitWatcher", $hash, 0 );
  } else {
	#Init finished or took to long
    RemoveInternalTimer($hash);
	HomeConnect_Timer($hash);
  }
}

###############################################################################
#
#   ResponseInit
#
###############################################################################

sub HomeConnect_ResponseInit {
  my ( $hash, $data ) = @_;
  my $JSON = JSON->new->utf8(0)->allow_nonref;
  my $name = $hash->{NAME};
  my $msg;

  if ( !defined $data ) {
	return "[HomeConnect_ResponseInit] $name: failed to connect to HomeConnect API, see log for details";
  }

  Log3 $name, 5, "[HomeConnect_ResponseInit] $name: init response $data";

  my $appliances = eval { $JSON->decode($data) };
  if ($@) {
	$msg = "[HomeConnect_ResponseInit] $name: JSON error requesting appliances: $@";
	Log3 $name, 1, $msg;
	return $msg;
  }
  HomeConnect_FileLog($hash,"ResponseInit:".Dumper($appliances));

  for ( my $i = 0 ; 1 ; $i++ ) {
	my $appliance = $appliances->{data}->{homeappliances}[$i];
	if ( !defined $appliance ) { last }
	if ( $hash->{haId} eq $appliance->{haId} ) {
	  $hash->{aliasname} = $appliance->{name};
	  $hash->{type}      = $appliance->{type};
	  ##Set Prefix as early as possible from defaults to avoid races with updates on startup
	  $hash->{prefix}    = $HomeConnect_DevicePrefix{ $hash->{type} };
	  $hash->{brand}     = $appliance->{brand};
	  $hash->{vib}       = $appliance->{vib};
	  $hash->{connected} = $appliance->{connected};
	  Log3 $name, 1, "[HomeConnect_ResponseInit] $name: defined as HomeConnect $hash->{type} $hash->{brand} $hash->{vib}";

	  my $icon = $HomeConnect_Iconmap{$appliance->{type}};
	  $attr{$name}{icon} = $icon if (!defined $attr{$name}{icon} && !defined $attr{$name}{devStateIcon} && defined $icon);
	  $attr{$name}{stateFormat} = "state1 (state2)" if !defined $attr{$name}{stateFormat};

	  $attr{$name}{alias} = $hash->{aliasname}
		if ( !defined $attr{$name}{alias} && defined $hash->{aliasname} );

	  $hash->{helper}->{init}="init_done";

	  return;
	}
  }
  Log3 $name, 3, "[HomeConnect_ResponseInit] $name: specified appliance with haId $hash->{haId} not found";
}

###############################################################################
#
#   Undef
#
###############################################################################

sub HomeConnect_Undef($$) {
  my ( $hash, $arg ) = @_;

  RemoveInternalTimer($hash);
  HomeConnect_CloseEventChannel($hash);
  Log3 $hash->{NAME}, 3, "$hash->{NAME}: --- removed ---";
  return undef;
}

###############################################################################
#
#   Response
#   General Response, does not expect a return value unless error
#
###############################################################################

sub HomeConnect_Response() {
  my ( $hash, $data, $path ) = @_;
  my $name = $hash->{NAME};
  my $msg;
  if (defined $path) {
	$path =~ /.*\.(.*)$/;
	$path = $1;
  } else {
	$path = "Unknown";
  }
  #-- if data is present, something is wrong
  if ( defined $data && length($data) > 0 ) {

	#-- no rights ===> TODO: MOVE THIS INTO ERROR HANDLING
	if ( index( $data, "insufficient_scope" ) > -1 ) {
	  $msg = "[HomeConnect_Response] $name: insufficient_scope error, command not accepted by API due to missing rights";
	  Log3 $name, 1, $msg;
	  return $msg;
	}

	#Log3 $name, 1, "[HomeConnect_Response] $name: response $data";
	my $JSON  = JSON->new->utf8(0)->allow_nonref;
	my $jhash = eval { $JSON->decode($data) };
	if ($@) {
	  $msg = "[HomeConnect_Response] $name: JSON error: $@";
	  Log3 $name, 1, $msg;
	  return $msg;
	}

    HomeConnect_FileLog($hash,"Response ".$path.":".Dumper($jhash));

	if ( $jhash->{"error"} ) {
		my $desc=$jhash->{"error"}->{"description"};
		print "$desc\n";
		if ($desc) {
			if ($desc =~ /Setting is not supported/) {  
			    #Unfortunately the API returns 'SDK.Error.UnsupportedSetting' for both the API call and the setting itself
				#So checking the description is the only way to distinguish
				#Remembering that a setting does not work, so we can exclude it in future. Doing it in an attribute lets users revert that decision
				print "Checking setting $path\n";
				my $exAttr=$attr{$name}{"excludeSetting"};
				if (defined $exAttr and $exAttr ne "") {
					$exAttr =~ s/,/\$|^/m;
					$exAttr = "^".$exAttr."\$";
					$attr{$name}{"excludeSetting"}.=",".$path if ($exAttr !~ /$path/);
				} else {
					$attr{$name}{"excludeSetting"}=$path;
				}
			}
			#Ignore if error contains something with "offline" as it seems normal that some calls don't get a callback (only events)
			return if $desc =~ /offline/;
		}
		HomeConnect_HandleError($hash,$jhash);
	}

	#-- no error, but possibly some additional things to do
    if ( defined($HC_delayed_PS) && $HC_delayed_PS ne "0" ) {
	  HomeConnect_FileLog($hash,"Response getting Program Options");
	  $HC_delayed_PS = 0;
	  HomeConnect_GetProgramOptions($hash);
	}
  }
}

###############################################################################
#
#   HandleError
#  "Program can currently not be written" ==> childlock ??
#  "HomeAppliance connection initialization failed" ==> after timeout
#  "Request cannot be performed since OperationState is not Ready"
#  "HomeAppliance connection initialization failed"
#  "BSH.Common.Setting.PowerState validation failed with OutOfBounds"
#
###############################################################################

sub HomeConnect_HandleError($$) {
  my ( $hash, $jhash ) = @_;
  my $name = $hash->{NAME};

  my $error           = "unknown";
  if ( defined $jhash->{"error"}->{"description"} ) {
	$error = $jhash->{"error"}->{"description"};
	Log3 $name, 1, "[HomeConnect_HandleError] $name: Error \"$error\""
	  if $error;
	readingsSingleUpdate( $hash, "lastErr", $error, 1 );
	if ( $error =~ /offline/ ) {

	  #-- key SDK.Error.HomeAppliance.Connection.Initialization.Failed
	  HomeConnect_readingsSingleUpdate( $hash, "BSH.Common.Status.OperationState", "Offline", 1 );
	  $hash->{STATE} = "Offline";
	  #In offline case, the initalization should just continue to next stage
	  $hash->{helper}->{init}="programs_done" if $hash->{helper}->{init} eq "programs";
	  $hash->{helper}->{init}="status_done" if $hash->{helper}->{init} eq "status";
	  HomeConnect_checkState($hash);
	}
	elsif ( $error =~ /currently not available or writable/ ) {

	  #????

	}
	elsif ( $error =~ /not supported/ ) {

	  #????

	}
  }
  return $error;
}

###############################################################################
#
#   Set
#
###############################################################################

sub HomeConnect_Set($@) {
  my ( $hash, @a ) = @_;
  my $reDOUBLE = '^(\\d+\\.?\\d{0,2})$';
  my $JSON     = JSON->new->utf8(0)->allow_nonref;

  my $haId = $hash->{haId};
  my $name = $hash->{NAME};
  my $type = $hash->{type};

  my $opts = join @a;

#--connect to Home Connect server, initialize status ------------------------------
  if ( $a[1] eq "init" ) {
	Log3 $hash->{NAME}, 1, "[HomeConnect_Set] init called";  
	InternalTimer( gettimeofday() + int(rand(10))+5, "HomeConnect_Init", $hash, 0 );
	return;
  }
  return if !defined $hash->{prefix};    #Init not complete yet
										 #-- update debug setting
										 #$HC_debug = AttrVal($name,"debug",0);

  #-- prefixes
  my $programPrefix = $hash->{prefix} . ".Program.";
  my $optionPrefix  = $hash->{prefix} . ".Option.";

  my $availableCmds = "ZZZ_Dump:noArg statusRequest:noArg ";

  my $excludes = $attr{$name}{"excludeSetting"};
  $excludes="" if !defined $excludes;
  $excludes =~ s/,/\$|^/m;
  $excludes = "^".$excludes."\$";
	  
  #-- first check: Logged in? WRONG, SHOULD BE CONNECTED
  #if (Value($hash->{hcconn}) ne "Logged in") {
  #  $availableCmds = "init";
  #  return $availableCmds if( $a[1] eq "?" );
  #} # WHAT ELSE???

  #-- PowerOn not for Hob, Oven and Washer
  #if( $powerOff && $type !~ /(Hob)|(Oven)|(Washer)/){
  if ( $type !~ /(Hob)|(Oven)|(Washer)/ ) {
	$availableCmds .= "PowerOn:noArg ";

	#return $availableCmds if( $a[1] eq "?" );
  }

  #-- PowerOff not for Hob, Oven
  #if( !$powerOff && $type !~ /(Hob)|(Oven)/){
  if ( defined( $hash->{data}->{poweroff} ) ) {
	$availableCmds .= $hash->{data}->{poweroff} . ":noArg ";
  }

  if ( $type =~ /(Hood)|(Dishwasher)/ ) {
	$availableCmds .= "AmbientLightCustomColor:colorpicker,RBG " if ("AmbientLightCustomColor" !~ /$excludes/);
  }

  #-- programs taken from hash or empty
  my $programs = $hash->{programs};
  if ( !defined($programs) ) {
	$programs = "";
  }
  
  my $operationState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.OperationState", "" );
  my $pgmRunning=0;
  #$pgmRunning=1 if (HomeConnect_ReadingsVal($hash,"BSH.Common.Root.ActiveProgram","") ne "");
  my $pgmRunning = $operationState =~ /((Active)|(DelayedStart)|(Run)|(Pause))/;
  my $remoteStartAllowed=HomeConnect_ReadingsVal($hash,"BSH.Common.Status.RemoteControlStartAllowed",0);

#-- no programs for freezers, fridge freezers, refrigerators and wine coolers
#   and due to API restrictions, wwe may also not set the programs for Hob and Oven
  if ( $hash->{type} !~ /(Hob)|(Oven)|(FridgeFreezer)/ ) {
	  if ($pgmRunning) {
		$availableCmds .= " StopProgram:noArg";
		$availableCmds .= " PauseProgram:noArg";
		$availableCmds .= " ResumeProgram:noArg";

	  }elsif ($remoteStartAllowed) {
		$availableCmds .= " StartProgram:noArg";
		$availableCmds .= " SelectedProgram:$programs";
	  }
  }

#-- available settings ----------------------------------------------------------------------
  my $availableSets = $hash->{settings};
  if ( !defined($availableSets) ) {
	Log3 $name, 1, "[HomeConnect_Set] $name: no settings defined, replacing by default settings for type $type";
	$availableSets = $HomeConnect_DeviceSettings{$type};
	return "" if ( $a[1] eq "?" );
  }
  else {
	$availableSets =~ s/\,/ /g;

	#-- transform ChildLock setting into ChildLock on/off command
	if ( $availableSets =~ /([a-zA-Z\.]*)ChildLock/ ) {
	  $availableSets =~ s/$1ChildLock/ChildLock:on,off/;
	}

	#-- transform AlarmClock setting into AlarmClock command
	if ( $availableSets =~ /([a-zA-Z\.]*)AlarmClock/ ) {
	  $availableSets =~ s/$1AlarmClock/AlarmRelative:time AlarmEndTime:time AlarmCancel:noArg/;
	}

	#-- SabbathMode setting does not imply that it may be set. Leave out for now
	#-- transform SabbathMode setting into sabbathMode on/off command
	#if( $availableSets =~ /([a-zA-Z\.]*)SabbathMode/){
	#  $availableSets =~ s/$1SabbathMode/SabbathMode:on,off/;
	#}
  }

#-- available options ------------------------------------------------------------------------
  my $availableOpts        = "";
  my $availableOptsWidgets = "";
  my $availableOptsHTML    = "";
  
  #TEST
  #$availableOpts .= "DelayStartTime:time DelayEndTime:time DelayRelative:time ";
  
  
  if ( defined( $hash->{data}->{options} ) ) {
	foreach my $key ( keys %{ $hash->{data}->{options} } ) {

	  #-- key with or without prefix
	  my $prefix = $hash->{data}->{options}->{$key}->[0];

	  if ($key !~ /$excludes/) {
		  #-- special key for delayed start
		  if ( $key =~ /((StartInRelative)|(FinishInRelative))/ ) {

			#Never include prefix for commands - this is ugly
			$availableOpts .= "DelayStartTime:time DelayEndTime:time DelayRelative:time " if $remoteStartAllowed;
		  }
		  else {
			$availableOpts .= $key;

			#-- type determines widget
			my $dtype = $hash->{data}->{options}->{$key}->[1];

			#-- no special widget
			if ( $dtype eq "Double" ) {

			  #-- no special widget
			}
			elsif ( $dtype eq "Int" ) {

			  #-- select 0/1
			}
			elsif ( $dtype eq "Boolean" ) {
			  $availableOpts .= ":0,1";    #--- ON/OFF??
			}
			elsif ( $dtype =~ /Enum/ ) {
			  my $vals = $hash->{data}->{options}->{$key}->[3];
			  $availableOpts .= ":" . $vals;
			}
		  }
		  $availableOpts .= " "
			if ( $availableOpts ne "" );
		}
	}
  }

  #-- put together
  $availableCmds .= " " . $availableOpts if ( $availableOpts ne "" );
  $availableCmds .= " " . $availableSets if ( $availableSets ne "" );

  #Log3 $name,1,"+++++++++++++++++**> Final List of Commands ".$availableCmds;

  return "[HomeConnect_Set] $name: no set value specified" if ( int(@a) < 2 );
  return $availableCmds                                    if ( $a[1] eq "?" );

  #-- read some conditions
  my $program = HomeConnect_ReadingsVal( $hash, "BSH.Common.Root.SelectedProgram", "" );
  my $powerState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.PowerState", "" );
  my $powerOff = ( ( $powerState =~ /Off/ ) || ( $operationState =~ /Inactive/ ) );
  my $doorState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.DoorState", "" );
  my $doorOpen = ( $doorState =~ /Open/ );

  #-- doit !
  shift @a;
  my $command = shift @a;
  HomeConnect_FileLog($hash,"set $command ".join(" ",@a));
  Log3 $name, 1, "[HomeConnect] $name: set command: $command";

  if ( $command eq "ZZZ_Dump" ) {
	return
		"Device $name of type $type has\nsettings: "
	  . Dumper( $hash->{data}->{settings} )
	  . "\noptions: "
	  . Dumper( $hash->{data}->{options} )
	  . "\ntranstable: "
	  . Dumper( $hash->{data}->{trans} )
	  . "\npoweroff: "
	  . Dumper( $hash->{data}->{poweroff} );

	#-- powerOn/Off ----------------------------------------------------
  }
  elsif ( $command =~ /statusRequest/ ) {

	HomeConnect_UpdateStatus($hash);
	#HomeConnect_checkState($hash);
  }
  elsif ( $command =~ /AmbientLight/ ) {

	HomeConnect_SetAmbientColor($hash,$a[0]);
  }
  elsif ( $command =~ /Power((On)|(Off)|(Standby))/ ) {
	HomeConnect_PowerState( $hash, $1 );

	#-- ChildLock -------------------------------------------------------
  }
  elsif ( $command eq "ChildLock" ) {
	HomeConnect_ChildLock( $hash, $a[0] );

	#-- SabbathMode -----------------------------------------------------
  }
  elsif ( $command =~ /SabbathMode/ ) {
	HomeConnect_SabbathMode( $hash, $a[0] );

	#-- DelayTimer-----------------------------------------------------
  }
  elsif ( $command =~
	/(DelayRelative)|(DelayStartTime)|(DelayEndTime)|(DelayFinishAt)/ )
  {
	#return "[HomeConnect] $name: cannot set delay timer, device powered off"
	#  if (!$powerOn);
	HomeConnect_delayTimer( $hash, $command, $a[0] );

	#-- AlarmClock -----------------------------------------------------
  }
  elsif ( $command eq "AlarmCancel" ) {
	HomeConnect_alarmCancel($hash);

  }
  elsif ( $command =~ /(AlarmRelative)|(AlarmEndTime)/ ) {
	HomeConnect_alarmTimer( $hash, $command, $a[0] );

	#-- start current program -------------------------------------------------
  }
  elsif ( $command eq "StartProgram" ) {

	#return "[HomeConnect_Set] $name: cannot start, device powered off"
	#  if (!$powerOn);
	return "[HomeConnect_Set] $name: a program is already running"
	  if ($pgmRunning);
	return "[HomeConnect_Set] $name: please enable remote start on your appliance to start a program"
	  if ( !$remoteStartAllowed );
	return "[HomeConnect_Set] $name: cannot start, door open"
	  if ($doorOpen);
	return HomeConnect_startProgram($hash);

  #--pause current program------------------------------------------------------
  }
  elsif ( $command eq "PauseProgram" ) {
	return "[HomeConnect_Set] $name: no program running to pause"
	  if ( !$pgmRunning );
	return HomeConnect_pauseProgram($hash);

  #--resume paused program------------------------------------------------------
  }
  elsif ( $command eq "ResumeProgram" ) {
	return "[HomeConnect_Set] $name: no program running to resume"
	  if ( !$pgmRunning );
	return HomeConnect_resumeProgram($hash);

   #--stop current program------------------------------------------------------
  }
  elsif ( $command eq "StopProgram" ) {
	return "[HomeConnect_Set] $name: cannot stop, no program is running"
	  if ( !$pgmRunning );
	my $data = {
	  callback => \&HomeConnect_Response,
	  uri      => "/api/homeappliances/$haId/programs/active"
	};
	HomeConnectConnection_delrequest( $hash, $data );

  #-- set options, update current program if needed ----------------------------
  }
  elsif ( index( $availableOpts, $command ) > -1 ) {
	my $optval  = shift @a;
	my $optvalx = $optval;
	my $optunit = shift @a;
	if ( !defined $optval ) {
	  return "[HomeConnect_Set] $name: please enter a new value for option $command";
	}

	#-- enumerated type: optvalx is the same as optval
	if ( !looks_like_number($optval) && !defined($optunit) ) {
	  $optval  = $hash->{data}->{options}->{$command}->[1] . "." . $optval;
	  $optval  = "\"$optval\"";
	  $optvalx = $optval;

	  #-- boolean type: optvalx is changed to true/false
	}
	elsif ( $optval =~ /^(0|1|((o|O)n)|((o|O)ff))$/ && !defined $optunit ) {
	  $optvalx = ( $optval =~ /1|((o|O)n)/ ) ? "true" : "false";
	}
	my $newreading = $optval;
	$newreading .= " " . $optunit if ( defined $optunit );

	#--- update reading
	HomeConnect_readingsSingleUpdate( $hash, $optionPrefix . $command, $newreading, 1 );

	#-- doit
	my $json =
	  "{\"data\":{\"key\":\"$optionPrefix$command\",\"value\":$optvalx";
	$json .= ",\"unit\":\"$optunit\"" if ( defined $optunit );
	$json .= "}}";

	#-- for selected program use "programs/selected"
	#   for active program use programs/active
	#   $hash->{data}->{options}->{$key} = [$pref,$type,$def,$vals,$lup,$exec];
	my $choice     = "selected";
	my $liveupdate = $hash->{data}->{options}->{$command}->[4];
	if ( $pgmRunning && defined($liveupdate) && $liveupdate eq "1" ) {
	  $choice = "active";
	}

	my $data = {
	  callback => \&HomeConnect_Response,
	  uri      => "/api/homeappliances/$haId/programs/$choice/options/$optionPrefix$command",
	  data => $json
	};
	Log3 $name, 1, "[HomeConnect_Set] changing option with uri " . $data->{uri} . " and data " . $data->{data};
	HomeConnect_request( $hash, $data );
	#-- set settings -----------------------------------------------------
  }
  elsif ( index( $availableSets, $command ) > -1 ) {
	my $setval  = shift @a;
	my $setunit = shift @a;
	if ( !defined $setval ) {
	  return "[HomeConnect_Set] $name: please enter a new value for setting $command";
	}

	#-- enumerated type
	if ( !looks_like_number($setval) && !defined($setunit) ) {
	  $setval =	$hash->{data}->{settings}->{$command}->[1] . "." . $setval;
	  $setval = "\"$setval\"";

	  #-- boolean type
	}
	elsif ( $setval =~ /^(0|1|((o|O)n)|((o|O)ff))$/ && !defined $setunit ) {
	  $setval = ( $setval =~ /1|((o|O)n)/ ) ? "true" : "false";
	}
	my $newreading = $setval;
	$newreading .= " " . $setunit if ( defined $setunit );
	HomeConnect_readingsSingleUpdate( $hash, "BSH.Common.Setting." . $command, $newreading, 1 );

	#-- doit
	my $json =
	  "{\"data\":{\"key\":\"BSH.Common.Setting.$command\",\"value\":$setval";
	$json .= ",\"unit\":\"$setunit\"" if ( defined $setunit );
	$json .= "}}";

	my $data = {
	  callback => \&HomeConnect_Response,
	  uri  => "/api/homeappliances/$haId/settings/BSH.Common.Setting.$command",
	  data => $json
	};
	Log3 $name, 1,
		"[HomeConnect_Set] changing setting with uri "
	  . $data->{uri}
	  . " and data "
	  . $data->{data};
	HomeConnect_request( $hash, $data );
 #-- select a program ----------------------------------------------------------
  }
  elsif ( $command =~ /(s|S)elect(ed)?Program/ ) {

	#return "[HomeConnect_Set] $name: cannot select program, device powered off"
	#  if (!$powerOn);
	my $program = shift @a;

	#-- trailing space ???
	$program =~ s/\s$//;
	Log3 $name, 1, "[HomeConnect_Set] command to select program $program";

	if ( ( !defined $program )
	  || ( $programs ne "" && index( $programs, $program ) == -1 ) )
	{
	  return "[HomeConnect_Set] $name: unknown program $program, choose one of $programs";
	}

	##### TEMPORARY
	if ( $program =~ /Favorite.*/ ) {
	  $programPrefix = "BSH.Common.Program.";
	}

	my $data = {
	  callback => \&HomeConnect_Response,
	  uri      => "/api/homeappliances/$haId/programs/selected",
	  data     => "{\"data\":{\"key\":\"$programPrefix$program\"}}"
	};

	#-- make sure that after selecting also GetProgramOptions is called
	$HC_delayed_PS = 1;
	#HomeConnect_readingsSingleUpdate( $hash, "BSH.Common.Status.SelectedProgram", $program, 1 );

	Log3 $name, 1, "[HomeConnect] selecting program $program with uri " . $data->{uri} . " and data " . $data->{data};
	HomeConnect_request( $hash, $data );
  }
}

###############################################################################
#
#   Get
#
###############################################################################

sub HomeConnect_Get($@) {
  my ( $hash, @args ) = @_;
  my $name = $hash->{NAME};
  my $cmd  = $args[1];

  #-- check argument
  my $gets     = "Settings:noArg";
  my $settings = $hash->{settings};
  my $type     = $hash->{type};
  if ( defined($settings) && $type !~ /FridgeFreezer/ ) {
	$gets .= " Programs:noArg ProgramOptions:noArg";
  }
  return "[HomeConnect_Get] $name: with unknown argument $cmd, choose one of " . $gets
	if ( $cmd eq "?" );

  #-- Programs ------------------------------------------
  if ( $cmd eq "Programs" ) {
	return HomeConnect_GetPrograms($hash);

	#-- ProgramOptions ------------------------------------------
  }
  elsif ( $cmd eq "ProgramOptions" ) {
	return HomeConnect_GetProgramOptions($hash);

#-- Request appliance settings ----------------------------------------------------
  }
  elsif ( $cmd eq "Settings" ) {
	return HomeConnect_GetSettings($hash);
  }
}

###############################################################################
#
#   PowerState
#
###############################################################################

sub HomeConnect_PowerState($$) {
  my ( $hash, $target ) = @_;
  my $name = $hash->{NAME};
  my $haId = $hash->{haId};

  my $operationState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.OperationState", "" );
  my $powerState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.PowerState", "" );

  if ( $target !~ /^((On)|(Off)|(Standby))$/ ) {
	return "[HomeConnect_PowerState] $name: called with wrong argument $target";
  }
  else {
	Log3 $name, 1, "[HomeConnect_PowerState] $name: setting PowerState->$target while OperationState=$operationState and PowerState=$powerState";
  }

  #-- send the update
  my $json =
"{\"data\":{\"key\":\"BSH.Common.Setting.PowerState\",\"value\":\"BSH.Common.EnumType.PowerState.$target\"}}";
  my $data = {
	callback => \&HomeConnect_Response,
	uri => "/api/homeappliances/$haId/settings/BSH.Common.Setting.PowerState",
	timeout => 90,
	data    => $json
  };
  HomeConnect_request( $hash, $data );
}

###############################################################################
#
#   Routines for Settings
#
###############################################################################

sub HomeConnect_ChildLock($$) {
  my ( $hash, $value ) = @_;
  my $name = $hash->{NAME};
  my $haId = $hash->{haId};

  $value = ( $value eq "on" ) ? "true" : "false";

  #-- send the update
  my $json = "{\"key\":\"BSH.Common.Setting.ChildLock\",\"value\":$value}";
  my $data = {
	callback => \&HomeConnect_Response,
	uri  => "/api/homeappliances/$haId/settings/BSH.Common.Setting.ChildLock",
	data => "{\"data\":$json}"
  };
  HomeConnect_request( $hash, $data );
}

sub HomeConnect_SabbathMode($$) {
  my ( $hash, $value ) = @_;
  my $name = $hash->{NAME};
  my $haId = $hash->{haId};

  $value = ( $value eq "on" ) ? "true" : "false";

  #-- send the update
  my $json = "{\"key\":\"BSH.Common.Setting.SabbathMode\",\"value\":$value}";
  my $data = {
	callback => \&HomeConnect_Response,
	uri  => "/api/homeappliances/$haId/settings/BSH.Common.Setting.SabbathMode",
	data => "{\"data\":$json}"
  };
  HomeConnect_request( $hash, $data );
}

###############################################################################
#
#   Routines for AlarmClock
#
###############################################################################

sub HomeConnect_alarmCancel {
  my ($hash) = @_;
  my $haId = $hash->{haId};

  #-- send the update
  my $json = "{\"key\":\"BSH.Common.Setting.AlarmClock\",\"value\":0}";
  my $data = {
	callback => \&HomeConnect_Response,
	uri  => "/api/homeappliances/$haId/settings/BSH.Common.Setting.AlarmClock",
	data => "{\"data\":$json}"
  };
  HomeConnect_request( $hash, $data );
}

sub HomeConnect_alarmTimer($$$) {
  my ( $hash, $command, $value ) = @_;

  my $name = $hash->{NAME};
  my $haId = $hash->{haId};

  my $secs;

  #-- value is always in minutes or hours:minutes
  if ( $value =~ /((\d+):)?(\d+)/ ) {
	$secs = $2 * 3600 + 60 * $3;
  }
  else {
	Log3 $name, 1,
	  "[HomeConnect] $name: error, input value $value is not a time spec";
	return;
  }

  my ( $sec, $min, $hour ) = ( localtime() )[ 0, 1, 2 ];

  #-- determine endtime
  my $inrelative;
  if ( $command eq "AlarmEndTime" ) {
	$inrelative = $secs - $hour * 3600 - $min * 60 - $sec;
	$inrelative += 86400
	  if ( $inrelative < 0 );
  }
  else {
	$inrelative = $secs;
  }

  #-- send the update
  my $json =
	"{\"key\":\"BSH.Common.Setting.AlarmClock\",\"value\":$inrelative}";
  my $data = {
	callback => \&HomeConnect_Response,
	uri  => "/api/homeappliances/$haId/settings/BSH.Common.Setting.AlarmClock",
	data => "{\"data\":$json}"
  };
  HomeConnect_request( $hash, $data );
}

###############################################################################
#
#   Routines for delayed start
#
###############################################################################

sub HomeConnect_delayTimer($$$) {
  my ( $hash, $command, $value ) = @_;

  my $name = $hash->{NAME};
  my $haId = $hash->{haId};

  my $secs;
  my $thour;
  my $tmin;

  #-- value is always in minutes or hours:minutes
  if ( $value =~ /((\d+):)?(\d+)/ ) {
	$tmin  = $3;
	$thour = defined $2 ? $2 : 0;
	$secs  = $thour * 3600 + 60 * $tmin;
  }
  else {
	return "[HomeConnect_delayTimer] $name: error, input value $value is not a time spec";
  }
  Log3 $name, 1, "[HomeConnect_delayTimer] $name: requested Delay $secs ($thour:$tmin)";

  #-- how long does the selected program run
  my $delta;

  #-- do we start in relativ or finish in relative
  my $delstart = defined( $hash->{data}->{options}->{"StartInRelative"} );
  my $delfin   = defined( $hash->{data}->{options}->{"FinishInRelative"} );
  #$delfin=1;
  #- device has option StartInRelative
  if ($delstart) {
	$delta = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.RemainingProgramTime", 0 );
	
	$delta =~ s/\D+//g;    #strip " seconds"
						   #-- device has option FinishInRelative
  }
  elsif ($delfin) {
	$delta = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.FinishInRelative", 0 );
	#$delta=13500;
	if ($delta eq "0") {
	#Device might have estimated program time instead
		$delta = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.EstimatedTotalProgramTime", 0 );
	}
	$delta =~ s/\D+//g;    #strip " seconds"
  }
  else {
	return "[HomeConnect_delayTimer] $name: error, device has neither startInRelative nor finishInRelative";
  }
  $delta = 0 if !looks_like_number($delta);

  Log3 $name, 1, "[HomeConnect_delayTimer] $name: program time is $delta";
  if ( $delta <= 60 ) {
	return "[HomeConnect_delayTimer] $name: error, no program seleced";
  }
  HomeConnect_FileLog($hash,"$command $value $delta");

  #-- determine start and end
  my ( $min,             $hour ) = ( localtime() )[ 1, 2 ];
  my ( $startinrelative, $starttime, $endinrelative, $endtime );
  my ( $endmin,          $endhour,   $startmin,      $starthour );
  if ( $command =~ /DelayStartTime/ ) {
	$startinrelative = $secs - $hour * 3600 - $min * 60;
	$startinrelative += 86400
	  if ( $startinrelative < 0 );
	$endinrelative = $secs - $hour * 3600 - $min * 60 + $delta;
	$endinrelative += 86400
	  if ( $endinrelative < 0 );
	( $startmin, $starthour ) =
	  ( localtime( time + $startinrelative ) )[ 1, 2 ];
	( $endmin, $endhour ) = ( localtime( time + $endinrelative ) )[ 1, 2 ];
  }
  elsif ( $command =~ /DelayEndTime/ ) {
	$startinrelative = $secs - $hour * 3600 - $min * 60 - $delta;
	$startinrelative += 86400
	  if ( $startinrelative < 0 );
	$endinrelative = $secs - $hour * 3600 - $min * 60;
	$endinrelative += 86400
	  if ( $endinrelative < 0 );
	( $startmin, $starthour ) =
	  ( localtime( time + $startinrelative ) )[ 1, 2 ];
	( $endmin, $endhour ) = ( localtime( time + $endinrelative ) )[ 1, 2 ];
  }
  elsif ( $command =~ /DelayRelative/ ) {
	$startinrelative = $secs;
	$endinrelative   = $secs + $delta;
	( $startmin, $starthour ) =
	  ( localtime( time + $startinrelative ) )[ 1, 2 ];
	( $endmin, $endhour ) = ( localtime( time + $endinrelative ) )[ 1, 2 ];
  }
  else {
	return "[HomeConnect] $name: error, unknown delay command $command";
  }
  $starttime = sprintf( "%d:%02d", $starthour, $startmin );
  $endtime   = sprintf( "%d:%02d", $endhour,   $endmin );
  HomeConnect_FileLog($hash,"Now: $hour:$min\nStarttime: $starttime\nEndtime: $endtime\nStartRel: $startinrelative\nEndRel: $endinrelative\n");

  #-- device has option StartInRelative
  if ($delstart) {
	my $h = int( $startinrelative / 3600 );
	my $m = ceil( ( $startinrelative - 3600 * $h ) / 60 );
	readingsBeginUpdate($hash);
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartInRelative", sprintf( "%i seconds",$startinrelative) );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartInRelativeHHMM", sprintf( "%d:%02d", $h, $m ) );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartAtHHMM", $starttime );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishAtHHMM", $endtime );
	readingsEndUpdate( $hash, 1 );
	Log3 $name, 1, "[HomeConnect_delayTimer] $name: startInRelative set to $startinrelative";

	#-- device has option FinishInRelative
  }
  else {
	my $h = int( $endinrelative / 3600 );
	my $m = ceil( ( $endinrelative - 3600 * $h ) / 60 );
	readingsBeginUpdate($hash);
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishInRelative", sprintf("%i seconds",$endinrelative) );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishInRelativeHHMM", sprintf( "%d:%02d", $h, $m ) );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishAtHHMM", $endtime );
	readingsEndUpdate( $hash, 1 );
	Log3 $name, 1, "[HomeConnect_delayTimer] $name: finishInRelative set to $endinrelative";
  }
}

###############################################################################
#
#   startProgram
#
###############################################################################

sub HomeConnect_startProgram($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $ret;

  my $programPrefix = $hash->{prefix} . ".Program.";

  my $programs = $hash->{programs};
  if ( !defined($programs) || $programs eq "" ) {
	$ret = "[HomeConnect_startProgram] $name: Cannot start, list of programs empty";
	Log3 $name, 1, $ret;
	return $ret;
  }
  my $program =	HomeConnect_ReadingsVal( $hash, "BSH.Common.Root.SelectedProgram", undef );
  $program =~ s/.*Program\.//;

  #-- trailing space ???
  $program =~ s/\s$//;

  if ( $program eq "" ) {
	$program = HomeConnect_ReadingsVal( $hash, "BSH.Common.Root.SelectedProgram",
	  undef );
  }

  if ( !defined $program || index( $programs, $program ) == -1 ) {
	$ret = "[HomeConnect_startProgram] $name: Cannot start, unknown program $program, choose one of $programs";
	Log3 $name, 1, $ret;
	return $ret;
  }

  #-- the option hash does not have prefixes in key, but in array
  #   $hash->{data}->{options}->{$key} = [$pref,$type,$def,$vals,$lup,$exec];
  my $optdata = "";

  foreach my $key ( keys %{ $hash->{data}->{options} } ) {

	# (keypref= key with prefix, key = key without prefix)
	my $keypref = $hash->{data}->{options}->{$key}->[0] . "." . $key;

#-- liveupdate? Then this must not be included in the start code
#   TODO: REALLY ?? NO, WRONG !! StartInRelative can no longer be set separately!
	next
	  if ( defined( $hash->{data}->{options}->{$key}->[4] )
	  && $hash->{data}->{options}->{$key}->[4] == 1 );

 #-- take the current value (keypref= key with prefix, key = key without prefix)
	my $value = HomeConnect_ReadingsVal( $hash, $keypref, "" );

	#-- safeguard against missing delay
	$value = "0 seconds"
	  if ( $key eq "StartInRelative" && $value eq "" );
	Log3 $name, 1,
	  "[HomeConnect_startProgram] $name: option $key has value $value";

	#-- construct json expression for value
	my @a = split( "[ \t][ \t]*", $value );
	$optdata .= ","
	  if ( $optdata ne "" );

	if ( looks_like_number( $a[0] ) ) {

	  #-- has a unit, must be a numerical value
	  if ( defined $a[1] ) {
		$optdata .= "{\"key\":\"$keypref\",\"value\":$a[0],\"unit\":\"$a[1]\"";

		#-- no unit, should be boolean
	  }
	  else {
		my $b = ( $a[0] == 1 ) ? "true" : "false";
		$optdata .= "{\"key\":\"$keypref\",\"value\":$b";
	  }

	  #-- string value - has a complex type
	}
	else {
	  my $type = $hash->{data}->{options}->{$key}->[1];
	  $optdata .= "{\"key\":\"$keypref\",\"value\":\"$type.$a[0]\"";
	  $optdata .= ",\"unit\":\"$a[1]\""
		if defined $a[1];
	}
	$optdata .= "}";
  }

  #SPECIAL TEST CASE
  my $program2 = $programPrefix . $program;
  if ( $program2 =~ /Cooking.Hood.Program.Cooking.Common.Program/ ) {
	Log 1, 	  "=========> Problem in start, prefix=$programPrefix, program=$program";
	Log 1, "           Removing first part ";
	$program2 =~ s/Cooking.Hood.Program\.//;
  }

  ##### TEMPORARY
  if ( $program =~ /Favorite.*/ ) {
	$programPrefix = "BSH.Common.Program.";
  }

  #-- submit update
  my $data = {
	callback => \&HomeConnect_Response,
	uri      => "/api/homeappliances/" . $hash->{haId} . "/programs/active",
	data     =>
	  "{\"data\":{\"key\":\"$programPrefix$program\",\"options\":[$optdata]}}"
  };

  Log3 $name, 1, "[HomeConnect] $name: start program $program with uri " . $data->{uri} . " and data " . $data->{data};
  HomeConnect_request( $hash, $data );
}

#BSH.Common.Status.OperationState=BSH.Common.EnumType.OperationState.Pause
sub HomeConnect_pauseProgram($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #-- submit update
  my $data = {
	callback => \&HomeConnect_Response,
	uri		=> "/api/homeappliances/" . $hash->{haId} . "/commands/BSH.Common.Command.PauseProgram",
	data 	=> "{\"data\":{\"key\":\"BSH.Common.Command.PauseProgram\",\"value\": true } }" };
  Log3 $name, 1, "[HomeConnect] $name: pause program with uri " . $data->{uri} . " and data " . $data->{data};
  HomeConnect_request( $hash, $data );
}

sub HomeConnect_resumeProgram($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  #-- submit update
  my $data = {
	callback => \&HomeConnect_Response,
	uri      => "/api/homeappliances/" . $hash->{haId} . "/commands/BSH.Common.Command.ResumeProgram",
	data => "{\"data\":{\"key\":\"BSH.Common.Command.ResumeProgram\",\"value\": true}}"
  };
  Log3 $name, 1, "[HomeConnect] $name: resume program with uri " . $data->{uri} . " and data " . $data->{data};
  HomeConnect_request( $hash, $data );
}

###############################################################################
#
#   Timer
#
###############################################################################

sub HomeConnect_Timer {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $updateTimer = AttrVal( $name, "updateTimer", 5 );

  if ( defined $hash->{conn} and AttrVal( $name, "disable", 0 ) == 0 ) {
	HomeConnect_ReadEventChannel($hash);
  }

  # check if still connected
  if ( !defined $hash->{conn} and AttrVal( $name, "disable", 0 ) == 0 ) {

	# a new connection attempt is needed
	my $retryCounter =
	  defined( $hash->{retrycounter} ) ? $hash->{retrycounter} : 0;
	if ( $retryCounter == 0 ) {

	  # first try
	  HomeConnect_ConnectEventChannel($hash);
	  InternalTimer( gettimeofday() + $updateTimer, "HomeConnect_Timer", $hash, 0 );
	}
	else {
	  # add an extra wait time
	  InternalTimer( gettimeofday() + ( ($retryCounter) * 300 ), "HomeConnect_WaitTimer", $hash, 0 );
	}
	$retryCounter++;
	$hash->{retrycounter} = $retryCounter;
  } else {
	# all good
	InternalTimer( gettimeofday() + $updateTimer, "HomeConnect_Timer", $hash, 0 );
  }
}

###############################################################################
#
#   WaitTimer
#
###############################################################################

sub HomeConnect_WaitTimer {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $updateTimer = AttrVal( $name, "updateTimer", 10 );

  #-- a new connection attempt is needed
  if ( !defined $hash->{conn} ) {
	HomeConnect_ConnectEventChannel($hash);
  }
  InternalTimer( gettimeofday() + $updateTimer, "HomeConnect_Timer", $hash, 0 );

}

sub HomeConnect_SetAmbientColor {
  my ( $hash, $color ) = @_;
  
  $color=lc $color;
  my $json =
	"{\"key\":\"BSH.Common.Setting.AmbientLightCustomColor\",\"value\":\"#$color\"}";
  my $data = {
	callback => \&HomeConnect_Response,
	uri  => "/api/homeappliances/$hash->{haId}/settings/BSH.Common.Setting.AmbientLightCustomColor",
	data => "{\"data\":$json}"
 }; 
 HomeConnect_request( $hash, $data );
}

###############################################################################
#
#   GetSettings
#
###############################################################################

sub HomeConnect_GetSettings {
  my ( $hash, $program ) = @_;
  my $data = {
	callback => \&HomeConnect_ResponseGetSettings,
	uri      => "/api/homeappliances/$hash->{haId}/settings"
  };
  HomeConnect_request( $hash, $data );
}

###############################################################################
#
#   ResponseGetSettings HTML currently unused
#
###############################################################################

sub HomeConnect_ResponseGetSettings {
  my ( $hash, $json ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{type};
  my $msg;

  return
	if ( !defined $json );

  Log3 $name, 5, "[HomeConnect_ResponseGetSettings] $name: get settings response $json";

  my $JSON  = JSON->new->utf8(0)->allow_nonref;
  my $jhash = eval { $JSON->decode($json) };
  if ($@) {
	$msg = "[HomeConnect_ResponseGetSettings] $name: JSON error requesting settings: $@";
	Log3 $name, 1, $msg;
	return $msg;
  }
  HomeConnect_FileLog($hash,"ResponseGetSettings:".Dumper($jhash));

  if ( $jhash->{"error"} ) {
	my $error = HomeConnect_HandleError( $hash, $jhash );

#Older equipments are fully offline and return an error - continue with defaults to avoid problems after startup
	return $error if ( $error ne "HomeAppliance is offline" );
	$jhash->{data} = undef;
  }

  #-- no data received - we are using the default stuff
  if ( !$jhash->{data}->{settings} ) {
	$jhash->{data}->{settings} = \@{ $HomeConnect_DeviceSettings{$type} };

#This does not work - we would need to translate the array into something that looks like JSON (value=> , key=>) with numerical array indexes
#Setting to undef to the loop will exit right away and skip the settings for devices that do not answer (as old Washers)
	$jhash->{data}->{settings} = undef; #\@{$HomeConnect_DeviceSettings{$type}};
	Log3 $name, 1, "[HomeConnect_ResponseGetSettings] $name: get settings failed, using default stuff for type $type";
  }

  #-- put device dependent data into hash
  my $isDE = ( AttrVal( "global", "language", "EN" ) eq "DE" );

  $hash->{prefix} = $HomeConnect_DevicePrefix{$type};

  if ( defined $HomeConnect_DeviceEvents{$type} ) {
	$hash->{events} = join( ',', @{ $HomeConnect_DeviceEvents{$type} } );
  }
  else {
	$hash->{events} = "";
  }

  $hash->{data}->{poweroff} = $HomeConnect_DevicePowerOff{$type}
	if ( defined $HomeConnect_DevicePowerOff{$type} );

  $hash->{data}->{trans} = $HomeConnect_DeviceTrans_DE{$type}
	if ( defined $HomeConnect_DeviceTrans_DE{$type} && $isDE );

  #-- start the processing
  my $settingsPrefix = $hash->{prefix} . ".Setting.";
  readingsBeginUpdate($hash);

#-- localsettings is the full data, settings only for overview, setshtml is html
  my %localsettings = ();
  my $settings      = "";

  #my $setshtml = "<br/><div id=\"settinglist\"><table>";

  for ( my $i = 0 ; 1 ; $i++ ) {
	my $setsline = $jhash->{data}->{settings}[$i];
	if ( !defined $setsline ) { last }

#--cleanup the key from all prefixes (keypref= key with prefix, key = key without prefix)
	my $keypref = $setsline->{key};
	my $key     = $keypref;
	$key =~ s/(.*)\.//;
	my $pref = $1;

	#$setshtml    .=  "\n<tr><td>$key</td>";

	my $valpref = $setsline->{value};
	my $value   = $valpref;
	$value =~ s/(.*\.)//;
	my $vef  = $1;
	my $unit = $setsline->{unit};

	if ( $keypref !~ /((BSH.Common.Setting\.)|($settingsPrefix))/ ) {
	  Log3 $name, 1, "[HomeConnect_ResponseGetSettings] $name: strange prefix $1 found in $keypref";
	}

	#-- collect
	$localsettings{$key} = [ $pref, $vef, $value, $unit ];

	#-- careful: if only these settings allowed, settings will stay empty
	if ( $key !~ /(PowerState)|(Unit)|(Sabbath)/ ) {
	  if ( $settings ne "" ) {
		$settings .= ",";
	  }
	  $settings .= $key;
	}

	#Still put all received settings into readings
	HomeConnect_readingsBulkUpdate( $hash, $keypref, $value );
	Log3 $name, 4, "[HomeConnect_ResponseGetSettings] $name: updating setting $key to $value";
  }
  readingsEndUpdate( $hash, 1 );

  #$setshtml .= "</table></div>";

#-- hash->{data}->{settings} is for control of the parameters, $hash->{settings} for overview, $hash->{setlist} for HTML
  $hash->{data}->{settings} = \%localsettings;
  $hash->{settings} = $settings;

  #$hash->{setlist}          = $setshtml;
  $hash->{helper}->{init}="settings_done";
}

###############################################################################
#
#   GetPrograms
#
###############################################################################

sub HomeConnect_GetPrograms {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $msg;

#-- we do not get a list of programs if a program is active, so we just use the active program name
  my $operationState =
	ReadingsVal( $name, "BSH.Common.Status.OperationState", "" );
  my $activeProgram = ReadingsVal( $name, "BSH.Common.Root.ActiveProgram", "" );
  $activeProgram =~ s/^\s+|\s+$//g;
  if ( $operationState =~ /((Active)|(DelayedStart)|(Run))/ ) {
	if ( $activeProgram eq "" ) {
	  $msg = "[HomeConnect_GetPrograms] name: failure GetPrograms in OperationState=$operationState, but no ActiveProgram defined";
	  Log3 $name, 1, $msg;
	  return $msg;
	}
	else {
	  $msg = "[HomeConnect_GetPrograms] name: failure GetPrograms in OperationState=$operationState of ActiveProgram $activeProgram";
	  Log3 $name, 1, $msg;
	}
  }

  #-- Request available programs
  my $data = {
	callback => \&HomeConnect_ResponseGetPrograms,
	uri      => "/api/homeappliances/$hash->{haId}/programs/available"
  };
  HomeConnect_request( $hash, $data );

  Log3 $name, 5, "[HomeConnect_GetPrograms] $name: getting programs with uri " . $data->{uri};

}

###############################################################################
#
#   ResponseGetPrograms
#
###############################################################################

sub HomeConnect_ResponseGetPrograms {
  my ( $hash, $json ) = @_;
  my $name = $hash->{NAME};
  my $msg;

  return
	if ( !defined $json );

  Log3 $name, 5, "[HomeConnect_ResponseGetPrograms] $name: get programs response $json";

  #-- response from device
  my $JSON  = JSON->new->utf8(0)->allow_nonref;
  my $jhash = eval { $JSON->decode($json) };
  if ($@) {
	$msg = "[HomeConnect_ResponseGetPrograms] $name: JSON error requesting programs: $@";
	Log3 $name, 1, $msg;
	return $msg;
  }
  HomeConnect_FileLog($hash,"ResponseGetPrograms:".Dumper($jhash));

  return HomeConnect_HandleError( $hash, $jhash )
	if ( $jhash->{"error"} );

  my $programPrefix = $hash->{prefix} . ".Program.";
  my $extraPrograms = AttrVal( $name, "extraPrograms", "" );

  #-- put into list without prefix
  my $programs = "";
  for ( my $i = 0 ; 1 ; $i++ ) {
	my $programline = $jhash->{data}->{programs}[$i];
	if ( !defined $programline ) { last }
	my $key = $programline->{key};
	$key =~ s/$programPrefix//;

 #Work around a problem with certain dryers that repeat the program name 3 times
	my @kk = split( /\./, $key );
	$key = $kk[0] if ( @kk == 3 and $kk[0] eq $kk[1] );
	$programs .= ","
	  if ( $programs ne "" );
	$programs .= $key;
  }

  #-- do not overwrite if return is empty
  if ( $programs ne "" ) {
	$programs .= "," . $extraPrograms
	  if ( $extraPrograms ne "" );
	$hash->{programs} = $programs;
  }
  else {
	$msg = "[HomeConnect_ResponseGetPrograms] $name: no programs found";
	readingsSingleUpdate( $hash, "lastErr", "No programs found", 1 );
	Log3 $name, 1, $msg;
	return $msg;
  }
  $hash->{helper}->{init}="programs_done";
}

###############################################################################
#
#   GetProgramOptions
#
###############################################################################

sub HomeConnect_GetProgramOptions {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $msg;

  #-- start the processing
  my $programPrefix = $hash->{prefix} . ".Program.";

  #-- first guess selected program
  my $program =
	HomeConnect_ReadingsVal( $hash, "BSH.Common.Root.SelectedProgram", "" );
  $program =~ s/^\s+|\s+$//g;
  HomeConnect_FileLog($hash, "Program: $program");
  if ( $program eq "" ) {

	#-- 2nd guess active program
	$program =
	  HomeConnect_ReadingsVal( $hash, "BSH.Common.Root.ActiveProgram", "" );
	$program =~ s/^\s+|\s+$//g;

	#-- failure
	if ( $program eq "" || $program eq "-" ) {
	  $msg = "[HomeConnect_GetProgramOptions] $name: no program selected and no program active, cannot determine options";
	  readingsSingleUpdate( $hash, "lastErr", "No programs selected or active", 1 );
	  Log3 $name, 1, $msg;
	  return $msg;
	}
	else {
	  $msg = "[HomeConnect_GetProgramOptions] $name: getting options for active program $program instead of selected";
	  Log3 $name, 1, $msg;
	}
  }

  #-- add prefix for calling the API
  $program = $programPrefix . $program
	if ( $program !~ /$programPrefix/ );

  HomeConnect_FileLog($hash, "Program: $program");

  #SPECIAL TEST CASE - leaving that in as I don't have such a device
  if ( $program =~ /Cooking.Hood.Program.Cooking.Common.Program/ ) {
	Log 1, "=========> Problem in GetProgramOptions, prefix=$programPrefix, program=$program";
	Log 1, "           Removing first part ";
	$program =~ s/Cooking.Hood.Program\.//;
  }

  my $data = {
	callback => \&HomeConnect_ResponseGetProgramOptions,
	uri      => "/api/homeappliances/$hash->{haId}/programs/available/$program"
  };
  HomeConnect_request( $hash, $data );

  Log3 $name, 5, "[HomeConnect_GetProgramOptions] $name: getting options with uri " . $data->{uri};
}

###############################################################################
#
#   ResponseGetProgramOptions
#
###############################################################################

sub HomeConnect_ResponseGetProgramOptions {
  my ( $hash, $json ) = @_;
  my $name = $hash->{NAME};
  my $msg;

  return
	if ( !defined $json );

  Log3 $name, 5, "[HomeConnect_ResponseGetProgramOptions] $name: program options response $json";

  my $JSON  = JSON->new->utf8(0)->allow_nonref;
  my $jhash = eval { $JSON->decode($json) };
  if ($@) {
	$msg = "[HomeConnect_ResponseGetProgramOptions] $name: JSON error requesting options: $@";
	Log3 $name, 1, $msg;
	return $msg;
  }
  HomeConnect_FileLog($hash,"GetProgramOptions:".Dumper($jhash));

  return HomeConnect_HandleError( $hash, $jhash )
	if ( $jhash->{"error"} );

  #-- start the processing
  my $program = HomeConnect_ReadingsVal( $hash, "BSH.Common.Root.SelectedProgram", "" );

  #-- localoptions is the full data, options for overview, optshtml for HTML
  #   no change of readings at this stage
  my %localoptions = ();
  my $options      = "";

  for ( my $i = 0 ; 1 ; $i++ ) {
	my $optsline = $jhash->{data}->{options}[$i];
	if ( !defined $optsline ) { last }

	#--cleanup the key from all prefixes
	my $keypref = $optsline->{key};
	my $key     = $keypref;
	$key =~ s/(.*)\.//;

	#-- prefix
	my $pref = $1;

	#-- type
	my $type = $optsline->{type};

	#-- default value
	my $defpref = $optsline->{constraints}->{default};
	my $def;
	if ( defined($defpref) ) {
	  $def = $defpref;
	  $def =~ s/$type\.//;
	}

	#-- allowedvalues or current value
	my $vals = "";

	#my $cval;

	if ( $type eq "Double" ) {
	  $vals = "("
		. $optsline->{constraints}->{min} . ","
		. $optsline->{constraints}->{max} . ")";
	}
	elsif ( $type eq "Int" ) {
	  ## WHY NON NUM IN FOLLOWING LINE
	  $vals = "("
		. $optsline->{constraints}->{min} . ","
		. $optsline->{constraints}->{max} . ")";
	}
	elsif ( $type eq "Boolean" ) {
	}
	else {
	  foreach my $val ( @{ $optsline->{constraints}->{allowedvalues} } ) {
		$val =~ s/$type\.//;
		$vals .= ","
		  if ( $vals ne "" );
		$vals .= $val;
	  }
	}

	#TODO: make this a structured hash?
	#-- collect
	$localoptions{$key} = [

	  #-- prefix
	  $pref,

	  #-- type
	  $type,

	  #-- default value
	  $def,

	  #-- allowed values
	  $vals,

	  #-- liveupdate
	  $optsline->{constraints}->{liveupdate},

	  #-- execution
	  $optsline->{constraints}->{execution}
	];
	$options .= ","
	  if ( $options ne "" );
	$options .= $key;
  }

#-- hash->{data}->options} is for control of the parameters, $hash->{options} for overview, $hash->{optlist} for HTML
  if ( $options ne "" ) {
	$hash->{data}->{options} = \%localoptions;
	$hash->{options} = $options;
  }
  else {
	$msg = "[HomeConnect_ResponseGetProgramOptions] $name: no options found";
	Log3 $name, 1, $msg;
	return $msg;
  }
}

##############################################################################
#
#   checkState
#
##############################################################################

sub HomeConnect_checkState($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if !defined $hash->{prefix};    #Still not initialized
  my $lang = AttrVal( "global", "language", "EN" );
  my $programPrefix = $hash->{prefix} . "Command.";

  my $currentstate = ReadingsVal($name, "state", "off");
 #--- operationState (some device report OperationState ready while powered off)
  my $operationState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.OperationState", "" );
  $operationState =~ s/BSH.*State.//g;

  #-- check for power
  my $powerState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.PowerState", "" );
  $powerState =~ s/BSH.*State.//g;

  my $orgOpSt=$operationState;
  #-- correct for powered off and ready
  $operationState = "Inactive" if ( $powerState =~ /Off/ && $operationState =~ /Ready/ );

  my $startInRelative = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.StartInRelative", 0 );
  my $finishInRelative = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.FinishInRelative", 0 );

  my $aprogram = HomeConnect_ReadingsVal( $hash, "BSH.Common.Root.ActiveProgram", "" );
  my $sprogram = HomeConnect_ReadingsVal( $hash, "BSH.Common.Root.SelectedProgram", "" );

  #-- active program missing
  if ( $aprogram eq "" && $operationState eq "Run" ) {
	$aprogram = $sprogram;
	HomeConnect_readingsSingleUpdate( $hash, "BSH.Common.Root.ActiveProgram", $aprogram, 1 );
  }

  #-- selected program missing
  if ( $sprogram eq "" && $operationState eq "Run" ) {
	$sprogram = $aprogram;
	HomeConnect_readingsSingleUpdate( $hash, "BSH.Common.Root.SelectedProgram", $sprogram, 1 );
  }

  #-- in running state both are identical now
  my $program = $aprogram;
  $program =~ s/$programPrefix//;

  #-- trailing space ???
  $program =~ s/\s$//;

#Log 1,"===========> $name has program $program, translated into ".$hash->{data}->{trans}->{$program};
#-- program name only replaced by transtable content if this exists
  if ( $program ne "" && defined( $hash->{data}->{trans}->{$program} ) ) {
	$program = $hash->{data}->{trans}->{$program};
  }
  if ($lang eq "DE" && defined $HomeConnect_DeviceTrans_DE{$hash->{type}}->{$program}) {
	$program = $HomeConnect_DeviceTrans_DE{$hash->{type}}->{$program};
  }
  my $pct =	HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.ProgramProgress", "0" );
  $pct =~ s/ \%.*//;
  $operationState = "Finished" if ( $pct == 100 ); #Some devices don't put a proper finish message when done
  
  my $tim = HomeConnect_ReadingsVal( $hash,	"BSH.Common.Option.RemainingProgramTimeHHMM", "0:00" );
  my $sta = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.StartAtHHMM", "0:00" );
  my $door = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.DoorState", "closed" );

  Log3 $name, 1, "[HomeConnect_checkState] from s:$currentstate d:$door o:$operationState";

  my $state1 = "";
  my $state2 = "";
  my $state  = "off";
  my $trans  = $HC_table{$lang}->{ lc $operationState };
  $trans=$operationState if (!defined $trans or $trans eq "");
  
  if ( $operationState =~ /(Run)/ ) {
	$state  = "run";
	$state1 = "$program";
	$state2 = "$tim";
	if ($currentstate ne $state and $program ne "") {
		#state changed into running - now get the program options that might only be valid during run (e.g. SilenceOnDemand)
		  $HC_delayed_PS = 0; #Clear request for program options just in case, as we do it anyway
	      HomeConnect_GetProgramOptions($hash);
	}
  }
  if ( $operationState =~ /Pause/ ) {
	$state  = "pause";
	$state1 = "$program";
	$state2 = $trans;
  }
  if ( $operationState =~ /(Delayed)|(DelayedStart)/ ) {
	$state  = "scheduled";
	$state1 = $trans;
	$state2 = "$sta";
  }
  if ( $operationState =~ /(Error)|(Action)/ ) {
	$state  = lc $operationState;
	$state1 = $trans;
	$state2 = "-";
	readingsSingleUpdate($hash,"lastErr","Error or action required",1);
  }
  if ( $operationState =~ /(Abort)|(Finished)/ ) {
	$state  = "done";
	$state1 = $HC_table{$lang}->{$state};
	$state2 = "-";
  }
  if ( $operationState =~ /(Ready)|(Inactive)|(Offline)/ ) {
	if ($currentstate eq "done" and $door =~ /Closed/) {
		#Delay switching to "idle" until door gets opened so user continues to get indication that appliance needs to be emptied, even when it goes to "off" automatically
		$state  = "done";
		$state1 = $HC_table{$lang}->{$state};
		$state2 = "-";
	} else {
		$state  = "idle";
		$state1 = $HC_table{$lang}->{$state};
		$state2 = "-";
	}
  }

#Opened door overrides any state from done -> idle to indicate the appliance got emptied
  if ( $door =~ /Open/ ) {
	$state  = "idle" if $state eq "done";
	$state1 = $HC_table{$lang}->{"door"} . " " . $HC_table{$lang}->{ lc $door };
	$state2 = "-";
  }

  Log3 $name, 1, "[HomeConnect_checkState] to s:$state d:$door 1:$state1 2:$state2";
  
  #Correct special characters if using encoding=unicode
  $state1 = decode_utf8($state1) if $unicodeEncoding;
  $state2 = decode_utf8($state2) if $unicodeEncoding;
  
  readingsBeginUpdate($hash);
  my $errage=ReadingsAge($name,"lastErr",0);
  #Clear lastErr if older than 30min to avoid confusion
  if ($errage>1800) {
	readingsBulkUpdate( $hash, "lastErr", "ok");
  }
  readingsBulkUpdate( $hash, "state",   $state );
  readingsBulkUpdate( $hash, "state1",  $state1 );
  readingsBulkUpdate( $hash, "state2",  $state2 );
  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Status.OperationState",  $operationState ) if $operationState ne $orgOpSt;
  readingsEndUpdate( $hash, 1 );
}

##############################################################################
#
#   UpdateStatus
#
##############################################################################

sub HomeConnect_UpdateStatus {
  my ($hash) = @_;
  my $haId = $hash->{haId};

  #-- Get status variables
  my $data = {
	callback => \&HomeConnect_ResponseUpdateStatus,
	uri      => "/api/homeappliances/$haId/status"
  };
  HomeConnect_request( $hash, $data );
}

##############################################################################
#
#   ResponseUpdateStatus
#
##############################################################################

sub HomeConnect_ResponseUpdateStatus {
  my ( $hash, $json ) = @_;
  my $name = $hash->{NAME};
  my $msg;

  if ( !defined $json ) {
	Log3 $name, 1, "[HomeConnect_ResponseUpdateStatus] $name: no status available";
	return;
  }

  Log3 $name, 5, "[HomeConnect_ResponseUpdateStatus] $name: status response $json";

  my $JSON  = JSON->new->utf8(0)->allow_nonref;
  my $jhash = eval { $JSON->decode($json) };
  if ($@) {
	$msg = "[HomeConnect_ResponseUpdateStatus] $name: JSON error requesting status: $@";
	Log3 $name, 1, $msg;
	return $msg;
  }
  HomeConnect_FileLog($hash,"Update Status:".Dumper($jhash));

  #-- local readings hash has all prefixes
  my %localreadings = ();
  for ( my $i = 0 ; 1 ; $i++ ) {
	my $statusline = $jhash->{data}->{status}[$i];
	if ( !defined $statusline ) { last }
	my $key   = $statusline->{key};
	my $value = $statusline->{value};
	my $unit  = $statusline->{unit};
	$localreadings{$key} =
	  $value . ( ( defined $unit ) ? " " . $unit : "" );
  }

  if ( $jhash->{"error"} ) {
	my $error = HomeConnect_HandleError( $hash, $jhash );
  }

  my $rootPrefix   = "BSH.Common.Root.";
  my $statusPrefix = "((BSH.Common.Status.)|(" . $hash->{prefix} . ".Status.))";

  #-- Update readings
  readingsBeginUpdate($hash);
  for my $key ( keys %localreadings ) {
	my $value = $localreadings{$key};
	if ( $key !~ /$statusPrefix/ ) {
	  Log3 $name, 1, "[HomeConnect_ResponseUpdateStatus] $name: found new status prefix in $key";
	}

	HomeConnect_readingsBulkUpdate( $hash, $key, $value );
	Log3 $name, 4, "[HomeConnect_ResponseUpdateStatus] $name: updating reading $key to $value";

  }
  readingsEndUpdate( $hash, 1 );

  my $operationState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.OperationState", "0" );
  my $pgmRunning = $operationState =~ /((Active)|(DelayedStart)|(Run))/;

  $hash->{helper}->{init}="status_done";
  
  #--check for a running program
  if ($pgmRunning) {
	HomeConnect_CheckProgram($hash);
  }

  #-- new state
  HomeConnect_checkState($hash);
}

##############################################################################
#
#   CheckProgram
#
##############################################################################

sub HomeConnect_CheckProgram {
  my ($hash) = @_;

  #-- Get status variables
  my $data = {
	callback => \&HomeConnect_ResponseCheckProgram,
	uri      => "/api/homeappliances/$hash->{haId}/programs/active"
  };
  HomeConnect_request( $hash, $data );
}

##############################################################################
#
#   ResponseCheckProgram
#
##############################################################################

sub HomeConnect_ResponseCheckProgram {
  my ( $hash, $json ) = @_;
  my $name = $hash->{NAME};
  my $msg;

  if ( !defined $json ) {
	Log3 $name, 1, "[HomeConnect_ResponseCheckProgram] $name: no response";
	return;
  }

  my $JSON  = JSON->new->utf8(0)->allow_nonref;
  my $jhash = eval { $JSON->decode($json) };
  if ($@) {
	$msg = "[HomeConnec_ResponseCheckProgram] $name: JSON error requesting status: $@";
	Log3 $name, 1, $msg;
	return $msg;
  }
  HomeConnect_FileLog($hash,"ResponseCheckProgram:".Dumper($jhash));

  #-- change readings if necessary
  Log3 $name, 1, "[HomeConnect_ResponseCheckProgram] $name: ActiveProgram WOULD BE SET TO ". $jhash->{data}->{key};
  readingsBeginUpdate($hash);
  for ( my $i = 0 ; 1 ; $i++ ) {
	my $optsline = $jhash->{data}->{options}[$i];
	if ( !defined $optsline ) { last }

#--cleanup the key from all prefixes (keypref= key with prefix, key = key without prefix)
	my $keypref = $optsline->{key};
	my $key     = $keypref;
	$key =~ s/(.*)\.//;
	my $val = $optsline->{value};
	$val =~ s/(.*\.)//;
	my $pref = $1;

	if ( defined($val) ) {
	  if ( defined $optsline->{unit} ) {
		$val .= " " . $optsline->{unit};
	  }
	  my $oldval =
		HomeConnect_ReadingsVal( $hash, $keypref, "" );
	  Log3 $name, 1, "[HomeConnect_ResponseCheckProgram] $name: key $keypref has current value $oldval and new value $pref $val";
	}
  }
  readingsEndUpdate( $hash, 1 );
}

##############################################################################
#
#   ConnectEventSchannel
#
##############################################################################

sub HomeConnect_ConnectEventChannel {
  my ($hash) = @_;

  my $name    = $hash->{NAME};
  my $haId    = $hash->{haId};
  my $api_uri = $defs{ $hash->{hcconn} }->{api_uri};

  my $param = {
	url         => "$api_uri/api/homeappliances/$haId/events",
	hash        => $hash,
	timeout     => 10,
	noshutdown  => 1,
	noConn2     => 1,
	httpversion => "1.1",
	keepalive   => 1,
	callback    => \&HomeConnect_HttpConnected
  };

  Log3 $name, 5, "[HomeConnect_ConnectEventChannel] $name: connecting to event channel";

  HttpUtils_NonblockingGet($param);
}

###############################################################################
#
#   HttpConnected
#
#   callback used by HttpUtils_NonblockingGet
#   it will be called after the http socket connection has been opened
#   and handles the http protocol part.
#
###############################################################################

sub HomeConnect_HttpConnected {
  my ( $param, $err, $data ) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  #-- make sure we're really connected
  if ( !defined $param->{conn} ) {
	HomeConnect_CloseEventChannel($hash);
	return;
  }

  my ( $gterror, $token ) = getKeyValue( $hash->{hcconn} . "_accessToken" );
  my $method = $param->{method};
  $method = ( $data ? "POST" : "GET" ) if ( !$method );

  my $httpVersion = $param->{httpversion} ? $param->{httpversion} : "1.0";
  my $hdr         = "$method $param->{path} HTTP/$httpVersion\r\n";
  $hdr .= "Host: $param->{host}\r\n";
  $hdr .= "User-Agent: fhem\r\n"
	if ( !$param->{header} || $param->{header} !~ "User-Agent:" );
  $hdr .= "Accept: text/event-stream\r\n";
  $hdr .= "Accept-Encoding: gzip,deflate\r\n" if ( $param->{compress} );
  $hdr .= "Connection: keep-alive\r\n"        if ( $param->{keepalive} );
  $hdr .= "Connection: Close\r\n"
	if ( $httpVersion ne "1.0" && !$param->{keepalive} );
  $hdr .= "Authorization: Bearer $token\r\n";

  if ( defined($data) ) {
	$hdr .= "Content-Length: " . length($data) . "\r\n";
	$hdr .= "Content-Type: application/x-www-form-urlencoded\r\n"
	  if ( $hdr !~ "Content-Type:" );
  }
  $hdr .= "\r\n";

  Log3 $hash->{NAME}, 5, "[HomeConnect_HttpConnected] $name: sending headers to event channel: $hdr";

  syswrite $param->{conn}, $hdr;
  $hash->{conn}                = $param->{conn};
  $hash->{eventChannelTimeout} = time();

  Log3 $hash->{NAME}, 5, "[HomeConnect_HttpConnected] $name: connected to event channel";

  #-- the server connection is left open to receive new events
}

###############################################################################
#
#   CloseEventChannel
#
###############################################################################

sub HomeConnect_CloseEventChannel($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if ( defined $hash->{conn} ) {
	$hash->{conn}->close();
	delete( $hash->{conn} );
	Log3 $name, 1, "[HomeConnect_CloseEventChannel] $name: disconnected from event channel";
  }
}

###############################################################################
#
#   ReadEventChannel
#
###############################################################################

sub HomeConnect_ReadEventChannel($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $inputbuf;
  my $JSON = JSON->new->utf8(0)->allow_nonref;

  if ( !defined $hash->{conn} ) {
	Log3 $name, 5, "[HomeConnect_ReadEventChannel] $name: event channel is not connected";
	return undef;
  }

  my ( $rout, $rin ) = ( '', '' );
  vec( $rin, $hash->{conn}->fileno(), 1 ) = 1;

  #-- check for timeout
  if ( defined $hash->{eventChannelTimeout}
	&& ( time() - $hash->{eventChannelTimeout} ) > 140 )
  {
	Log3 $name, 2, "[HomeConnect_ReadEventChannel] $name: event channel timeout, two keep alive messages missing";
	HomeConnect_CloseEventChannel($hash);
	return undef;
  }

  my $count      = 0;
  my $checkstate = 0;   # Flag that checkState should be called after processing

  #-- read data
  while ( $hash->{conn}->fileno() ) {

	#-- loop monitoring
	$count = $count + 1;
	if ( $count > 100 ) {
	  Log3 $name, 2, "[HomeConnect_ReadEventChannel] $name: event channel fatal error: infinite loop";
	  last;
	}

	#-- check channel data availability
	my $tmp    = $hash->{conn}->fileno();
	my $nfound = select( $rout = $rin, undef, undef, 0 );
	Log3 $name, 5, "[HomeConnect_ReadEventChannel] $name: event channel searching for data, fileno:\"$tmp\", nfound:\"$nfound\", loopCounter:\"$count\"";
	if ( $nfound < 0 ) {
	  Log3 $name, 2, "[HomeConnect_ReadEventChannel] $name: event channel timeout/error: $!";
	  HomeConnect_CloseEventChannel($hash);
	  return undef;
	}
	if ( $nfound == 0 ) {
	  last;
	}

	#--
	my $len = sysread( $hash->{conn}, $inputbuf, 32768 );

	Log3 $name, 5, "[HomeConnect_ReadEventChannel] $name: event channel len:\"$len\", received:\"$inputbuf\"";
	#-- check if something was actually read
	if ( !defined($len)
	  || $len == 0
	  || !defined($inputbuf)
	  || length($inputbuf) == 0 )
	{
	  Log3 $name, 5, "[HomeConnect_ReadEventChannel] $name: event channel read failed, len:\"$len\", received:\"$inputbuf\"";
	  HomeConnect_CloseEventChannel($hash);
	  return undef;
	}

	#-- reset timeout
	$hash->{eventChannelTimeout} = time();

	my ($event) = $inputbuf =~ /^event\:(.*)$/m;
	my ($id)    = $inputbuf =~ /^id\:(.*)$/m;
	my ($json)  = $inputbuf =~ /^data\:(.*)$/m;
	my ($http)  = $inputbuf =~ /^HTTP\/1.1 (.*) OK/m;

	if ($http) {
	  if ( $http ne "200" ) {
		Log3 $name, 2, "[HomeConnect_ReadEventChannel] $name: event channel received an http error: $_";
		HomeConnect_CloseEventChannel($hash);
		return undef;

		#-- successful connection, reset counter
	  }
	  else {
		$hash->{retrycounter} = 0;
	  }
	}
	elsif ( $json and $event =~ /NOTIFY|STATUS|EVENT/ ) {
	  Log3 $name, 5, "[HomeConnect_ReadEventChannel] $name: event $event data: $json";
	  my $jhash = eval { $JSON->decode($json) };

	  if ($@) {
		Log3 $name, 2, "[HomeConnect_ReadEventChannel] $name: JSON error reading from event channel";
		return;
	  }
	HomeConnect_FileLog($hash,"Event:".Dumper($jhash));

	  my $isfinished = 0;
	  my $isalarmoff = 0;
	  readingsBeginUpdate($hash);

	  for ( my $i = 0 ; 1 ; $i++ ) {
		my $item = $jhash->{items}[$i];
		if ( !defined $item ) { last }
		my $key   = $item->{key};
		my $value = $item->{value};
		$value = "" if ( !defined($value) );
		my $unit = $item->{unit};
		$unit = "" if ( !defined($unit) );

		HomeConnect_readingsBulkUpdate( $hash, $key, $value . ( ( defined $unit ) ? " " . $unit : "" ) );
		Log3 $name, 4, "[HomeConnect_ReadEventChannel] $name: $key = $value";

#Log3 $name, 1, "[HomeConnect_ReadEventChannel] $name: $key = $value"
#	if( $key !~ /.*((AlarmClock)|(StartInRelative)|(FinishInRelative)|(ElapsedProgramTime)|(ProgramProgress)|(RemainingProgramTime)|(CurrentCavityTemperature)|(PreheatFinished)|(RemoteControlStartAllowed)|(LocalControlActive)|(childLock)).*/ );

		#-- special keys
		my $tr_value;
		if ( $key =~ /ProgramFinished/ ) {
		  if ( $value =~ /Present/ ) {
			$isfinished = 1;

			#$tr_value =
		  }
		  else {
			#$tr_value =
		  }
		  $checkstate = 1;
		}
		elsif ( $key =~ /ActiveProgram/ ) {
		} elsif ( $key =~ /SelectedProgram/ ) {
		#Looks like set selectedprogram does not necessarly get a response callback, so react on the event 
		  $HC_delayed_PS = 0; #Clear request for program options just in case, as we do it anyway
	      HomeConnect_GetProgramOptions($hash);
		}	elsif ( $key =~ /RemainingProgramTime/ ) {
		  my $h    = int( $value / 3600 );
		  my $m    = ceil( ( $value - 3600 * $h ) / 60 );
		  my $tim1 = sprintf( "%d:%02d", $h, $m );

		  #-- hijacking the prefix although not authorized
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.RemainingProgramTimeHHMM", $tim1 );
		  $checkstate = 1;
		}
		elsif ( $key =~ /StartInRelative/ ) {
		  $value =~ s/\t.*//; # remove seconds
		  my $h    = int( $value / 3600 );
		  my $m    = ceil( ( $value - 3600 * $h ) / 60 );
		  my $tim2 = sprintf( "%d:%02d", $h, $m );

		  #-- determine start and end
		  my ( $startmin, $starthour ) =
			( localtime( time + $value ) )[ 1, 2 ];
		  my $delta = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.RemainingProgramTime", 0 );
		  #TODO: test number
		  my ( $endmin, $endhour ) =
			( localtime( time + $value + $delta ) )[ 1, 2 ];
		  my $tim3 = sprintf( "%d:%02d", $starthour, $startmin );
		  my $tim4 = sprintf( "%d:%02d", $endhour,   $endmin );

		  #-- hijacking the prefix although not authorized
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartInRelativeHHMM", $tim2 );
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartAtHHMM", $tim3 );
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartToHHMM", $tim4 );
		}
		elsif ( $key =~ /FinishInRelative/ ) {
		  $value =~ s/\t.*//; # remove seconds
		  my $h    = int( $value / 3600 );
		  my $m    = ceil( ( $value - 3600 * $h ) / 60 );
		  my $tim2 = sprintf( "%d:%02d", $h, $m );

		 #-- determine start and end
		 #my ($startmin, $starthour) = (localtime(time+$value))[1,2];
		 #my $delta = ReadingsNum($name,$optionPrefix."RemainingProgramTime",0);
		  my ( $endmin, $endhour ) =
			( localtime( time + $value ) )[ 1, 2 ];

		  #my $tim3 = sprintf("%d:%02d",$starthour,$startmin);
		  my $tim4 = sprintf( "%d:%02d", $endhour, $endmin );

		  #-- hijacking the prefix although not authorized
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishInRelativeHHMM", $tim2 );

		  #readingsBulkUpdate($hash, $optionPrefix."StartAtHHMM", $tim3);
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishAtHHMM", $tim4 );
		}
		elsif ( $key =~ /AlarmClockElapsed/ ) {
		  if ( $value =~ /Present/ ) {
			HomeConnect_readingsBulkUpdate( $hash,
			  "BSH.Common.Option.AlarmClockHHMM", "00:00" );
		  }
		  else {
		  }
		}
		elsif ( $key =~ /AlarmClock/ ) {
		  my $h    = int( $value / 3600 );
		  my $m    = ceil( ( $value - 3600 * $h ) / 60 );
		  my $tim5 = sprintf( "%d:%02d", $h, $m );

		  #-- determine end
		  my ( $endmin, $endhour ) =
			( localtime( time + $value ) )[ 1, 2 ];
		  my $tim6 = sprintf( "%d:%02d", $endhour, $endmin );

		  #-- hijacking the prefix although not authorized
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.AlarmClockHHMM", $tim5 );
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.AlarmAtHHMM", $tim6 );
		}
		elsif ( $key =~ /(DoorState)|(OperationState)/ ) {
		  $checkstate = 1;
		}
		elsif ( $key =~ /RemoteControlStartAllowed/ ) {
		}
	  }

	  #-- determine new state
	  HomeConnect_checkState($hash);
	}
	elsif ( $event eq "DISCONNECTED" ) {
	  my $state = "Offline";
	  readingsBulkUpdate( $hash, "state", $state )
		if ( $hash->{STATE} ne $state );
	  Log3 $name, 4, "[HomeConnect_ReadEventChannel] $name: disconnected $id";
	  $checkstate=1;
	}
	elsif ( $event eq "CONNECTED" ) {
	  Log3 $name, 4, "[HomeConnect_ReadEventChannel] $name: connected $id";
	  HomeConnect_UpdateStatus($hash);
	}
	elsif ( $event eq "KEEP-ALIVE" ) {
	  Log3 $name, 4, "[HomeConnect_ReadEventChannel] $name: keep alive $id";
	}
	else {
	  Log3 $name, 4,
		"[HomeConnect_ReadEventChannel] $name: Unknown event $event";
	  Log3 $name, 4,
		"[HomeConnect_ReadEventChannel] $name: Unknown event $inputbuf";
	}
	readingsEndUpdate( $hash, 1 );
  }

  #Update some status readings if requested
  HomeConnect_checkState($hash) if $checkstate;
  Log3 $name, 5, "[HomeConnect_ReadEventChannel] $name: event channel received no more data";
}

# Manipulate the Readings and Values according to the settings
# Attribute namePrefix = 1 : keep the prefix in the name of the reading
# Attribute valuePrefix = 1 : keep the prefix in the name of the value

sub HomeConnect_replaceReading($$) {
  my ( $hash, $value ) = @_;
  my $name          = $hash->{NAME};
  my $HC_namePrefix = AttrVal( $name, "namePrefix", 0 );
  if ( $HC_namePrefix == 0 ) {
	$value =~ s/BSH.Common.//;
	my $programPrefix = $hash->{prefix} . "\.";
	$value =~ s/$programPrefix//;
  }
  return $value;
}

sub HomeConnect_replaceValue($$) {
  my ( $hash, $value ) = @_;
  my $name           = $hash->{NAME};
  my $HC_valuePrefix = AttrVal( $name, "valuePrefix", 0 );
  if ( $HC_valuePrefix == 0 and $value =~ /\./ ) {
	$value =~ /.*\.(.*)$/;
	$value = $1;
  }
  $value =~ s/\s$//;    # Remove any trailing spaces
  $value = encode_utf8($value) if !($unicodeEncoding);
  return $value;
}

#Wrap the two readings Update functions into one
sub HomeConnect_readingsUpdate($$$$$) {
  my ( $hash, $reading, $value, $notify, $function ) = @_;
  my $nreading = HomeConnect_replaceReading( $hash, $reading );
  my $nvalue   = HomeConnect_replaceValue( $hash, $value );
  #Translation: if reading is in list, translate the value and create a new reading with "tr_" prefix
  my $trans = AttrVal ( $hash->{NAME}, "translate", "");
  $trans =~ s/,/\$|^/m;
  $trans = "^".$trans."\$";
  $nreading =~ /.*\.(.*)$/;
  my $sreading = $1; #Pure last part of the reading
  $value = $1;

  if ($sreading =~ $trans) {
	my $lvalue=lc $nvalue;
	my $tvalue=$nvalue;
    $tvalue =~ /\t.*/; #When translating also remove " %", " seconds", " °C" etc. to create a plain value
	$tvalue=$HC_table{DE}{$lvalue} if (defined $HC_table{DE}{$lvalue});
	#In case user wants the program name, try that as well:
	$tvalue=$hash->{data}->{trans}->{$nvalue} if (defined( $hash->{data}->{trans}->{$nvalue}));
	#$sreading="tr_".$sreading; #Custom readings don't need any prefix
	$tvalue = decode_utf8($tvalue) if $unicodeEncoding;
	readingsSingleUpdate( $hash, $sreading, $tvalue, $notify ) if $function eq "single";
	readingsBulkUpdate( $hash, $sreading, $tvalue ) if $function eq "bulk";
  }
  return readingsSingleUpdate( $hash, $nreading, $nvalue, $notify ) if $function eq "single";
  return readingsBulkUpdate( $hash, $nreading, $nvalue ) if $function eq "bulk"; 
}

sub HomeConnect_readingsBulkUpdate($$$) {
  my ( $hash, $reading, $value ) = @_;
  return HomeConnect_readingsUpdate($hash,$reading,$value,0,"bulk");
}

sub HomeConnect_readingsSingleUpdate($$$$) {
  my ( $hash, $reading, $value, $notify ) = @_;
  return HomeConnect_readingsUpdate($hash,$reading,$value,$notify,"single");
}

sub HomeConnect_ReadingsVal($$$) {
  my ( $hash, $reading, $default ) = @_;
  #Safety to avoid FHEM crashing during development as original ReadingsVal has a name (not a hash) as first argument
  return "error" if (ref($hash) ne "HASH");
  my $name = $hash->{NAME};

  my $nreading = HomeConnect_replaceReading( $hash, $reading );

  my $res = ReadingsVal( $name, $nreading, $default );
  $res =~ s/\s$//;    # Remove any trailing spaces
  Log3 $name, 4, "[HomeConnect_ReadingsVal] $name: $reading->$nreading : $res";
  return $res;
}

sub HomeConnect_Attr(@) {
  my ( $cmd, $name, $attrName, $attrVal ) = @_;
  my $hash = $defs{$name};

  if( $attrName eq 'logfile' ) {
    if( $cmd eq "set" && $attrVal && $attrVal ne 'FHEM' ) {
      fhem( "defmod -temporary $name\_log FileLog $attrVal Logfile|$name\.\*" );
	  CommandAttr( undef, '$name\_log room hidden' );
      $hash->{logfile} = $attrVal;
    } else {
      fhem( "delete $name\_log" );
    }
  }

  return undef;
}

#Hook up to the existing logfile - bit ugly - only for dev purposes
sub HomeConnect_FileLog($$) {
	my ($hash, $msg) = @_;
	return if (!$hash->{logfile});
	my $logdev=$defs{$hash->{NAME}."_log"};
	return if (!defined $logdev);
	$msg =~ s/homeappliances\/[0-9]+\//homeappliances\/XXXX\//mg;
	$msg =~ s/'haId' => '[0-9]+'/'haId' => 'XXXX'/mg;
	my $fh = $logdev->{FH};
	return if (!$fh);
	my @t = localtime();
    my $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d",
          $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);
	$fh->flush();
	print $fh $tim." ".$msg."\n";
}

#Wrap request, for logging purposes
sub HomeConnect_request($$) {
	my ($hash,$data) = @_;
	HomeConnect_FileLog($hash,"Request:".Dumper($data));
	HomeConnectConnection_request( $hash, $data );
}
	  
sub HomeConnect_Notify($$) {
	my ($hash, $dev_hash) = @_;
	my $ownName = $hash->{NAME}; # own name / hash
	return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled

	my $devName = $dev_hash->{NAME}; # Device that created the events
	my $events = deviceEvents($dev_hash,1);
	if ($devName eq "global" and grep(m/^INITIALIZED|REREADCFG$/, @{$events})) {
		Log3 $hash->{NAME}, 5, "[HomeConnect_Notify] called from global for $ownName";  
		my $def=$hash->{DEF};
		$def="" if (!defined $def); 
		#return HomeConnect_Init($hash);
	}
}

################################### 
sub HomeConnect_State($$$$) {			#reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
    #Log3 $hash->{NAME}, 1, "[HomeConnect_State] called";  
	return undef;
}

1;

=pod
=item device
=item summary Integration of Home Connect appliances (Siemens, Bosch)
=item summary_DE Integration von Home Connect Geräten (Siemens, Bosch)

=begin html

<h3>HomeConnect</h3>
<a id="HomeConnect"></a>
<ul>
  <a id="HomeConnect-define"></a>
  <h4>Define</h4>
  <ul>
    <code>define &lt;name&gt; HomeConnect &lt;connection&gt; &lt;haId&gt;</code>
    <br/>
    <br/>
    Defines a single Home Connect household appliance. See <a href="http://www.home-connect.com/">Home Connect</a>.<br><br>
    Example:

    <code>define Dishwasher HomeConnect hcconn SIEMENS-HCS02DWH1-83D908F0471F71</code><br>

    <br/>
	Typically the Home Connect devices are created automatically by the scanDevices action in HomeConnectConnection.<br>
	Note: <li>Not all commands will work with every device. As the interface is rather generic, it is impossible to find out what your device can actually do and how it will behave.
	So this module will rather offer an option that does not work (you will get an error message in reading "lastErr" or by popup) than hiding options that could work.</li>
	<li>Most commands are executed asynchronously, which means you will not see updated readings right away and won't get error messages displayed. Wait a bit and check the reading "lastErr" (mind the timestamp to avoid reacting on old errors)</li>
    <br/>
  </ul>

  <a name="HomeConnect-set"></a>
  <h4>Set</h4>
  <ul>
	<li><b>set SelectedProgram &lt;Program Name&gt;</b><br>
			<a id="HomeConnect-set-SelectedProgram"></a>
			Select the program for the appliance taken out of a list of possible programs that have been retrieved earlier. Typically your device also needs to be powered on to make this work.<br>
			If the list is empty it might need to be filled first with "get Programs", which might need the appliance to be switched on.<br>
			</li>
	<li><b>set StartProgram</b><br>
			<a id="HomeConnect-set-StartProgram"></a>
			Start the program that either has been selected by "set SelectedProgram" or was manually selected at the appliance.<br>
			Note that to actually start the "Remote Start" has to be enabled (manually) at the appliance<br>
			</li>
	<li><b>set StopProgram</b><br>
			<a id="HomeConnect-set-StopProgram"></a>
			Stop (abort) a running program. Highly depends on the capabilities of the appliance if this is possible and how quickly it is done.<br>
			</li>
	<li><b>set PauseProgram</b><br>
			<a id="HomeConnect-set-PauseProgram"></a>
			Pause a running program. Not all appliances will support this. Resumed with "ResumeProgram".<br>
			</li>
	<li><b>set ResumeProgram</b><br>
			<a id="HomeConnect-set-ResumeProgram"></a>
			Resume a previously paused program.<br>
			</li>
	<li><b>set PowerOn</b><br>
			<a id="HomeConnect-set-PowerOn"></a>
			Switch an appliance on. Only supported by devices that do not get fully switched off.<br>
			</li>			
	<li><b>set PowerOff</b><br>
			<a id="HomeConnect-set-PowerOff"></a>
			Power off an appliance, if supported.<br>
			</li>			
  </ul>
  <h4>Further option settings</h4>
  Further settings might appear after "Settings" or "ProgramOptions" get queried. These are created dynamically and it is impossible to document them all. Listing some special cases and ones known by the author here.<br>
  <h3>General - supported by multiple devices</h3>
  <ul>
  	<li><b>set DelayEndTime &lt;HH:MM&gt; </b><br>
			<a id="HomeConnect-set-DelayEndTime"></a>
			If device supports "startInRelative" or "finishInRelative" and device is set to "remoteStartAllowed"<br>
			Delay the start of the device, so it will likely finish at the given time.
			</li>
	<li><b>set DelayRelative &lt;HH:MM&gt; </b><br>
			<a id="HomeConnect-set-DelayRelative"></a>
			If device supports "startInRelative" or "finishInRelative" and device is set to "remoteStartAllowed"<br>
			Delays the start of the device by the specified time.
	</li>
	<li><b>set DelayStartTime &lt;HH:MM&gt; </b><br>
			<a id="HomeConnect-set-DelayStartTime"></a>
			If device supports "startInRelative" or "finishInRelative" and device is set to "remoteStartAllowed"<br>
			Delays the finish time of the device by the specified time.
	</li>
  </ul>
  <h3>Device specific</h3>
  <ul>
	<li><b>Dryer:</b> DryingTarget</li>
	<li><b>Washer:</b> </li>
	<li><b>Dishwasher:</b> </li>
  </ul>
  <a name="HomeConnect_Get"></a>
  <h4>Get</h4>
  <ul>
	<li><b>get Settings</b><br>
			<a id="HomeConnect-get-Settings"></a>
			Retrieve the available general settings, e.g. things like "ChildLock". It is recommended that you device is turned on when your query this, though especially newer devices will also return data when switched off or in standby.<br>
			</li>
	<li><b>get Programs</b><br>
			<a id="HomeConnect-get-Programs"></a>
			Retrieve the list of available programs, e.g. things like "Eco50","Cotton" etc. It is recommended that you device is turned on when your query this, though especially newer devices will also return data when switched off or in standby.<br>
			</li>
	<li><b>get ProgramOptions</b><br>
			<a id="HomeConnect-get-ProgramOptions"></a>
			Retrieve the list of program specific options for the currently selected program. Your device should be switched on and set to the appropriate program to make this work properly.<br>
			</li>
  </ul>
  <a name="HomeConnect_Attr"></a>
  <h4>Attributes</h4>
  <ul>
	<li><b>updateTimer &lt;Integer&gt;</b><br>
			<a id="HomeConnect-attr-updateTimer"></a>
			Define how often checks are executed - default is 10 seconds.<br>
			</li>
	<li><b>namePrefix &lt;Integer&gt;</b><br>
			<a id="HomeConnect-attr-namePrefix"></a>
			The Home Connect interface uses pretty long and complicated names for it's settings, e.g. BSH.Common.Setting.PowerState.<br>
			By setting this to 1 these prefixes are fully preserved and the readings created are equally long.<br>
			If set to 0 (default) the module will cut away the "BSH.Common" to make this more readable. When communicating with Home Connect the module will internally continue to use the full name.<br>
			</li>
	<li><b>valuePrefix &lt;Integer&gt;</b><br>
			<a id="HomeConnect-attr-valuePrefix"></a>
			The Home Connect interface uses pretty long and complicated names for values settings, e.g. BSH.Common.EnumType.DoorState.Open.<br>
			By setting this to 1 these prefixes are fully preserved and the values are displayed as such.<br>
			If set to 0 (default) the module will cut away everything, but the actual value ("Open" in the example). When communicating with Home Connect the module will internally continue to use the full name.<br>
			</li>
	<li><b>translate &lt;Reading List&gt;</b><br>
			<a id="HomeConnect-attr-translate"></a>
			"Readings List" is a comma separated list of reading names (without any prefixes, so e.g. "DoorState").<br>
			For every of those readings, a new readings will be created without prefixes (so for "Status.DoorState" gets copied to "DoorState").<br>
			The new reading values will not have any units (so things like "seconds" or "%" will be removed). If the language in "global" is set to "DE", FHEM will attempt to translate the values to German using an internal table.
			</li>
	<li><b>logfile &lt;Filename&gt;</b><br>
			<a id="HomeConnect-attr-logfile"></a>
			For development purposes: A temporary logfile device will be created and logs all FHEM events plus all API calls and responses/events (JSON)
			</li>
  </ul>
</ul>

=end html
=cut

########################################################################################
#
# 48_HomeConnect.pm
#
# Bosch Siemens Home Connect Module for FHEM
#
# Stefan Willmeroth 09/2016
# Major rebuild Prof. Dr. Peter A. Henning 2023
# Major re-rebuild by Adimarantis 2024/2025
my $HCversion = "1.19";
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
use HomeConnectConf;

# Import configuration data
my $HomeConnect_Translation = \%HomeConnectConf::HomeConnect_Translation;
my $HomeConnect_Iconmap = \%HomeConnectConf::HomeConnect_Iconmap;
my $HomeConnect_DeviceDefaults; # Set directly to the right type in HomeConnect_ResponeInit()

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
	. "excludeSettings: "
	. "extraOptions: "
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

  my $hcc=$defs{ $hash->{hcconn} };
  return "[HomeConnect_Define] HomeConnectConnection device $a[2] not found" if !defined( $hcc );
  return undef if $hcc->{STATE} ne "Connected";

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

  $hash->{STATE}="Initializing, please wait";
  $hash->{helper}->{init}="start";
  #Set the most important settings from hidden readings and defaults to avoid fatal errors when API calls fail
  my $type=ReadingsVal($name,".type",undef);
  my $prefix=ReadingsVal($name,".prefix",undef);

  $hash->{type}=$type if ($type and !defined($hash->{type}));
  $hash->{prefix} = $prefix if ($prefix and !defined($hash->{prefix}));

  HomeConnect_CloseEventChannel($hash);
  RemoveInternalTimer($hash);
  #Keep a counter to avoid potential endless loop
  $hash->{helper}->{init_count}=0;

  $hash->{helper}->{init}=0;		#Init/ResponseInit
  $hash->{helper}->{status}=-1;		#UpdateStatus/ResponseUpdateStatus
  $hash->{helper}->{settings}=-1;	#GetSeeings/ResponseGetSettings
  $hash->{helper}->{programs}=-1;	#GetPrograms/ResponeGetPrograms
  $hash->{helper}->{options}=-1;		#GetProgramOptions/ResponseGetProgramOptions
  $hash->{helper}->{details}=-1;		#CheckProgram/ResponseCheckProgram
  $hash->{offline}=0;		#Set to 1 if offline error
  $hash->{helper}->{clear}=-1;
    
  delete $hash->{data}->{sets}; #Make sure this gets reset on init

  #-- Read list of appliances, find my haId
  my $data = {
	callback => \&HomeConnect_ResponseInit,
	uri      => "/api/homeappliances"
  };
  HomeConnect_Request( $hash, $data );
  my $scope = ReadingsVal($hash->{hcconn},"accessScope","unknown");
  HomeConnect_FileLog($hash,"accessScope: ".$scope);

  InternalTimer( gettimeofday() + int(rand(5))+1, "HomeConnect_InitWatcher", $hash, 0 );
}

#Flow {helper}->{<flag>} =-1 Not requested =0 Requested =1 finished
# init=1  		/api/homeappliances 				Init/ResponseInit 					Get list of all connected devices and identify type, prefix etc. for current device
#				type,brand,vib,haID,enumber,name,connected for all devices, need to identify by haID which data belongs to this device
# settings=1	/api/homeappliances/{haId}/settings	PowerState, Childlock - should be updated by Event after initial update
# status=1		/api/homeappliances/{haId}/status	UpdateStatus/ResponseUpdateStatus	Get general status unformation. All this should get updated by events. Only call at Init
#				RemoteControlStartAllowed,RemoteControlActive,DoorState,OperationState
# programs=1 	/api/homeappliances/{haId}/programs 			Get list of all available, selected and active programs, might fail if device is offline for some devices
#				selected section: Only for selected program (if any): options []: key, value, (unit)	-> Fill SelectedProgram on Startup
#				active section: Only for running program (if any): options []: key, value, (unit)		-> Fill ActiveProgram on Startup
#				programs section: All available programs (except Favorite): key, constraints (execution=selectandstart, available=???)
#				Flow:	-Trigger on startup, if "offline" keep 0
#						-PowerState=on and =0 -> Trigger again
# options=1		/api/homeappliances/{haId}/programs/available/{prg} options[]: key/constraints (min,max,default)/unit/type/liveupdate
#				This is the only call that gives real settings and their details and should only contain options valid in the current state
#				Flow:	Needs to be called when a program gets selected or starts running to determine the right "set" list for options
#				Should reset the {data}->{values} section
# details=1 	/api/homeappliances/{haId}/programs/selected	options[]: 	key/value 		: Just information like ProgramName, BaseProgram
#																			key/value/unit	: Info with type like StartInRelative, EnergyForecast, WaterForecast, RemainingProgramTime*
#																			key/value (bool): Certain real options that can be set, no guarantee they're all valid
#				/api/homeappliances/{haId}/programs/active		Same as above for active program
#				Flow: Call in addition to options as it gives more details about the current status. Content identical to selected/active section in GetPrograms
#				Fill the {data}->{values} section

sub HomeConnect_InitWatcher($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if (!defined($hash->{helper}->{init})); #Not ready
  return if ($hash->{helper}->{init_count}>10); #Fatal error, don't do anything else
  
  HomeConnect_FileLog($hash, "Init Watch loop $hash->{helper}->{init_count} ".
							$hash->{helper}->{init}."/".$hash->{helper}->{settings}."/".$hash->{helper}->{status});

  HomeConnect_Init($hash) if ($hash->{helper}->{init} == -1);
  #All these calls might not work if device is offline - do not try again on offline error
  HomeConnect_GetSettings($hash) if ($hash->{helper}->{init} == 1 and $hash->{helper}->{settings} == -1 and !$hash->{offline});
  HomeConnect_UpdateStatus($hash) if ($hash->{helper}->{settings} == 1 and $hash->{helper}->{status} == -1 and !$hash->{offline});

  $hash->{helper}->{init_count}++;

  my $done=0;
  $done=1 if ($hash->{helper}->{init} == 1 and $hash->{offline}); # A device that's offline cannot do more
  $done=1 if ($hash->{helper}->{status} == 1); # Programs will be checked in normal Timer

  # Check updates more frequently
  if (!$done) {
    RemoveInternalTimer($hash);
	InternalTimer( gettimeofday() + int(rand(5))+1, "HomeConnect_InitWatcher", $hash, 0 );
  } else {
	HomeConnect_FileLog($hash, "Init Watch done");
    RemoveInternalTimer($hash);
	HomeConnect_Timer($hash);
  }
}

###############################################################################
#
#   responseInit
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
	$msg = "[HomeConnect_ResponeInit] $name JSON error requesting appliances: Probably a connection timeout. Check connection to Home Connect Server and try again.";
	$hash->{helper}->{init}=-1; #Reset flag for retry
	Log3 $name, 1, $msg;
	return $msg;
  }
  HomeConnect_FileLog($hash,"responseInit:".Dumper($appliances));

  my $arr=$appliances->{data}->{homeappliances};
  my $appliance;
  foreach (@$arr) {
	if ($hash->{haId} eq $_->{haId}) {
      $appliance=$_;
	  last;
	}
  }

  if (!$appliance) {
    $hash->{helper}->{init}="error";
	Log3 $name, 3, "[HomeConnect_ResponseInit] $name: specified appliance with haId $hash->{haId} not found";
	HomeConnect_readingsSingleUpdate($hash,"lastErr","Appliance $hash->{haId} not found",1);
	return;
  }
  $hash->{aliasname} = $appliance->{name};
  my $type = $appliance->{type};
  $hash->{type}      = $type;
  readingsSingleUpdate($hash,".type",$type,0) if ($type); #Save type in hidden reading
  $hash->{brand}     = $appliance->{brand};
  $hash->{vib}       = $appliance->{vib};
  $hash->{offline} = ($appliance->{connected})?0:1; #Convert from JSON Boolean Type
  Log3 $name, 3, "[HomeConnect_ResponseInit] $name: defined as HomeConnect $hash->{type} $hash->{brand} $hash->{vib}";
  $hash->{helper}->{init}=1;

  $HomeConnect_DeviceDefaults=\%{$HomeConnectConf::HomeConnect_DeviceDefaults{$type}};

  my $icon = $HomeConnect_Iconmap->{$appliance->{type}};
  $attr{$name}{icon} = $icon if (!defined $attr{$name}{icon} && !defined $attr{$name}{devStateIcon} && defined $icon);
  $attr{$name}{stateFormat} = "state1 (state2)" if !defined $attr{$name}{stateFormat};

  $attr{$name}{alias} = $hash->{aliasname} if ( !defined $attr{$name}{alias} && defined $hash->{aliasname} );

  #Some general static initialization, now we know the type
  my $isDE = ( AttrVal( "global", "language", "EN" ) eq "DE" );
  my $prefix=$HomeConnect_DeviceDefaults->{prefix};
  $hash->{prefix} = $prefix;
  readingsSingleUpdate($hash,".prefix",$prefix,0) if ($prefix); #Save type in hidden reading

  if ( defined $HomeConnect_DeviceDefaults->{events} ) {
	$hash->{events} = join( ',', @{ $HomeConnect_DeviceDefaults->{events} } );
  } else {
	$hash->{events} = "";
  }

  my @dp=(keys %{$HomeConnect_DeviceDefaults->{programs_DE}});
  HomeConnect_FileLog($hash,"Defaultprograms:".join(",",@dp));
  my $int=ReadingsVal($name,".programs","");
  HomeConnect_FileLog($hash,".programs:".$int);
  #If no programs are set, try to get it from hidden reading
  if (!$hash->{programs} or $hash->{programs} eq "") {
	 if ($int) { #Take internal reading
		$hash->{programs}=$int;
	 } else {
		 #Get from hardcoded defaults
		$hash->{programs}=join(",",@dp);
	}
  }

  $hash->{data}->{finished} = $HomeConnect_DeviceDefaults->{finished};
  
  $hash->{data}->{poweroff} = $HomeConnect_DeviceDefaults->{poweroff}
	if ( defined $HomeConnect_DeviceDefaults->{poweroff} );

  $hash->{data}->{trans} = $HomeConnect_DeviceDefaults->{programs_DE}
	if ( defined $HomeConnect_DeviceDefaults->{programs_DE} && $isDE );
	
  foreach my $key (keys %{$HomeConnect_DeviceDefaults->{programs_DE}}) {
	$hash->{data}->{retrans}->{$HomeConnect_DeviceDefaults->{programs_DE}->{$key}}=$key;
  }
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
  return if ( !defined $data or length($data) == 0 );

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
		if ($desc) {
			my $key=$jhash->{"error"}->{"key"};
			if ($key =~ /SDK.Error.UnsupportedSetting/ or 
			    $key =~ /SDK.Error.UnsupportedOption/ or 
				$key eq "404" or 
				$key eq "insufficient_scope") {  
			    #Unfortunately the API returns 'SDK.Error.UnsupportedSetting' for both the API call and the setting itself
				#So checking the description is the only way to distinguish
				#Remembering that a setting does not work, so we can exclude it in future. Doing it in an attribute lets users revert that decision
				#key "404" indicates e.g. that command is not supported ("The requested resource could not be found")
				#key "insufficient_scope" indicates that this is (currently) not possible via API
 				HomeConnect_AddExclude($name,$path);
				$hash->{helper}->{details}=-1; #Check Program State again, so incorrectly changed readings get corrected
			} elsif ($key =~ /SDK.Error.UnsupportedCommand/) {
				#Same for commands, some commands do not work for specific models (e.g. PauseProgram)
				HomeConnect_AddExclude($name,$1);
		    }
		}
		HomeConnect_HandleError($hash,$jhash);
	}
	return;
}

sub HomeConnect_AddExclude($$) {
  my ($name,$exclude) = @_;
  my $exAttr=$attr{$name}{"excludeSettings"};
  if (defined $exAttr and $exAttr ne "") {
	$exAttr =~ s/,/\$|^/m;
	$exAttr = "^".$exAttr."\$";
	$attr{$name}{"excludeSettings"}.=",".$exclude if ($exAttr !~ /$exclude/);
  } else {
	$attr{$name}{"excludeSettings"}=$exclude;
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
    HomeConnect_FileLog($hash,"Error:".Dumper($jhash));
	$error = $jhash->{"error"}->{"description"};
	Log3 $name, 1, "[HomeConnect_HandleError] $name: Error \"$error\""
	  if $error;
	readingsSingleUpdate( $hash, "lastErr", $error, 1 );
	
	if ( $error =~ /offline/ ) {

	  #-- key SDK.Error.HomeAppliance.Connection.Initialization.Failed
	  HomeConnect_readingsSingleUpdate( $hash, "BSH.Common.Status.OperationState", "Offline", 1 );
	  $hash->{STATE} = "Offline";
	  $hash->{offline} = 1;
	  HomeConnect_readingsSingleUpdate($hash,"BSH.Common.Setting.PowerState","Off",1);
	  #In offline case, the initalization should just continue to next stage
	  HomeConnect_CheckState($hash);
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

  my $haId = $hash->{haId};
  my $name = $hash->{NAME};
  my $type = $hash->{type};

  my $opts = join @a;

#--connect to Home Connect server, initialize status ------------------------------
  if ( $a[1] eq "init" ) {
	Log3 $hash->{NAME}, 3, "[HomeConnect_Set] init called";  
	InternalTimer( gettimeofday() + int(rand(10))+5, "HomeConnect_Init", $hash, 0 );
	return;
  }
  return if !defined $hash->{prefix};    #Init not complete yet
										 #-- update debug setting
										 #$HC_debug = AttrVal($name,"debug",0);

  #-- prefixes
  my $programPrefix = $hash->{prefix} . ".Program.";
  my $optionPrefix  = $hash->{prefix} . ".Option.";
  my $excludes = $attr{$name}{"excludeSettings"};
  $excludes="" if !defined $excludes;
  $excludes =~ s/,/\$|^/g;
  $excludes = "^".$excludes."\$";

  my $pwchoice="";
  #-- PowerOn not for Hob, Oven and Washer
  if ( $type !~ /(Hob)|(Oven)|(Washer$)/ ) {
	$pwchoice="On";
  }

  my @cmds;
  #disable debug stuff: push (@cmds,"ZZZ_Dump:noArg anyRequest:textField");
  
  #-- PowerOff not for Hob, Oven
  if ( defined( $hash->{data}->{poweroff} ) ) {
    $pwchoice.="," if $pwchoice ne "";
    $pwchoice.="Standby" if $hash->{data}->{poweroff} =~ /Standby/;
    $pwchoice.="Off" if $hash->{data}->{poweroff} =~ /Off/;
	push(@cmds,"Power:".$pwchoice);
  }

  if ( $type =~ /(Hood)|(Dishwasher)/ ) {
	push(@cmds,"AmbientLightCustomColor:colorpicker,RBG") if ("AmbientLightCustomColor" !~ /$excludes/);
  }
  
  if ( $type =~ /(Fridge)|(Freezer)|(Refrigerator)/ ) { #+Oven?
	my $da1=HomeConnect_ReadingsVal($hash,"Refrigeration.Common.Setting.Door.AssistantFridge","Off");
	my $da2=HomeConnect_ReadingsVal($hash,"Refrigeration.Common.Setting.Door.AssistantFreezer","Off");
	if ($da1 eq "On" or $da2 eq "On") {
		push(@cmds,"OpenDoor:noArg") if ("OpenDoor" !~ /$excludes/);
	}
  }
  
  #-- programs taken from hash or empty
  my $programs = $hash->{programs};
  $programs = "" if !defined($programs);
  #Translate pulldown options if translation table present
  if ($hash->{data}->{trans}) {
	foreach my $tr (keys %{$hash->{data}->{trans}}) {
		$programs =~ s/$tr/$hash->{data}->{trans}->{$tr}/;
	}
  }
  $programs = decode_utf8($programs) if ($unicodeEncoding);
  $programs =~ s/ /_/g; #Safety measure to remove accidential spaces in programnames
  
  my $operationState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.OperationState", "" );
 
 #Do not count DelayedStart as "running" as it is required to "StartProgram" when the delay is changed
  my $pgmRunning = $operationState =~ /((Active)|(Run)|(Pause))/;
  my $remoteStartAllowed=HomeConnect_ReadingsVal($hash,"BSH.Common.Status.RemoteControlStartAllowed","Off");
  $remoteStartAllowed=($remoteStartAllowed eq "On"?1:0);

#-- no programs for freezers, fridge freezers, refrigerators and wine coolers
#   and due to API restrictions, wwe may also not set the programs for Hob and Oven
  if ( $hash->{type} !~ /(Hob)|(Oven)|(Fridge)|(Freezer)|(Refrigerator)|(Wine)/ ) {
	push(@cmds,"StopProgram:noArg") if ($operationState =~ /((Active)|(Run)|(Pause)|(DelayedStart))/);
	push(@cmds,"PauseProgram:noArg") if ($operationState =~ /((Active)|(Run))/ and "PauseProgram" !~ /$excludes/);
	push(@cmds,"ResumeProgram:noArg") if ($operationState =~ /(Pause)/);

	push(@cmds,"StartProgram:noArg") if ($remoteStartAllowed and $operationState =~ /(Ready)|(Inactive)/);

	push(@cmds,"SelectedProgram:$programs") if ($operationState =~ /(Ready)|(Inactive)/);;
  }

#-- available options and settings ------------------------------------------------------------------------
  my $availableOpts=""; #Keep options/settings separated from cmds as it is used to identify command later

  if ( defined( $hash->{data}->{options} ) ) {
	foreach my $key ( keys %{ $hash->{data}->{options} } ) {
	  if ($key !~ /$excludes/ and defined($hash->{data}->{sets}->{$key})) { #Only keys with current values can be set
		  #-- special key for delayed start
		  if ( $key =~ /((StartInRelative)|(FinishInRelative))/ ) {
			push(@cmds,"DelayStartTime:time DelayEndTime:time DelayRelative:time") if $remoteStartAllowed;
		  } else {
			my $values=$hash->{data}->{options}->{$key}->{values};
			$availableOpts .= $key;
			$availableOpts .= ":".$values if $values;
			$availableOpts .= " ";
		  }
		}
	}
  }
  
  if ( defined( $hash->{data}->{settings} ) ) {
	foreach my $key ( keys %{ $hash->{data}->{settings} } ) {
	  if ($key !~ /$excludes/) {
		  #-- special key for Power on/off
		  if ( $key =~ /(PowerState)/ ) {
			#Add the powerstate code from above here
		  } elsif ( $key =~ /([a-zA-Z\.]*)AlarmClock/ ) { #$1 will become something like "Door"
		    push(@cmds,"$1AlarmRelative:time $1AlarmEndTime:time $1AlarmCancel:noArg");
		    #Ignore here as this was added above already - TODO: can this be done better? Need some API logs....
		  } else {
			$availableOpts .= $key;
			my $values=$hash->{data}->{settings}->{$key}->{values};
			$availableOpts .= ":".$values if $values;
			$availableOpts .= " ";
		  }
		}
	}
  } 
  
  return "[HomeConnect_Set] $name: no set value specified" if ( int(@a) < 2 );
  push(@cmds,$availableOpts);
  return join(" ",@cmds) if ( $a[1] eq "?" );

  #-- read some conditions
  my $program = HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.SelectedProgram", "" );
  my $powerState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.PowerState", "" );
  my $powerOff = ( ( $powerState =~ /Off/ ) || ( $operationState =~ /Inactive/ ) );
  my $doorState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.DoorState", "" );
  my $doorOpen = ( $doorState =~ /Open/ );

  #-- doit !
  shift @a;
  my $command = shift @a;
  HomeConnect_FileLog($hash,"set $command ".join(" ",@a));
  Log3 $name, 3, "[HomeConnect] $name: set command: $command";

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
  elsif ( $command =~ /AmbientLight/ ) {
	HomeConnect_SetAmbientColor($hash,$a[0]);
  }
  elsif ( $command =~ /anyRequest/ ) {
	HomeConnect_AnyRequest($hash,join(" ",@a));
  }
  elsif ( $command =~ /Power/ ) {
    return if (!$a[0]);
    my $pwcmd=$command.$a[0];
	$pwcmd =~ s/Power//;
	$pwcmd =~ s/Off/MainsOff/ if $hash->{data}->{poweroff} eq "MainsOff";
	HomeConnect_PowerState( $hash, $pwcmd );

	#-- DelayTimer-----------------------------------------------------
  }
  elsif ( $command =~ /(DelayRelative)|(DelayStartTime)|(DelayEndTime)|(DelayFinishAt)/ )
  {
	#return "[HomeConnect] $name: cannot set delay timer, device powered off"
	#  if (!$powerOn);
	HomeConnect_DelayTimer( $hash, $command, $a[0], $a[1] );

	#-- AlarmClock -----------------------------------------------------
  }
  elsif ( $command eq "AlarmCancel" ) {
	HomeConnect_AlarmCancel($hash);

  }
  elsif ( $command =~ /(AlarmRelative)|(AlarmEndTime)/ ) {
	HomeConnect_AlarmTimer( $hash, $command, $a[0] );

	#-- start current program -------------------------------------------------
  }
  elsif ( $command =~ /StartX/) {
	return HomeConnect_StartProgram2($hash,$a[0]);
  }
  elsif ( $command =~ /(s|S)tart(p|P)rogram/ ) {

	#return "[HomeConnect_Set] $name: cannot start, device powered off"
	#  if (!$powerOn);
	return "[HomeConnect_Set] $name: a program is already running"
	  if ($pgmRunning);
	return "[HomeConnect_Set] $name: please enable remote start on your appliance to start a program"
	  if ( !$remoteStartAllowed );
	return "[HomeConnect_Set] $name: cannot start, door open"
	  if ($doorOpen);
	return HomeConnect_StartProgram($hash);

  #--basic command without arguments------------------------------------------------------
  }
  elsif ( $command =~ /(PauseProgram)|(ResumeProgram)|(OpenDoor)/ ) {
	return HomeConnect_SendCommand($hash,$command);
   #--stop current program------------------------------------------------------
  }
  elsif ( $command =~ /(s|S)top(p|P)rogram/ ) {
	return "[HomeConnect_Set] $name: cannot stop, no program is running"
	  if ( !$pgmRunning and $operationState !~ /(DelayedStart)/);
	my $data = {
	  callback => \&HomeConnect_Response,
	  uri      => "/api/homeappliances/$haId/programs/active"
	};
	HomeConnectConnection_delrequest( $hash, $data );
	HomeConnect_FileLog($hash,"Stopping Program:".Dumper($data));

  #-- set options, update current program if needed ----------------------------
  }
  elsif ( index( $availableOpts, $command ) > -1 ) {
	my $optval  = shift @a;
	my $optunit = shift @a;
	if ( !defined $optval ) {
	  return "[HomeConnect_Set] $name: please enter a new value for option $command";
	}

	if ($hash->{data}->{options}->{$command}) {
	  return HomeConnect_SendSetting($hash,"options",$command,$optval,$optunit);
	} elsif ($hash->{data}->{settings}->{$command}) {
	  return HomeConnect_SendSetting($hash,"settings",$command,$optval,$optunit);
	} else {
	  return "[HomeConnect_Set] $name: invalid command $command";
    }
    return;
 #-- select a program ----------------------------------------------------------
  }
  elsif ( $command =~ /(s|S)elect(ed)?Program/ ) {

	#return "[HomeConnect_Set] $name: cannot select program, device powered off"
	#  if (!$powerOn);
	my $program = shift @a;

	#-- trailing space ???
	$program =~ s/\s$//;
	Log3 $name, 3, "[HomeConnect_Set] command to select program $program";

	if ( ( !defined $program )
	  || ( $programs ne "" && index( $programs, $program ) == -1 ) )
	{
	  return "[HomeConnect_Set] $name: unknown program $program, choose one of $programs";
	}
	
	#Translate back to get a valid program
	if ($hash->{data}->{retrans}) {
		$program = encode_utf8($program) if ($unicodeEncoding);
		$program=$hash->{data}->{retrans}->{$program} if $hash->{data}->{retrans}->{$program};
	}

	#Dishwasher favorites use "Common" prefix
	if ( $program =~ /Favorite.*/ ) {
	  $programPrefix = "BSH.Common.Program.";
	  return "Selecting/Starting a Favorite is currently not supported by the Home Connect API";  
      HomeConnect_readingsSingleUpdate($hash,"BSH.Common.Setting.SelectedProgram","BSH.Common.Program.".$program,1);
	}

	my $data = {
	  callback => \&HomeConnect_Response,
	  uri      => "/api/homeappliances/$haId/programs/selected",
	  data     => "{\"data\":{\"key\":\"$programPrefix$program\"}}"
	};

	Log3 $name, 3, "[HomeConnect] selecting program $program with uri " . $data->{uri} . " and data " . $data->{data};
	HomeConnect_Request( $hash, $data );
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
  my $gets     = "Settings:noArg Status:noArg";
  my $type     = $hash->{type};
  return if !$type; # Device not ready yet
  if ( $type !~ /FridgeFreezer/ ) {
	$gets .= " Programs:noArg ProgramOptions:noArg ProgramStatus:noArg";
  }
  return "[HomeConnect_Get] $name: with unknown argument $cmd, choose one of " . $gets
	if ( $cmd eq "?" );

  HomeConnect_FileLog($hash,"get ".join(" ",@args));

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
#-- Request status update ----------------------------------------------------
  }
  elsif ( $cmd eq "Status" ) {
	return HomeConnect_UpdateStatus($hash);
  }
  elsif ( $cmd eq "ProgramStatus" ) {
	return HomeConnect_CheckProgram($hash);
  }
}

sub HomeConnect_AnyRequest($$) {
  my ($hash, $string) = @_;
  
  my $data = {
	callback => \&HomeConnect_ResponseAny,
	uri  => "/api/homeappliances/$hash->{haId}/$string",
  };
  HomeConnect_Request( $hash, $data );
}

sub HomeConnect_ResponseAny() {
  my ( $hash, $data, $path ) = @_;
  HomeConnect_FileLog($hash,"Reply $path: $data");
}

sub HomeConnect_SendSetting($$$$$) {
  my ($hash, $area, $command, $value, $unit) = @_;
  my $name=$hash->{NAME};
  my $def=\%{$hash->{data}->{$area}->{$command}};
  my $type=$def->{type};
	
  my $json=HomeConnect_MakeJSON($hash,$def,$value);
  return $json if ($json !~ /{.*}/); #Got error instead of JSON
  $json = "{\"data\":".$json."}"; 
  my $path=$area;
  #-- for selected program use "programs/selected"
  #   for active program use programs/active
  my $operationState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.OperationState", "" );
  my $pgmRunning = $operationState =~ /((Active)|(Run)|(Pause))/;
  if ($area eq "options") {
	my $choice     = "selected";
	my $liveupdate = $hash->{data}->{options}->{$command}->{update};
    if ( $pgmRunning && defined($liveupdate) && $liveupdate eq "1" ) {
	  $choice = "active";
    }
	$path="programs/$choice/options";
  }

  my $data = {
	callback => \&HomeConnect_Response,
	uri  => "/api/homeappliances/$hash->{haId}/$path/$def->{name}",
	data => $json
  };
  Log3 $name, 3, "[HomeConnect_SendSetting] changing $area with uri " . $data->{uri} . " and data " . $data->{data};
  HomeConnect_Request( $hash, $data );
  HomeConnect_readingsSingleUpdate($hash,$def->{name},$value,1); #Assume this works, thus update reading
  return undef;
}

#Create a JSON for request
sub HomeConnect_MakeJSON($$$) {
  my ($hash,$def,$value,$dt) = @_;
  
  my $type=$def->{type};
  $type="undef" if !$type; #If no type skip all conversions and checks
  my $values=$def->{values}; #Make a pattern of the value list
  $type = "Boolean" if ($type eq "undef" and $values =~ /(o|O)n,(o|O)ff/);
  if ($values) {
	$values =~ s/,/\$|^/g;
	$values = "^".$values."\$";
  }
  $value =~ s/ $def->{unit}// if $def->{unit};
  if ($type =~ /Int/ or $type =~ /Double/) {
    return "Value too small, must be >$def->{min}" if ($def->{min} and $value<$def->{min});
    return "Value too large, must be <$def->{max}" if ($def->{max} and $value>$def->{max});
  } elsif ($type =~ /Bool/) {
	$value = ( $value =~ /1|((o|O)n)/ ) ? "true" : "false" ;
  } elsif ($type =~ /(E|e)num/) { #EnumType
    return "Unknown value" if ($def->{values} and $value !~ /$values/);
	$value = "\"".$def->{type}.".".$value."\"";
  }

  my $json = "{\"key\":\"$def->{name}\",\"value\":$value";
	$json .= ",\"unit\":\"$def->{unit}\"" if ( defined $def->{unit} );
	$json .= "}";
  if (!$unicodeEncoding) {#httputils will throw an internal error on "°C" otherwise
	$json=~ s/\x{c2}//g; #Special hack - just encode will be incorrect and not accepted by API
    $json=encode_utf8($json);
  }
  return $json;
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

  if ( $target !~ /^((On)|(Off)|(Standby)|(MainsOff))$/ ) {
	return "[HomeConnect_PowerState] $name: called with wrong argument $target";
  }
  else {
	Log3 $name, 3, "[HomeConnect_PowerState] $name: setting PowerState->$target while OperationState=$operationState and PowerState=$powerState";
  }

  #-- send the update
  my $json = "{\"data\":{\"key\":\"BSH.Common.Setting.PowerState\",\"value\":\"BSH.Common.EnumType.PowerState.$target\"}}";
  my $data = {
	callback => \&HomeConnect_Response,
	uri => "/api/homeappliances/$haId/settings/BSH.Common.Setting.PowerState",
	timeout => 90,
	data    => $json
  };
  HomeConnect_Request( $hash, $data );
  #Update reading as some devices don't send an update when switching off
  HomeConnect_readingsSingleUpdate($hash,"BSH.Common.Setting.PowerState","Off",1) if $target =~ /Off/;
}

###############################################################################
#
#   Routines for AlarmClock
#
###############################################################################

sub HomeConnect_AlarmCancel {
  my ($hash) = @_;
  my $haId = $hash->{haId};

  #-- send the update
  my $json = "{\"key\":\"BSH.Common.Setting.AlarmClock\",\"value\":0}";
  my $data = {
	callback => \&HomeConnect_Response,
	uri  => "/api/homeappliances/$haId/settings/BSH.Common.Setting.AlarmClock",
	data => "{\"data\":$json}"
  };
  HomeConnect_Request( $hash, $data );
}

sub HomeConnect_AlarmTimer($$$) {
  my ( $hash, $command, $value ) = @_;

  my $name = $hash->{NAME};
  my $haId = $hash->{haId};

  my $secs;

  #-- value is always in minutes or hours:minutes
  if ( $value =~ /((\d+):)?(\d+)/ ) {
	$secs = $2 * 3600 + 60 * $3;
  }
  else {
	Log3 $name, 1, "[HomeConnect] $name: error, input value $value is not a time spec";
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
  HomeConnect_Request( $hash, $data );
}

###############################################################################
#
#   Routines for delayed start
#
###############################################################################

sub HomeConnect_DelayTimer($$$$) {
  my ( $hash, $command, $value, $start ) = @_;

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
	return "[HomeConnect_DelayTimer] $name: error, input value $value is not a time spec";
  }
  Log3 $name, 3, "[HomeConnect_DelayTimer] $name: requested Delay $secs ($thour:$tmin)";

  #-- how long does the selected program run
  my $delta;

  #-- do we start in relativ or finish in relative
  my $delstart = defined( $hash->{data}->{options}->{"StartInRelative"} );
  my $delfin   = defined( $hash->{data}->{options}->{"FinishInRelative"} );
  delete $hash->{helper}->{delayedstart};

  #- device has option StartInRelative
  if ($delstart) {
	$delta = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.RemainingProgramTime", 0 );
	
	$delta =~ s/\D+//g;    #strip " seconds"
						   #-- device has option FinishInRelative
  }
  elsif ($delfin) {
    my $estimate = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.EstimatedTotalProgramTime", 0 );
	$delta = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.FinishInRelative", 0 );
	$delta =~ s/\D+//g;    #strip " seconds"
	$estimate =~ s/\D+//g;    #strip " seconds"
	#$delta=13500;
	#Prioritize the estimate as FinishInRelative might not be set correctly if device uses the estimate
	$delta = $estimate if ($estimate ne "0" or $delta eq "0");
  }
  else {
	return "[HomeConnect_DelayTimer] $name: error, device has neither startInRelative nor finishInRelative";
  }
  $delta = 0 if !looks_like_number($delta);

  Log3 $name, 5, "[HomeConnect_DelayTimer] $name: program time is $delta";
  if ( $delta <= 60 ) {
	return "[HomeConnect_DelayTimer] $name: error, no program seleced";
  }
  HomeConnect_FileLog($hash,"$command $value $delta");

  my $operationState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.OperationState", "" );
  if ($operationState =~ /DelayedStart/) {
	  #if device is already in DelayedStart, program needs to be stopped first
	  my $data = {
	  callback => \&HomeConnect_Response,
	  uri      => "/api/homeappliances/$haId/programs/active"
	  };
	  $hash->{helper}->{autostart}=1;
	  HomeConnectConnection_delrequest( $hash, $data );
	  HomeConnect_FileLog($hash,"Stopping current program to restart with delay $command $value");
	  #Remember the desired setting as "stopProgram" will reset StartInRelative to 0
	  #Once stop is confirmed (opeationState == Ready) the ReadEventChannel will set autostart to 2 and call this function again
	  $start="start"; #if already in delayedstart, start again right away
	  $hash->{helper}->{delay}=join(",",$command,$value,$start);
	  return;
  }

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

  $hash->{helper}->{delayedstart}=1 if ($delstart or $delfin);

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
	#-- device has option FinishInRelative
  }
  else {
	my $h = int( $endinrelative / 3600 );
	my $m = ceil( ( $endinrelative - 3600 * $h ) / 60 );
	readingsBeginUpdate($hash);
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishInRelative", sprintf("%i seconds",$endinrelative) );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishInRelativeHHMM", sprintf( "%d:%02d", $h, $m ) );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartAtHHMM", $starttime );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishAtHHMM", $endtime );
	readingsEndUpdate( $hash, 1 );
  }
  HomeConnect_StartProgram($hash) if (defined $start and $start eq "start");
}

###############################################################################
#
#   startProgram
#
###############################################################################

sub HomeConnect_StartProgram($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $ret;

  my $programPrefix = $hash->{prefix} . ".Program.";
  $hash->{helper}->{autostart}=0;
  
  my $programs = $hash->{programs};
  if ( !defined($programs) || $programs eq "" ) {
	$ret = "[HomeConnect_StartProgram] $name: Cannot start, list of programs empty";
	Log3 $name, 1, $ret;
	return $ret;
  }
  my $program =	HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.SelectedProgram", undef );
  $program =~ s/.*Program\.//;

  #-- trailing space ???
  $program =~ s/\s$//;

  if ( !defined $program || index( $programs, $program ) == -1 ) {
	$ret = "[HomeConnect_StartProgram] $name: Cannot start, unknown program $program, choose one of $programs";
	Log3 $name, 1, $ret;
	return $ret;
  }

  my @optdata;

  foreach my $key ( keys %{ $hash->{data}->{options} } ) {

#Verstehe ich das richtig das nur optionen ohne liveupdate beim start program übertragen werden?
#Also nur die delayedstart sachen?

#-- liveupdate? Then this must not be included in the start code
#   TODO: REALLY ?? NO, WRONG !! StartInRelative can no longer be set separately!
	next
	  if ( defined( $hash->{data}->{options}->{$key}->{update} )
	  && $hash->{data}->{options}->{$key}->{update} eq "On" );
	next if (!defined ($hash->{data}->{sets}->{$key})); #Don't include values we're currently not allowed to set (like SilenceOnDemand)

	my $value = HomeConnect_ReadingsVal( $hash, $hash->{data}->{options}->{$key}->{name}, "" );

	#-- safeguard against missing delay
	$value = "0 seconds"
	  if ( $key eq "StartInRelative" && ($value eq ""  or !($hash->{helper}->{delayedstart})));
	$value = "0 seconds"
	  if ( $key eq "FinishInRelative" && !$hash->{helper}->{delayedstart} );
	  
	Log3 $name, 3, "[HomeConnect_StartProgram] $name: option $key has value $value";

	my $json=HomeConnect_MakeJSON($hash,\%{$hash->{data}->{options}->{$key}},$value);
	return $json if ($json !~ /{.*}/); #Got error instead of JSON
	
	push (@optdata,$json);

  }
  
  my $options=join(",",@optdata);
  
  #Dishwasher Favorite uses Common prefix, unfortunately this does not work (Program not supported)
  if ( $program =~ /Favorite.*/ ) {
	$program=HomeConnect_ReadingsVal($hash,"BSH.Common.Option.BaseProgram","0"); #Use 0 as default as that is returned by API for empty
	return "To start a Favorite, make sure to select the Favorite on your appliance and call 'get Programs'" if $program eq "0";
  }

  #-- submit update
  my $data = {
	callback => \&HomeConnect_Response,
	uri      => "/api/homeappliances/" . $hash->{haId} . "/programs/active",
	data     =>
	  "{\"data\":{\"key\":\"$programPrefix$program\",\"options\":[$options]}}"
  };

  Log3 $name, 3, "[HomeConnect] $name: start program $program with uri " . $data->{uri} . " and data " . $data->{data};
  HomeConnect_Request( $hash, $data );
}

sub HomeConnect_StartProgram2($$) {
  my ($hash,$program) = @_;

  my $data = {
	callback => \&HomeConnect_Response,
	uri      => "/api/homeappliances/" . $hash->{haId} . "/programs/active",
	data     =>
	  "{\"data\":{\"key\":\"$program\",\"options\":[]}}"
  };

  Log3 $hash->{name}, 3, "[HomeConnect] Force start progam $program with uri " . $data->{uri} . " and data " . $data->{data};
  HomeConnect_Request( $hash, $data );
}

# PauseProgram, ResumeProgram, OpenDoor
sub HomeConnect_SendCommand($$) {
  my ($hash,$command) = @_;
  my $name = $hash->{NAME};
  return if (!$command or $command eq "");
  #-- submit update
  my $data = {
	callback => \&HomeConnect_Response,
	uri		=> "/api/homeappliances/" . $hash->{haId} . "/commands/BSH.Common.Command.$command",
	data 	=> "{\"data\":{\"key\":\"BSH.Common.Command.$command\",\"value\": true } }" };
  Log3 $name, 3, "[HomeConnect] $name: $command uri " . $data->{uri} . " and data " . $data->{data};
  HomeConnect_Request( $hash, $data );
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

  #Clear some settings that mostly make sense in run state
  if ($hash->{helper}->{clear} and $hash->{helper}->{clear} == -1 and $hash->{prefix}) {
    $hash->{helper}->{clear} = 0;
	my $prefix=$hash->{prefix};
	readingsBeginUpdate($hash);
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartInRelative", "" ) if HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.StartInRelative", undef );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartInRelativeHHMM", "" ) if HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.StartInRelativeHHMM", undef );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartAtHHMM", "" ) if HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.StartAtHHMM", undef );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishAtHHMM", "" ) if HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.FinishAtHHMM", undef );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.RemainingProgramTime", "" ) if HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.RemainingProgramTime", undef );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.RemainingProgramTimeHHMM", "" ) if HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.RemainingProgramTimeHHMM", undef );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.ProgramProgress", "0 %" ) if HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.ProgramProgress", "0 %" ) ne "0 %";
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.BSH.Common.Option.ElapsedProgramTime", "" ) if HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.ElapsedProgramTime", undef );
	HomeConnect_readingsBulkUpdate( $hash, $prefix.".Option.ProcessPhase", "" ) if HomeConnect_ReadingsVal( $hash, $prefix.".Option.ProcessPhase", undef );
	$HomeConnect_DeviceDefaults=\%{$HomeConnectConf::HomeConnect_DeviceDefaults{$hash->{type}}};
	foreach my $reading (@{$HomeConnect_DeviceDefaults->{clear}}) {
		HomeConnect_readingsBulkUpdate( $hash, $prefix.".".$reading, "" ) if HomeConnect_ReadingsVal( $hash, $prefix.".".$reading, undef );
	}
	readingsEndUpdate( $hash, 1 );	
  }

  #Check all the Status Flags and execute the required queries
  if ($hash->{helper}->{init} == 1 and !$hash->{offline}) { #Sanity check - only if init was successful and not offline
	HomeConnect_GetSettings($hash) if ($hash->{helper}->{settings} == -1);
	HomeConnect_UpdateStatus($hash) if ($hash->{helper}->{status} == -1);

	HomeConnect_GetPrograms($hash) if ($hash->{helper}->{programs} == -1);

	my $prg = HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.SelectedProgram", "" ).HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.ActiveProgram", "" );

	#After GetPrograms we should know if a program is active or selected
	if ( $prg ne "" and $hash->{helper}->{programs} == 1) {
	  HomeConnect_GetProgramOptions($hash) if ($hash->{helper}->{options} == -1 );
	  HomeConnect_CheckProgram($hash) if ($hash->{helper}->{options} == 1 and $hash->{helper}->{details} == -1 );
	}
  }
  
  # check if still connected
  if ( !defined $hash->{conn} and AttrVal( $name, "disable", 0 ) == 0 ) {

	# a new connection attempt is needed
	my $retryCounter =
	  defined( $hash->{helper}->{retrycounter} ) ? $hash->{helper}->{retrycounter} : 0;
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
	$hash->{helper}->{retrycounter} = $retryCounter;
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
 HomeConnect_Request( $hash, $data );
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
  HomeConnect_Request( $hash, $data );
  $hash->{helper}->{settings} = 0;
  return;
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

  my $ret=HomeConnect_ParseKeys($hash,"settings",$json);
  if (!$ret) {
	Log3 $name, 3, "[HomeConnect_ResponseGetSettings] $name: error getting settings, replacing by default settings for type $type";
	my @list;
	delete $hash->{data}->{settings};
	foreach my $opt (@{$HomeConnect_DeviceDefaults->{settings}}) {
		$opt =~ s/:(.*)//;
		my $values=$1;
		HomeConnect_SetOption($hash,"settings",$opt,"name","BSH.Common.Setting.".$opt);
		HomeConnect_SetOption($hash,"settings",$opt,"values",$values) if ($values);
		push(@list,$opt);
	}
	$ret=join(",",@list);
  } else {
    #Only set "done" if successfull. In "offline" Error case, HandleError is setting this as that is normal for older devices
	$hash->{helper}->{settings} = 1;
  }
  $hash->{settings}=$ret;
  return;
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

  #Redefine variable, probably needed in case of "reload" of module
  $HomeConnect_DeviceDefaults=\%{$HomeConnectConf::HomeConnect_DeviceDefaults{$hash->{type}}};

  $hash->{helper}->{programs} = 0;
  
  #No programs with any fridges
  if ($hash->{type} =~ /(Fridge)|(Freezer)|(Refrigerator)|(Wine)/) { 
	#Keep programs=0 so it is clear programoptions etc. won't get called as well
	return;
  }

#-- we do not get a list of programs if a program is active, so we just use the active program name
  my $operationState = ReadingsVal( $name, "BSH.Common.Status.OperationState", "" );

  if ( $operationState =~ /(Active)|(DelayedStart)|(Run)|(Pause)/ ) {
  #TEST: Why? we now get selected/active infos as well
	  #return; #Do not try to get programs at all in these cases
  } 

  #-- Request available programs
  delete $hash->{data}->{sets}; #Reset the value list, as GetPrograms creates the "master" list
  my $data = {
	callback => \&HomeConnect_ResponseGetPrograms,
	uri      => "/api/homeappliances/$hash->{haId}/programs"
  };
  HomeConnect_Request( $hash, $data );
  Log3 $name, 5, "[HomeConnect_GetPrograms] $name: getting programs with uri " . $data->{uri};
  return;
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

  my $extraPrograms = AttrVal( $name, "extraPrograms", "" );

  my $arr=$jhash->{data}->{programs};
  
	
  my @prgs;
  foreach my $line (@$arr) {
	my $key = $line->{key};
	$key = HomeConnect_FixProgram($key);
	push (@prgs,$key);
  }
  my $found=@prgs; #Count before selected/active get added
  
  my @optarray;
  #Reply also contains information about the currently selected and active program
  my $skey=$jhash->{data}->{selected}->{key};
  if ($skey) {
	$skey = HomeConnect_FixProgram($skey);
	HomeConnect_readingsSingleUpdate($hash,"BSH.Common.Setting.SelectedProgram",$hash->{prefix}.".Programs.".$skey,1);
	if (!grep { $_ eq $skey } @prgs) { #Avoid duplicates
		push (@prgs,$skey);
	}
	@optarray=@{$jhash->{data}->{selected}->{options}};
	HomeConnect_FileLog($hash,"selected:".Dumper(@optarray));
	HomeConnect_ProcessOptions($hash,"options","check",\@optarray);
  } else {
	HomeConnect_readingsSingleUpdate($hash,"BSH.Common.Setting.SelectedProgram","",1);
	HomeConnect_FileLog($hash,"No Program selected");
  }

  my $akey=$jhash->{data}->{active}->{key};
  if ($akey) {
	$akey = HomeConnect_FixProgram($akey);
	HomeConnect_readingsSingleUpdate($hash,"BSH.Common.Setting.ActiveProgram",$hash->{prefix}.".Programs.".$akey,1);
	if (!grep { $_ eq $akey } @prgs) {
		push (@prgs,$akey);
	}
	@optarray=@{$jhash->{data}->{active}->{options}};
	HomeConnect_FileLog($hash,"active:".Dumper(@optarray));
	HomeConnect_ProcessOptions($hash,"options","check",\@optarray);
  } else {
	HomeConnect_readingsSingleUpdate($hash,"BSH.Common.Setting.ActiveProgram","",1);
	HomeConnect_FileLog($hash,"No Program active");
  }
  if ($found>0) { #Only change programs if a list was returned
	push (@prgs,$extraPrograms) if $extraPrograms;
	my $programs=join(",",@prgs);
	$hash->{programs} = $programs;
	readingsSingleUpdate($hash,".programs",$programs,0); #Also remember in hidden reading
  } else {
    HomeConnect_FileLog($hash,"ProgramList:".$hash->{programs});
	$msg = "[HomeConnect_ResponseGetPrograms] $name: no programs found";
	readingsSingleUpdate( $hash, "lastErr", "No programs found", 1 );
	Log3 $name, 1, $msg;
	return $msg;
  }
  $hash->{helper}->{programs} = 1;
}

sub HomeConnect_FixProgram($) {
	my ($key) = @_;
	$key =~ s/.*\..*\.Program\.//;
	#Work around a problem with certain dryers that repeat the program name 3 times
	my @kk = split( /\./, $key );
	$key = $kk[0] if ( @kk == 3 and $kk[0] eq $kk[1] );
	return $key;
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
  
    #No programs with any fridges
  if ($hash->{type} =~ /(Fridge)|(Freezer)|(Refrigerator)|(Wine)/) { 
	$hash->{helper}->{options} = 1;
	return;
  }
  
  #-- start the processing
  my $programPrefix = $hash->{prefix} . ".Program.";
  my $operationState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.OperationState", "" );
  my $query="";

  #TEST: Need to add DelayedStart to query from "active" as well?
  #-- first try active program as it might be more accurate than "selected"
  my $sprogram =	HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.SelectedProgram", "" );
  if ($sprogram ne "" and $operationState !~ /Run|Finished|Pause/) {
	$query="available/$programPrefix$sprogram";
	if ( $sprogram =~ /Favorite.*/ ) { #Cannot query Favorite - query BaseProgram instead
	  $sprogram=HomeConnect_ReadingsVal($hash,"BSH.Common.Option.BaseProgram","0"); #Use 0 as default as that is returned by API for empty
	  if ($sprogram ne "0") {
		$query="available/$programPrefix$sprogram";
	  }
	}
  }
  my $aprogram = HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.ActiveProgram", "" );
  $query="active/$programPrefix$aprogram" if ($aprogram ne "" and $operationState !~ /Run|Finished|Pause/);

  $query="active/options" if ($query eq "" and $operationState =~ /Run|Finished|Pause/); #Use "active" even if ActiveProgram is not present when running

  if ( $query eq "") {
	$msg="No programs selected or active";
	readingsSingleUpdate( $hash, "lastErr", $msg, 1 );
	Log3 $name, 1, $msg;
	return $msg;
  }


  HomeConnect_FileLog($hash, "GetProgramOptions: $query");

  my $data = {
	callback => \&HomeConnect_ResponseGetProgramOptions,
	uri      => "/api/homeappliances/$hash->{haId}/programs/$query"
  };
  HomeConnect_Request( $hash, $data );
  $hash->{helper}->{options} = 0;
  Log3 $name, 5, "[HomeConnect_GetProgramOptions] $name: getting options with uri " . $data->{uri};
  return;
}

###############################################################################
#
#   ResponseGetProgramOptions
#
###############################################################################

sub HomeConnect_ResponseGetProgramOptions {
  my ( $hash, $json, $path ) = @_;
  my $name = $hash->{NAME};
  my $msg;

  return
	if ( !defined $json );
  
  my $options= HomeConnect_ParseKeys($hash,"options",$json);
  my $program= $hash->{helper}->{key};
  #Update ActiveProgram from Reply if missing
  if ($program && HomeConnect_ReadingsVal($hash,"BSH.Common.Setting.ActiveProgram","") eq "" && $path =~/active/) {
	  HomeConnect_readingsSingleUpdate($hash,"BSH.Common.Setting.ActiveProgram",$program,1);
  }
  #Update SelectedProgram from Reply if missing
  if ($program && HomeConnect_ReadingsVal($hash,"BSH.Common.Setting.SelectedProgram","") eq "" && $path =~/selected/) {
	  HomeConnect_readingsSingleUpdate($hash,"BSH.Common.Setting.SelectedProgram",$program,1);
  }

  #Add extra options from attribute, booleans will be detected by specifying them with "option:On,Off"
  #However even Option Names are identified, they don't work with the API
  my $extraOpts = AttrVal($name,"extraOptions","");
  my @opt=split(" ",$extraOpts);
  foreach my $option (@opt) {
    $option =~ /(.*):(.*)/;
	$hash->{data}->{options}->{$1}->{name}=$hash->{prefix}.".Option.".$1;
	$hash->{data}->{options}->{$1}->{values}=$2;
	$options.="," if ($options ne "");
	$options.=$1;
  }
  $hash->{options}=$options;
  $hash->{helper}->{options} = 1;
  #Also get the current state data  
  $hash->{helper}->{details} = -1;
  return;
}


#Parse the reply of getting settings or options
#$area is "setting" or "option"
sub HomeConnect_ParseKeys($$$) {
  my ($hash,$area,$json) = @_;

  my $name=$hash->{NAME};
  my $orgarea=$area;
  return if ( !defined $json );
  Log3 $name, 5, "[HomeConnect_ParseKeys] $name: $area response $json";

  my $JSON  = JSON->new->utf8(0)->allow_nonref;
  my $jhash = eval { $JSON->decode($json) };
  if ($@) {
	my $msg = "[HomeConnect_ParseKeys] $name JSON error requesting $area: Probably a connection timeout. Check connection to Home Connect Server and try again.";
	Log3 $name, 1, $msg;
	return $msg;
  }
  HomeConnect_FileLog($hash,"Get_$area:".Dumper($jhash));

  if ( $jhash->{"error"} ) {
   HomeConnect_HandleError( $hash, $jhash );
   return undef;
  }
  $area="options" if ($area eq "check"); #"check" is a special case for options
  return if (!$jhash->{data}->{$area});

  delete $hash->{data}->{sets} if $orgarea eq "options"; #"options" keeps the default, "value" shows current values and indicates what's active
  my @arr=@{$jhash->{data}->{$area}};
  $hash->{helper}->{key}=$jhash->{data}->{key};
  return HomeConnect_ProcessOptions($hash,$area,$orgarea,\@arr);
}

sub HomeConnect_ProcessOptions($$$$) {
  my ($hash,$area,$orgarea,$arr) = @_;
  
  my $name=$hash->{NAME};
  readingsBeginUpdate($hash);
  my @list; #to return a summary list
  foreach my $line (@$arr) {
	my $option=$line->{key};
	my $key=$option; #unaltered
	$option =~ s/.*\.//;
	push (@list,$option);
	my $vtype=$line->{type};
	my $allowedvals = $line->{constraints}->{allowedvalues};
	if ($allowedvals) {
	  $allowedvals=join(",",@$allowedvals) if (ref($allowedvals) eq "ARRAY"); # allowedvalues might contain an array, make it a "," separated list
	  $allowedvals =~ s/$vtype\.//g if ($vtype =~ /\./); #and remove the prefixes
	}
	my $default=$line->{constraints}->{default};
	$default =~ s/^$vtype\.// if ($default and $vtype =~ /\./); #remove prefix from default if type is a complex (not Int etc.)

	#Specific for settings
    my $svalue=$line->{value};
	my $stype;
	if ($svalue and ($svalue !~ /^\d+$/) and ($svalue !~ /^\d+\.\d+/)) { #Not for Int or float numbers
		$svalue =~ s/(.*)\.//; #Remove prefix from Setting Values
		$stype = $1; #Store prefix as type
	}

	HomeConnect_SetOption($hash,$area,$option,"type",$line->{type}); #Full type
	$allowedvals="On,Off" if ($vtype and $vtype eq "Boolean");
	if (ref($svalue) eq "JSON::PP::Boolean") {
		$allowedvals="On,Off";
		$vtype="Boolean";
		$svalue=$svalue?"On":"Off"; #Convert JSON Boolean to On/Off
	}
	if ($svalue and !$allowedvals and $line->{value} =~ /EnumType.*(On|Off)/) {
		#SpecialCase for enumerator On/Off when now enumarations are set in "check" mode
		$allowedvals="On,Off";
	}
	HomeConnect_FileLog($hash,"Checking key $key $orgarea $option ".(defined($svalue)?$svalue:"<noval>"));
	my $unit=$line->{unit};
	$unit = undef if (defined($unit) and $line->{unit} =~ /(E|e)num/); #Stupid coffeemaker has "enum" as unit
	if ($orgarea ne "check" or defined($hash->{data}->{$area}->{$option})) { #Checkprogram shall only update existing values
		HomeConnect_SetOption($hash,$area,$option,"name",$key); #Full key needed to issue command
		HomeConnect_SetOption($hash,$area,$option,"min",$line->{constraints}->{min}); #could be used for range checking
		HomeConnect_SetOption($hash,$area,$option,"max",$line->{constraints}->{max}); #could be used for range checking
		HomeConnect_SetOption($hash,$area,$option,"update",$line->{constraints}->{liveupdate}); 
		HomeConnect_SetOption($hash,$area,$option,"values",$allowedvals); #typically exclusive of min/max
		HomeConnect_SetOption($hash,$area,$option,"default",$default); #needed? Probably need to set this in the reading for preselection
		HomeConnect_SetOption($hash,$area,$option,"exec",$line->{constraints}->{execution}); #needed?

		HomeConnect_SetOption($hash,$area,$option,"value",$svalue); #for settings
		HomeConnect_SetOption($hash,$area,$option,"type",$stype); #for settings
		HomeConnect_SetOption($hash,$area,$option,"unit",$unit); #for settings
		#Mark Options as "set" option only when it is mentioned in "ProgramOptions"
		if ($orgarea ne "check") {
			$hash->{data}->{sets}->{$option}=1 if ($key !~ /Common/);
			$hash->{data}->{sets}->{$option}=1 if ($key =~ /Duration/);	#Include some special Common keys
		}
	} 
	
	#Also put this into readings
	if ($svalue) {
		HomeConnect_readingsBulkUpdate( $hash, $key, $svalue.($unit?" ".$unit:"") );
		#Some special key updates
		if ($option =~ /RemainingProgramTime$/) {
			$hash->{helper}->{rtime}=int(gettimeofday()); #Remember Timestamp of last update
			$hash->{helper}->{remaining}=$svalue;
		} elsif ($option =~ /ElapsedProgramTime$/) {
			$hash->{helper}->{etime}=int(gettimeofday()); #Remember Timestamp of last update
			$hash->{helper}->{elapsed}=$svalue;
		}
	}
  }
  readingsEndUpdate( $hash, 1 );
  return join(",",@list);
}

sub HomeConnect_SetOption($$$$$) {
  my ($hash,$area,$key,$target,$value) = @_;
  return if (!defined $value or $value eq "");
  if (ref($value) eq "JSON::PP::Boolean") {
	$value=$value?"On":"Off"; #Convert to normal 0/1
  }
  $hash->{data}->{$area}->{$key}->{$target}=$value;
  return $value; #Use for conversion
}

##############################################################################
#
#   checkState
#
##############################################################################

sub HomeConnect_CheckState($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if !defined $hash->{prefix};    #Still not initialized
  my $lang = AttrVal( "global", "language", "EN" );
  my $programPrefix = $hash->{prefix} . "Command.";
  my $type = $hash->{type};

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

  my $aprogram = HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.ActiveProgram", "" );
  my $sprogram = HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.SelectedProgram", "" );
  my $remoteStartAllowed=HomeConnect_ReadingsVal($hash,"BSH.Common.Status.RemoteControlStartAllowed","Off");
  $remoteStartAllowed=($remoteStartAllowed eq "On"?1:0);
  
  #-- selected program missing
  if ( $sprogram eq "" && $operationState eq "Run" && $aprogram ne "" ) {
	$sprogram = $aprogram;
	HomeConnect_readingsSingleUpdate( $hash, "BSH.Common.Setting.SelectedProgram", $sprogram, 1 );
  }

  #-- in running state both are identical now
  my $program = $aprogram;
  $program =~ s/$programPrefix//;

  #-- trailing space ???
  $program =~ s/\s$//;

#-- program name only replaced by transtable content if this exists
  if ( $program ne "" && defined( $hash->{data}->{trans}->{$program} ) ) {
	$program = $hash->{data}->{trans}->{$program};
  }
  if ($lang eq "DE" && defined $HomeConnect_DeviceDefaults->{programs_DE}->{$program}) {
	$program = $HomeConnect_DeviceDefaults->{programs_DE}->{$program};
  }
  my $pct =	HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.ProgramProgress", "0" );
  $pct =~ s/ \%.*//;
  #My Washer sets pct to 100 some time ahead of Finished
  #$operationState = "Finished" if ( $pct == 100 ); #Some devices don't put a proper finish message when done
  
  my $tim = HomeConnect_ReadingsVal( $hash,	"BSH.Common.Option.RemainingProgramTimeHHMM", "0:00" );
  my $sta = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.StartAtHHMM", "0:00" );
  my $door = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.DoorState", "closed" );
  $tim=$pct."%" if ($tim eq "0:00" and $pct>0); #E.g. for coffemaker that just gives a %

  HomeConnect_FileLog($hash, "[HomeConnect_CheckState] V$HCversion from s:$currentstate d:$door o:$orgOpSt");
  $hash->{version}=$HCversion;

  my $state1 = "";
  my $state2 = "";
  my $state  = "off";
  my $trans  = $HomeConnect_Translation->{$lang}->{ lc $operationState };
  $trans=$operationState if (!defined $trans or $trans eq "");
  
  if (ReadingsAge($name,"BSH.Common.Option.ElapsedProgramTime",-1)>120) {
	if ($hash->{helper}->{etime}) {
		my $delta=gettimeofday()-$hash->{helper}->{etime};
		HomeConnect_FileLog($hash,"Elapsed:".$hash->{helper}->{elapsed}+$delta);
	}
  }

  # Workaround for missing RemainingProgramTime - calculate myself if no update since 2 minutes
  if ($hash->{helper}->{rtime}) {
	if (ReadingsAge($name,"BSH.Common.Option.RemainingProgramTime",-1)>120) {
		my $delta=int(gettimeofday())-$hash->{helper}->{rtime};
		my $value=$hash->{helper}->{remaining}-$delta;
		my $rstr=HomeConnect_UpdateRemainingTime($hash,$value);
		HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.RemainingProgramTimeHHMM", $rstr );
	}
  }

  
  if ( $type =~ /Oven/ ) {
	my $tim1 = HomeConnect_ReadingsVal( $hash,	"BSH.Common.Option.RemainingProgramTime", "0 seconds" );
	my $tim2 = HomeConnect_ReadingsVal( $hash,	"BSH.Common.Option.ElapsedProgramTime", "0 seconds" );
	my $temp = HomeConnect_ReadingsVal( $hash,	"Cooking.Oven.Status.CurrentCavityTemperature", "0 °C" );
	$tim="";
	$tim1  =~ s/ \D+//g; # remove seconds
	$tim2  =~ s/ \D+//g; # remove seconds
	$temp  =~ s/ \D+//g; # remove °C
	$temp = int($temp); #Remove decimals
	$tim = HomeConnect_ConvertSeconds($tim2) if $tim2>0; #Default is elapsed
	$tim = HomeConnect_ConvertSeconds($tim1) if $tim1>0; #Alternative Remaining
	$tim .= "/" if ($temp>0 and $tim ne "");
	$tim .= $temp." °C" if $temp>0;
  }

  readingsBeginUpdate($hash);  
  if ( $operationState =~ /(Run)/ ) {
	$state  = "run";
	$state1 = "$program";
	$state2 = "$tim";
	if ($currentstate ne $state and $program ne "") {
		#state changed into running - now get the program options that might only be valid during run (e.g. SilenceOnDemand)
		$hash->{helper}->{options} = -1 if ($type !~ /Coffee/); #Except for coffemakers where this would create errors
		HomeConnect_FileLog($hash,"request updatePO as $currentstate != $state and program=$program");
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
	readingsBulkUpdate($hash,"lastErr","Error or action required",1);
	$hash->{helper}->{clear}=-1 if ($currentstate ne $state);
  }
  if ( $operationState =~ /(Abort)|(Finished)/ ) {
	delete $hash->{helper}->{rtime}; #Clear timestamps for calculating remaining/elapsed time
	delete $hash->{helper}->{etime};
	$state  = "done";
	$state1 = $HomeConnect_Translation->{$lang}->{$state};
	$state2 = "-";
	$state = "idle" if $type =~ /Coffe/; # Coffeemakers don't have a door that can be opened -> go to ready right away
	$hash->{helper}->{clear}=-1 if ($currentstate ne $state);
  }
  if ( $operationState =~ /(Ready)|(Inactive)|(Offline)/ ) {
	$hash->{helper}->{clear}=-1 if ($currentstate ne $state);
    HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.ProgramProgress", "0 %" ) if $pct>0; #Reset Progress to prevent wrong display when starting next
	if ($currentstate eq "done" and $door =~ /Closed/) {
		#Delay switching to "idle" until door gets opened so user continues to get indication that appliance needs to be emptied, even when it goes to "off" automatically
		$state  = "done";
		$state1 = $HomeConnect_Translation->{$lang}->{$state};
		$state2 = "-";
	} else {
	  if ($remoteStartAllowed) {
		$state = "auto";
		$state1 = $HomeConnect_Translation->{$lang}->{"autostart"};
		$state2 = "-";
	  } else {
		$state  = "idle";
		$state1 = $HomeConnect_Translation->{$lang}->{$state};
		$state2 = "-";
	  }
	}
  }

#Opened door overrides any state from done -> idle to indicate the appliance got emptied
  if ( $door =~ /Open/ ) {
	$state  = "idle" if $state eq "done";
	$state1 = $HomeConnect_Translation->{$lang}->{"door"} . " " . $HomeConnect_Translation->{$lang}->{ lc $door };
	$state2 = "-";
	$operationState = "Ready" if $operationState =~/Finished/; # There might be no event setting Finished -> Ready when Finished was by set by FHEM
  }

  HomeConnect_CheckAlerts($hash);
  #This type only shows temperatures, override everything
  if ( $type =~ /Fridge|Refrigerator|Freezer/ ) {
	my $alarms = ReadingsVal($name,"alarms","");
	$state = lc $door;
	$state = "alarm" if $alarms =~ /DoorAlarm/;
	my $tr = HomeConnect_ReadingsVal( $hash,"Refrigeration.FridgeFreezer.Setting.SetpointTemperatureRefrigerator", undef );
	my $tf = HomeConnect_ReadingsVal( $hash,"Refrigeration.FridgeFreezer.Setting.SetpointTemperatureFreezer", undef );
	$tr.=" °C" if defined($tr) and $tr!~ /C/;
	$tf.=" °C" if defined($tf) and $tf!~ /C/;	
	$state1 = "-";
	$state2 = "-";
	$state1 = $tr if defined($tr);
	$state2 = $tf if defined($tf);
	if ($state1 eq "-") { $state1=$state2; $state2="-";}
  } 

  HomeConnect_FileLog($hash, "[HomeConnect_CheckState] to s:$state d:$door o:$operationState 1:$state1 2:$state2");
  
  #Correct special characters if using encoding=unicode
  $state1 = decode_utf8($state1) if $unicodeEncoding;
  $state2 = decode_utf8($state2) if $unicodeEncoding;
  
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

  #If stopProgram is done, retry to set delay
  if ($hash->{helper}->{autostart} and $hash->{helper}->{autostart}==2 and $hash->{helper}->{delay}) {
	  my @args=split(",",$hash->{helper}->{delay});
	  HomeConnect_DelayTimer($hash,$args[0],$args[1],$args[2]);
	  delete $hash->{helper}->{delay};
  }
}

#Check the Events for active alerts and store a summary in alerts and alertCount
sub HomeConnect_CheckAlerts($) {
  my ($hash) = @_;
  
  foreach my $reading (keys %{$hash->{READINGS}}) {
   if ($reading =~ /Event\.(.*)/) {
    my $value = HomeConnect_ReadingsVal($hash,$reading,"");
    my $alarm = $1;
	next if (!$alarm or $alarm eq "" or $value eq "");
	#Ignore: ProgramFinished, ProgramAborted, AlarmClockElapsed, PreheatFinished, DryingProcessFinished
	#Alternative positive list: /(Empty)|(Full)|(Cool)|(Descal)|(Clean)|(DoorAlarm)|(TemperatureAlarm)|(Stuck)|(Found)|(Poor)|(Reached)/
	next if ($alarm =~ /Program|AlarmClock|Finished/ );

	my $alarms=ReadingsVal($hash->{NAME},"alarms","");
	my $calarms=$alarms;
	  if ( $value =~ /Present/ ) {
		#If alarm not yet in list - add it
		if ( $alarms !~ $alarm ) {
			$alarms .= "," if $alarms ne "";
			$alarms .= $alarm;
		}
	  } else {
		#Remove alarm after it is over
	    $alarms =~ s/$alarm//g;
		$alarms =~ s/,,/,/g; #Clean potential double "," after removal
	  }
	  if ("$alarms" ne "$calarms") { 
		#Use Bulkupdate as this is called from within an readingsBegin/EndUpdate
		readingsBulkUpdate( $hash,"alarms",$alarms);
		my @cnt=split(",",$alarms);
		readingsBulkUpdate( $hash,"alarmCount",scalar @cnt);
	  }
   }
  }
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
  HomeConnect_Request( $hash, $data );
  $hash->{helper}->{status} = 0;
  return;
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
  
  HomeConnect_ParseKeys($hash,"status",$json);

  $hash->{helper}->{status} = 1;

  $hash->{STATE}="Ready";
}

##############################################################################
#
#   CheckProgram
#
##############################################################################

sub HomeConnect_CheckProgram {
  my ($hash) = @_;
 
  #Can only query if a program is either selected or active - prefer active here
  my $query="";
  $query="selected" if HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.SelectedProgram", "" );
  my $active=HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.ActiveProgram", "" );
  my $operationState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.OperationState", "" );
  #Clear accidentially set ActiveProgram
  HomeConnect_readingsSingleUpdate( $hash, "BSH.Common.Setting.ActiveProgram", undef,1 ) if ($active && $operationState =~ /Ready|Inactive/);
  $query="active" if $operationState =~ /Run|Finished|Pause/; #TEST: Need DelayedStart as well here?
  return if $query eq "";
    
  #-- Get status variables
  my $data = {
	callback => \&HomeConnect_ResponseCheckProgram,
	uri      => "/api/homeappliances/$hash->{haId}/programs/$query"
  };
  HomeConnect_Request( $hash, $data );
  $hash->{helper}->{details} = 0;
  return;
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

  my $options= HomeConnect_ParseKeys($hash,"check",$json);
  $hash->{helper}->{details} = 1;
  return;
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
  
  my $allevents = AttrVal($name,"allEvents",0);

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
  
  $param->{url} = "$api_uri/api/homeappliances/events" if $allevents == 1;

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
  $hash->{helper}->{eventChannelTimeout} = time();

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
  if ( defined $hash->{helper}->{eventChannelTimeout}
	&& ( time() - $hash->{helper}->{eventChannelTimeout} ) > 140 )
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
	$hash->{helper}->{eventChannelTimeout} = time();

	my ($event) = $inputbuf =~ /^event\:(.*)$/m;
	my ($id)    = $inputbuf =~ /^id\:(.*)$/m;
	my ($json)  = $inputbuf =~ /^data\:(.*)$/m;
	my ($http)  = $inputbuf =~ /^HTTP\/1.1 (.*) OK/m;
    my ($error) = $inputbuf =~ /\"error\"\:(.*)$/m;
 
    if (!$event and !$http and $error) {
	  Log3 $name, 5, "[HomeConnect_ReadEventChannel] $name: Error reading event channel:\"$inputbuf\"";
	  HomeConnect_CloseEventChannel($hash);
	  return undef;
	}
	
	if ($http) {
	  if ( $http ne "200" ) {
		Log3 $name, 2, "[HomeConnect_ReadEventChannel] $name: event channel received an http error: $_";
		HomeConnect_CloseEventChannel($hash);
		return undef;

		#-- successful connection, reset counter
	  }
	  else {
		$hash->{helper}->{retrycounter} = 0;
	  }
	}
	elsif ( $json and $event =~ /NOTIFY|STATUS|EVENT/ ) {
	  Log3 $name, 5, "[HomeConnect_ReadEventChannel] $name: event $event data: $json";
	  my $jhash = eval { $JSON->decode($json) };

	  if ($@) {
		Log3 $name, 2, "[HomeConnect_ReadEventChannel] $name: JSON error reading from event channel";
		return;
	  }
	  my $operationState = HomeConnect_ReadingsVal( $hash, "BSH.Common.Status.OperationState", "" );
	  HomeConnect_FileLog($hash,"Event:".Dumper($jhash));
	  $hash->{offline}=0; #Assume device can no longer be offline if it is sending events

	  readingsBeginUpdate($hash);

	  for ( my $i = 0 ; 1 ; $i++ ) {
		my $skipupdate=0;
		my $item = $jhash->{items}[$i];
		if ( !defined $item ) { last }
		my $key   = $item->{key};
		my $value = $item->{value};
		$value = "" if ( !defined($value) );
		my $unit = $item->{unit};
		$unit = "" if ( !defined($unit) );
		$value=$value?"On":"Off" if (ref($value) eq "JSON::PP::Boolean");
		
		Log3 $name, 4, "[HomeConnect_ReadEventChannel] $name: $key = $value";
		#-- special keys
		if ( defined($hash->{data}->{finished}) and $key =~ /$hash->{data}->{finished}/) {
		  if ( $value =~ /Present/ and $operationState =~ /Run/ ) {
		    #Dryer will not go into Finished state if WrinkleGuard is active - then we get "DryingProcessFinished" and "ProgramFinished" is sent only after end of WrinkleGuard 
		    HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Status.OperationState", "BSH.Common.EnumType.OperationState.Finished" );
		  }
		  else {
		    #Probably nothing special to do if value goes from Finished to Off
		  }
		  $checkstate = 1;
		#Temperature changes typically should update the state variables
		} elsif ( $key =~ /Temperature/ ) {
		  $checkstate = 1;
		#Known Alerts - keep filters very generic, but it should be accurate enough to only react on real alarms (use DoorAlarm and TemperatureAlarm to distinguish from AlarmClock)
		} elsif ( $key =~ /(Empty)|(Full)|(Cool)|(Descal)|(Clean)|(DoorAlarm)|(TemperatureAlarm)|(Stuck)|(Found)|(Poor)|(Reached)/ ) {
		  #update now done in CheckState()
		  $checkstate=1;
		} elsif ( $key =~ /ProgramAborted/ ) {
		  $hash->{helper}->{status}=-1 if ($value =~/Present/ and $operationState =~ /Run/); #Reread status after abort
		} elsif ( $key =~ /ActiveProgram/ ) {
		  #Remember previous active program
		  my $prev=HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.ActiveProgram","");
		  $hash->{helper}->{ActiveProgram}=$prev if $prev; #ActiveProgram might become empty (reason not understood)
		  $checkstate=1;
		} elsif ( $key =~ /PowerState/ ) {
		  if ( $value =~ /On/) {
			$hash->{helper}->{programs}=-1; #This might as well query selected/active program
			$hash->{helper}->{settings}=-1; #Some settings like ChildLock might be missing if it was queries in "off" state
		  } elsif ($value =~/Off/) {
			HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Setting.ActiveProgram", undef);
			$hash->{helper}->{clear}=-1;
		  }
		  $checkstate=1; # Update state on power change
		} elsif ( $key =~ /EstimatedTotalProgramTime/ ) {
		  #If the device estimates the total time, the FinishInRelative would contain some potential garbage number - reset
		  HomeConnect_readingsBulkUpdate( $hash,"BSH.Common.Option.FinishInRelative",0);
		  $checkstate=1;
		} elsif ( $key =~ /LocalControlActive/ ) {
		  $hash->{helper}->{status}=-1 if ($value =~ /Off/); #Update readings after user did something with the appliance
		} elsif ( $key =~ /SelectedProgram/ ) {
		  #Need to get program options when changing program except on power off where this gets set to undef
		  $hash->{helper}->{options} = -1 if $value;
		  #This is the case, when a program gets stopped to set a different delay. Set the previous active program instead of the "default"
		  $value=$hash->{helper}->{ActiveProgram} if ($hash->{helper}->{ActiveProgram} and $hash->{helper}->{autostart});
		  #If Active Program is set when a new program is selected and operationState is not running, this probably is a error
		  if ($operationState =~ /Ready|Inactive/ and HomeConnect_ReadingsVal( $hash, "BSH.Common.Setting.ActiveProgram", "" ) ne "") {
			HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Setting.ActiveProgram", undef );
		  }
		  $value = HomeConnect_FixProgram($value);
		  if (!($hash->{programs} =~ /$key/)) {
			HomeConnect_FileLog($hash,"Unknown selected program $key - trigger GetPrograms");			
			$hash->{helper}->{programs} = -1;
		  }
		}
		elsif ( $key =~ /StartInRelative/ ) {
		  $value =~ s/\D+//g; # remove seconds
		  my $h    = int( $value / 3600 );
		  my $m    = ceil( ( $value - 3600 * $h ) / 60 );
		  my $tim2 = sprintf( "%d:%02d", $h, $m );

		  #-- determine start and end
		  my ( $startmin, $starthour ) =
			( localtime( time + $value ) )[ 1, 2 ];
		  my $delta = HomeConnect_ReadingsVal( $hash, "BSH.Common.Option.RemainingProgramTime", 0 );
		  $delta =~ s/\D+//g; # remove seconds
		  #TODO: test number
		  my ( $endmin, $endhour ) =
			( localtime( time + $value + $delta ) )[ 1, 2 ];
		  my $tim3 = sprintf( "%d:%02d", $starthour, $startmin );
		  my $tim4 = sprintf( "%d:%02d", $endhour,   $endmin );

		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartInRelativeHHMM", $tim2 );
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartAtHHMM", $tim3 );
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.StartToHHMM", $tim4 );
		}
		#Combine updates for FinishInRelative and RemainingProgramTime as both will change the Finish Time
		elsif ( $key =~ /(FinishInRelative)|(RemainingProgramTime)/ ) {
		  my $frel=HomeConnect_UpdateRemainingTime($hash,$value);
		  if ($key =~ /RemainingProgramTime/) {
			HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.RemainingProgramTimeHHMM", $frel );
			delete $hash->{helper}->{rtime}; #Clear timestamps for calculating remaining/elapsed time
			delete $hash->{helper}->{etime};
		  }
		  $checkstate = 1;
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

		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.AlarmClockHHMM", $tim5 );
		  HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.AlarmAtHHMM", $tim6 );
		} elsif ( $key =~ /(DoorState)|(ProgramProgress)/ ) {
		  $checkstate = 1;
		} elsif ( $key =~ /(OperationState)/ ) {
		  if (defined $value) {
			#When trying to change delayedStart, we need to wait until stopProgram is finished before continuing
		    $hash->{helper}->{autostart}=2 if (defined $hash->{helper}->{autostart} and $hash->{helper}->{autostart} == 1 and $value=~/Ready/);
		  }
		  $checkstate = 1;
		}
		elsif ( $key =~ /RemoteControlStartAllowed/ ) {
		}
		HomeConnect_readingsBulkUpdate( $hash, $key, $value . ( ( defined $unit ) ? " " . $unit : "" ) ) if !$skipupdate;
	  }
	}
	elsif ( $event eq "DISCONNECTED" ) {
	  my $state = "Offline";
	  #TEST: Should this be handled like "power off" ?
	  readingsSingleUpdate( $hash, "state", $state, 1)
		if ( $hash->{STATE} ne $state );
	  Log3 $name, 4, "[HomeConnect_ReadEventChannel] $name: disconnected $id";
	  $checkstate=1;
	}
	elsif ( $event eq "CONNECTED" ) {
	  Log3 $name, 4, "[HomeConnect_ReadEventChannel] $name: connected $id";
	  $hash->{helper}->{status}=-1;
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

  HomeConnect_CheckState($hash) if $checkstate;
  Log3 $name, 5, "[HomeConnect_ReadEventChannel] $name: event channel received no more data";
}

sub HomeConnect_UpdateRemainingTime($$) {
	my ($hash,$value) = @_;
	$value =~ s/\D+//g; # remove seconds
	my $h    = int( $value / 3600 );
	my $m    = ceil( ( $value - 3600 * $h ) / 60 );
	my $frel = sprintf( "%d:%02d", $h, $m );
	my ( $endmin, $endhour ) = ( localtime( time + $value ) )[ 1, 2 ];
	my $ftim = sprintf( "%d:%02d", $endhour, $endmin );

	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishInRelativeHHMM", $frel );
	HomeConnect_readingsBulkUpdate( $hash, "BSH.Common.Option.FinishAtHHMM", $ftim );
	return $frel;
}

sub HomeConnect_ConvertSeconds($) {
	my ($value) = @_;
	my $h    = int( $value / 3600 );
	my $m    = ceil( ( $value - 3600 * $h ) / 60 );
	my $time = sprintf( "%d:%02d", $h, $m );
	return $time;
}

# Manipulate the Readings and Values according to the settings
# Attribute namePrefix = 1 : keep the prefix in the name of the reading
# Attribute valuePrefix = 1 : keep the prefix in the name of the value

sub HomeConnect_ReplaceReading($$) {
  my ( $hash, $value ) = @_;
  my $name          = $hash->{NAME};
  my $HC_namePrefix = AttrVal( $name, "namePrefix", 0 );
  $value =~ s/BSH.Common.Root/BSH.Common.Setting/; #Rename the confusing Root entries
  if ( $HC_namePrefix == 0 and $hash->{prefix}) {
	$value =~ s/.*\.Common.//; #Need *.Common as there is BSH.Common, but also e.g. LaundryCare.Common
	my $programPrefix = $hash->{prefix} . "\.";
	$value =~ s/$programPrefix//;
  }
  return $value;
}

sub HomeConnect_ReplaceValue($$) {
  my ( $hash, $value ) = @_;
  $value="" if !defined($value); #for setting "undef"
  my $name           = $hash->{NAME};
  return $value if ( $value =~ /\d+\.\d+/ ); # Floating Point
  my $HC_valuePrefix = AttrVal( $name, "valuePrefix", 0 );
  if ( $HC_valuePrefix == 0 and $value =~ /\./ ) {
	if ( $value =~ /.*\.Program\.(.*)/ ) {
	  $value=$1;
	} else {
	  $value =~ /.*\.(.*)$/;
	  $value = $1;
	}
  }
  $value =~ s/\s$//;    # Remove any trailing spaces
  $value = decode_utf8($value) if $unicodeEncoding;
  return $value;
}

#Wrap the two readings Update functions into one
sub HomeConnect_ReadingsUpdate($$$$$) {
  my ( $hash, $reading, $value, $notify, $function ) = @_;
  my $nreading = HomeConnect_ReplaceReading( $hash, $reading );
  my $nvalue   = HomeConnect_ReplaceValue( $hash, $value );
  #Translation: if reading is in list, translate the value and create a new reading with "tr_" prefix
  my $trans = AttrVal ( $hash->{NAME}, "translate", "");
  $trans =~ s/,/\$|^/g;
  $trans = "^".$trans."\$";
  $nreading =~ /.*\.(.*)$/;
  my $sreading = $1; #Pure last part of the reading
  $sreading=$reading if !$sreading; #Catch case reading has no dots

  if ($sreading =~ $trans) {
	my $lvalue=lc $nvalue;
	my $tvalue=$nvalue;
    $tvalue =~ /\s.*/; #When translating also remove " %", " seconds", " °C" etc. to create a plain value
	$tvalue=$HomeConnect_Translation->{DE}{$lvalue} if (defined $HomeConnect_Translation->{DE}{$lvalue});
	#In case user wants the program name, try that as well:
	$tvalue=$hash->{data}->{trans}->{$nvalue} if (defined( $hash->{data}->{trans}->{$nvalue}));
	$tvalue = decode_utf8($tvalue) if $unicodeEncoding;
	readingsSingleUpdate( $hash, $sreading, $tvalue, $notify ) if $function eq "single";
	readingsBulkUpdate( $hash, $sreading, $tvalue ) if $function eq "bulk";
  }
  return readingsSingleUpdate( $hash, $nreading, $nvalue, $notify ) if $function eq "single";
  return readingsBulkUpdate( $hash, $nreading, $nvalue ) if $function eq "bulk"; 
}

sub HomeConnect_readingsBulkUpdate($$$) {
  my ( $hash, $reading, $value ) = @_;
  return HomeConnect_ReadingsUpdate($hash,$reading,$value,0,"bulk");
}

sub HomeConnect_readingsSingleUpdate($$$$) {
  my ( $hash, $reading, $value, $notify ) = @_;
  return HomeConnect_ReadingsUpdate($hash,$reading,$value,$notify,"single");
}

sub HomeConnect_ReadingsVal($$$) {
  my ( $hash, $reading, $default ) = @_;
  #Safety to avoid FHEM crashing during development as original ReadingsVal has a name (not a hash) as first argument
  return "error" if (ref($hash) ne "HASH");
  my $name = $hash->{NAME};

  my $nreading = HomeConnect_ReplaceReading( $hash, $reading );

  my $res = ReadingsVal( $name, $nreading, $default );
  return $res if !defined($res);
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
	$msg =~ s/homeappliances\/[\w|-]+\//homeappliances\/XXXX\//mg;
	$msg =~ s/'haId' => '[\w|-]+'/'haId' => 'XXXX'/mg;
	my $fh = $logdev->{FH};
	if (!$fh) {
		#Log into normal log if something is wrong with filehandle
		Log3 $hash->{NAME}, 4, "[HomeConnect_FileLog] $hash->{NAME}: $msg";
		return;
	}
	my @t = localtime();
    my $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d",
          $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);
	print $fh $tim." ".$msg."\n";
	$fh->flush();
}

sub HomeConnect_Stacktrace() {
    print "Stacktrace:\n";
	my $i=1;
	while ( (my @call_details = (caller($i++))) ){
      print $call_details[1].":".$call_details[2]." in function ".$call_details[3]."\n";
    }
}

#Wrap request, for logging purposes
sub HomeConnect_Request($$) {
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

sub HomeConnect_State($$$$) {			#reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
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

  <a id="HomeConnect-set"></a>
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
  	<li><b>set DelayEndTime &lt;HH:MM&gt; [start]</b><br>
			<a id="HomeConnect-set-DelayEndTime"></a>
			If device supports "startInRelative" or "finishInRelative" and device is set to "remoteStartAllowed"<br>
			Delay the start of the device, so it will likely finish at the given time.<br>
			If the optional argument "start" is given, the appliance will set into DelayedStart mode right away. For some appliances you might need to "StopProgram" before you can manually operated it again.
			</li>
	<li><b>set DelayRelative &lt;HH:MM&gt; [start]</b><br>
			<a id="HomeConnect-set-DelayRelative"></a>
			If device supports "startInRelative" or "finishInRelative" and device is set to "remoteStartAllowed"<br>
			Delays the start of the device by the specified time.
			If the optional argument "start" is given, the appliance will set into DelayedStart mode right away. For some appliances you might need to "StopProgram" before you can manually operated it again.
	</li>
	<li><b>set DelayStartTime &lt;HH:MM&gt; [start]</b><br>
			<a id="HomeConnect-set-DelayStartTime"></a>
			If device supports "startInRelative" or "finishInRelative" and device is set to "remoteStartAllowed"<br>
			Delays the finish time of the device by the specified time.
			If the optional argument "start" is given, the appliance will set into DelayedStart mode right away. For some appliances you might need to "StopProgram" before you can manually operated it again.
	</li>
  </ul>
  <h3>Device specific</h3>
  <ul>
	<li><b>Dryer:</b> DryingTarget</li>
	<li><b>Washer:</b> </li>
	<li><b>Dishwasher:</b> </li>
  </ul>
  <a id="HomeConnect-get"></a>
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
  <a id="HomeConnect-attr"></a>
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
			For development purposes: A temporary logfile device will be created and logs all FHEM events plus all API calls and responses/events (JSON).<br>
			The HaIds are automatically removed, so the file should be safe to share without any personal information.
			</li>
	<li><b>excludeSettings &lt;Option List&gt;</b><br>
			<a id="HomeConnect-attr-excludeSettings"></a>
			Comma separeted list of options (as written in the "set" list) that should be hidden as they are unwanted or do not apply for your specific device.<br>
			This list will be automatically extended when the API return a "not supported" error.<br>
			Make sure to save your config to make this permanent. Also check this list if you miss a setting - maybe a "false positive" was detected, e.g. by trying to use a setting at a stage when the device does not accept it, while it would in a different stage.
			</li>
			
  </ul>
  <a id="HomeConnect-readings"></a>
  <h4>Readings</h4>
  Note: Readings are described in the abbreviated version here, if namePrefix is "1" additional prefix will be added in front.<br>
  <ul>
	<li><b>Event.*</b><br>
			Events from the appliance. Typically set to "Present" when active and to "Off" if no longer valid.<br>
			</li>
	<li><b>Option.*</b><br>
			Appliance or Program options settings. Values might be old, when not applicable to the current state/program.<br>
			</li>
	<li><b>Setting.*</b><br>
			Global settings. Settings can typically be changed by the user. Note that "Root.*" settings get translated to "Setting.*" for consistency.<br>
			</li>
	<li><b>Status.*</b><br>
			Status of settings that can not be set but rather describe the status of the device (e.g. an open door).<br>
			Interesting ones:
			<ul>
			<li>OperationState: indicates what the device is currently doing</li>
			<li>DoorState: if the door is open or closed</li>
			<li>RemoteControlStartAllowed: If "RemoteControl/Fernstart" is active</li>
			</ul>
			</li>
	<li><b>lastErr</b><br>
			As API calls are asynchronously, errors can not be presented back immediately. If something goes wrong, check this reading.<br>
			This however might be old, so check the timestamp as well. Will be automatically set to "ok" after a while.<br>
			</li>
	<li><b>state</b><br>
			Current state of the appliance. This is the best reading to use for automation activities (along with Status.DoorState and Status.OperationState).<br>
			Potential values are:
			<ul>
			 <li>run: A program is currently running</li>
			 <li>pause: A program is currently paused</li>
			 <li>scheduled: A program is scheduled to start later</li>
			 <li>done: Program was finished, but door not yet opened - used to indicate that device should be emptied</li>
			 <li>idle: Device does nothing and is ready to be used (either in standby or off)</li>
 			 <li>auto: Device does nothing and remote start is enabled, so it can be used for automation</li>
			</ul>
	<li><b>state1/state2</b><br>
			Contains a two line status display that can be used e.g. in FTUI.<br>
			Typically shows the name of the running program and the remaining run time, but that can differ depending on the device type and state<br>
			If you don't like these as a default, you should fall back to the original readings or create translated ones by listing them in the "translate" attribute.<br>
			</li>
	<li><b>alarms</b><br>
			Contains the currently active alarms (events). Does not contain trivial events like "ProgramFinished" but rather those that might require user interaction.<br>
			</li>
	<li><b>alarmCount</b><br>
			Number of items in "alarms", intended to be used in FTUI to display a "badge" that will tell the user there is some action required.<br>
			</li>
  </ul>
  <br><br>
  
</ul>

=end html
=cut

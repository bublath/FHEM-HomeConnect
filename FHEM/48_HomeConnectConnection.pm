=head1
        48_HomeConnectConnection.pm

# $Id: $

        Version 1.1

=head1 SYNOPSIS
        Bosch Siemens Home Connect Modul for FHEM
        contributed by Stefan Willmeroth 09/2016

=head1 DESCRIPTION
        48_HomeConnectConnection keeps the OAuth token needed by devices defined by
        48_HomeConnect 

=head1 AUTHOR - Stefan Willmeroth
        swi@willmeroth.com (forum.fhem.de)
=cut

package main;

use strict;
use warnings;
use JSON;
use URI::Escape;
use Switch;
use Data::Dumper; #debugging

use vars qw($readingFnAttributes);
use vars qw(%defs);
use vars qw(%FW_webArgs);

require HttpUtils;

##############################################
sub HomeConnectConnection_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}        = "HomeConnectConnection_Set";
  $hash->{DefFn}        = "HomeConnectConnection_Define";
  $hash->{GetFn}        = "HomeConnectConnection_Get";
  $hash->{FW_summaryFn} = "HomeConnectConnection_FwFn";
  $hash->{FW_detailFn}  = "HomeConnectConnection_FwFn";
  $hash->{AttrList}     = "disable:0,1 " .
                          "accessScope " .
                          $readingFnAttributes;
}

###################################
sub HomeConnectConnection_Set($@)
{
  my ($hash, @a) = @_;
  my $rc = undef;
  my $reDOUBLE = '^(\\d+\\.?\\d{0,2})$';

  my ($gterror, $gotToken) = getKeyValue($hash->{NAME}."_accessToken");

  return "no set value specified" if(int(@a) < 2);
  return "LoginNecessary" if($a[1] eq "?" && !defined($gotToken));
  return "scanDevices:noArg refreshToken:noArg logout:noArg" if($a[1] eq "?");
  if ($a[1] eq "auth") {
    return HomeConnectConnection_GetAuthToken($hash,$a[2]);
  }
  if ($a[1] eq "scanDevices") {
    HomeConnectConnection_AutocreateDevices($hash);
  }
  if ($a[1] eq "refreshToken") {
    undef $hash->{expires_at};
    HomeConnectConnection_RefreshToken($hash);
  }
  if ($a[1] eq "logout") {
    setKeyValue($hash->{NAME}."_accessToken",undef);
    setKeyValue($hash->{NAME}."_refreshToken",undef);
    undef $hash->{expires_at};
    $hash->{STATE} = "Login necessary";
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", $hash->{STATE});
    readingsEndUpdate($hash, 1);
  }
}

#####################################
sub HomeConnectConnection_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <conn-name> HomeConnectConnection [client_id] [redirect_uri] [simulator]";

  return $u if(int(@a) < 4);

  $hash->{api_uri} = "https://api.home-connect.com";

  if(int(@a) >= 4) {
    $hash->{client_id} = $a[2];
    $hash->{redirect_uri} = $a[3];
    if (int(@a) > 4) {
      if ("simulator" eq $a[4]) {
        $hash->{simulator} = "1";
        $hash->{api_uri} = "https://simulator.home-connect.com";
      } else {
        $hash->{client_secret} = $a[4];
      }
    }
    if (int(@a) > 5) {
      $hash->{client_secret} = $a[5];
    }
  }
  $hash->{STATE} = "Login necessary";
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "state", $hash->{STATE});
  readingsEndUpdate($hash, 1);

  # start with a delayed token refresh
  setKeyValue($hash->{NAME}."_accessToken",undef);
  undef $hash->{expires_at};
  InternalTimer(gettimeofday()+10, "HomeConnectConnection_RefreshTokenTimer", $hash, 0);

  return;
}

#####################################
sub
HomeConnectConnection_FwFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};

  my ($gterror, $authToken) = getKeyValue($hash->{NAME}."_accessToken");

  my $fmtOutput;

  if (!defined $authToken) {

    my $scope = AttrVal($hash->{NAME}, "accessScope",
		"IdentifyAppliance Monitor Settings Control " .
		"Oven Oven-Control Oven-Monitor Oven-Settings " .
		"Dishwasher Dishwasher-Control Dishwasher-Monitor Dishwasher-Settings " .
		"Washer Washer-Control Washer-Monitor Washer-Settings " .
		"Dryer Dryer-Control Dryer-Monitor Dryer-Settings " .
		"WasherDryer WasherDryer-Control WasherDryer-Monitor WasherDryer-Settings " .
		"Refrigerator Refrigerator-Control Refrigerator-Monitor Refrigerator-Settings " .
		"Freezer Freezer-Control Freezer-Monitor Freezer-Settings " .
		"FridgeFreezer-Control FridgeFreezer-Monitor FridgeFreezer-Settings " . #Caution: plain "FridgeFreezer" is out of scope!
		"WineCooler WineCooler-Control WineCooler-Monitor WineCooler-Settings " .
		"CoffeeMaker CoffeeMaker-Control CoffeeMaker-Monitor CoffeeMaker-Settings " .
		"Hob Hob-Control Hob-Monitor Hob-Settings " .
		"Hood Hood-Control Hood-Monitor Hood-Settings " .
		"CleaningRobot CleaningRobot-Control CleaningRobot-Monitor CleaningRobot-Settings " .
		"CookProcessor CookProcessor-Control CookProcessor-Monitor CookProcessor-Settings " .
		"");

	$scope =~ s/\s$//; #Remove potential trailing space

    my $csrfToken = InternalVal("WEB", "CSRFTOKEN", "HomeConnectConnection_auth");

    $fmtOutput = "<a href=\"$hash->{api_uri}/security/oauth/authorize?response_type=code" .
        "&redirect_uri=". uri_escape($hash->{redirect_uri}) . "&realm=fhem.de" .
        "&client_id=$hash->{client_id}&scope=" . uri_escape($scope) .
        "&state=" .$csrfToken. "\">Home Connect Login</a>";
  }
  return $fmtOutput;
}

#####################################
sub HomeConnectConnection_GetAuthToken
{
  my ($hash,$tokens) = @_;
  my $name = $hash->{NAME};
  my $JSON = JSON->new->utf8(0)->allow_nonref;

  my $error = $FW_webArgs{"error"};
  if (defined $error) {
    my $err_desc = $FW_webArgs{"error_description"};
    my $msg = "Login to Home Connect failed with error $error";
    $msg .= ": $err_desc" if defined($err_desc); 
    return $msg;
  }

  my $code = $FW_webArgs{"code"};
  if (!defined $code) {
    Log3 $name, 4, "Searching auth tokens in: $tokens";
    $tokens =~ m/code=([^&]*)/;
    $code = $1;
  }

  Log3 $name, 4, "Got oauth code: $code";

  HttpUtils_NonblockingGet({
    callback => \&HomeConnectConnection_CallbackGetAuthToken,
    hash => $hash,
    url => "$hash->{api_uri}/security/oauth/token",
    timeout => 10,
    noshutdown => 1,
    data => {grant_type => 'authorization_code', 
	    client_id => $hash->{client_id},
	    client_secret => $hash->{client_secret},
	    code => $code,
	    redirect_uri => $hash->{redirect_uri}
    }
  });
} 

#####################################
sub HomeConnectConnection_RefreshToken($;$)
{
  my ($hash, $nextcall) = @_;
  my $name = $hash->{NAME};
  my $refresh = undef;

  my $conn = $hash->{hcconn};
  if (!defined $conn) {
    $conn = $hash;
  } else {
    $conn = $defs{$conn};
  }

  my ($gkerror, $refreshToken) = getKeyValue($conn->{NAME}."_refreshToken");
  if (!defined $refreshToken) {
    $refresh = "no token to be refreshed";
  }

  if( defined($conn->{expires_at}) ) {
    my ($seconds) = gettimeofday();
    if( $seconds < $conn->{expires_at} - 300 ) {
      $refresh = "no token refresh needed";
    }
  }

  if (defined($refresh)) {
    Log3 $name, 4, "$name: $refresh";
    if (defined($nextcall)) {      
      $nextcall->{callback}($hash, $nextcall->{data});
    }
  } else {
    Log3 $name, 4, "$name: refreshing token";
    HttpUtils_NonblockingGet({
      callback => \&HomeConnectConnection_CallbackRefreshToken,
      hash => $hash,
      nextcall => $nextcall,
      url => "$hash->{api_uri}/security/oauth/token",
      timeout => 10,
      noshutdown => 1,
      data => {grant_type => 'refresh_token', 
        client_id => $conn->{client_id},  
        client_secret => $conn->{client_secret},
        refresh_token => $refreshToken
      }
    });
  }
  return undef;
}

#####################################
sub HomeConnectConnection_AutocreateDevices
{
  my ($hash) = @_;

  #### Read list of appliances
  my $URL = "/api/homeappliances";

  my $data = {callback => \&HomeConnectConnection_ResponseAutocreateDevices, uri => $URL};
  HomeConnectConnection_request($hash, $data);
}

#####################################
sub HomeConnectConnection_Undef($$)
{
   my ( $hash, $arg ) = @_;

   RemoveInternalTimer($hash);
   Log3 $hash->{NAME}, 3, "--- removed ---";
   return undef;
}

#####################################
sub HomeConnectConnection_Get($@)
{
  my ($hash, @args) = @_;

  return 'HomeConnectConnection_Get needs two arguments' if (@args != 2);

  my $get = $args[1];
  my $val = $hash->{Invalid};

  return "HomeConnectConnection_Get: no such reading: $get";

}

#####################################
sub HomeConnectConnection_RefreshTokenTimer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if (AttrVal($name, "disable", 0) == 1);

  undef $hash->{expires_at};
  HomeConnectConnection_RefreshToken($hash);
}

#####################################
sub HomeConnectConnection_request
{
  my ($hash, $data) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: request $data->{uri}";
  
  my $api_uri = (defined $hash->{hcconn}) ? $defs{$hash->{hcconn}}->{api_uri} : $hash->{api_uri};

  my $URL = $api_uri . $data->{uri};
  my $nextcall = {
    callback => \&HomeConnectConnection_requestAfterToken,
    data => {
      uri => $URL,
      data=>$data->{data},
      nextcall => {
        callback => $data->{callback}
      }
    }    
  };
  HomeConnectConnection_RefreshToken($hash, $nextcall);
}

#####################################
sub HomeConnectConnection_requestAfterToken
{
  my ($hash, $data) = @_;
  my $name = $hash->{NAME};

  my $conn = $hash->{hcconn};
  if (!defined $conn) {
    $conn = $name;
  }

  my ($gkerror, $token) = getKeyValue($conn."_accessToken");

  if (!defined($data)) {
    Log3 $name, 1, "$name: requestAfterToken no data";
    return;
  }

  my $uri = $data->{uri};
  if (!defined($uri)) {
    Log3 $name, 1, "$name: requestAfterToken no uri";
    return;
  }

  Log3 $name, 4, "$name: requestAfterToken $uri";

  my $param;
  if (defined($data->{data})) {

    if ($data->{data} eq "DELETE") {
        $param = {
          url        => $uri,
          hash       => $hash,
          nextcall   => $data->{nextcall},
          callback   => \&HomeConnectConnection_CallbackRequest,
          timeout    => 5,
          noshutdown => 1,
          method     => "DELETE",
          header     => { "Accept" => "application/vnd.bsh.sdk.v1+json", "Authorization" => "Bearer $token" }
        };
    } else {
      $param = {
        url        => $uri,
        hash       => $hash,
        nextcall   => $data->{nextcall},
        callback   => \&HomeConnectConnection_CallbackRequest,
        timeout    => 5,
        noshutdown => 1,
        method     => "PUT",
        header     => { "Accept" => "application/vnd.bsh.sdk.v1+json",
                        "Authorization" => "Bearer $token",
                        "Content-Type" => "application/vnd.bsh.sdk.v1+json"
                      },
        data       => $data->{data}
      };
    } 
  } else {
    $param = {
      url        => $uri,
      hash       => $hash,
      nextcall   => $data->{nextcall},
      callback   => \&HomeConnectConnection_CallbackRequest,
      timeout    => 5,
      noshutdown => 1,    
      header     => { "Accept" => "application/vnd.bsh.sdk.v1+json", "Authorization" => "Bearer $token" }
    };
  }
  HttpUtils_NonblockingGet($param);
}

#####################################
sub HomeConnectConnection_delrequest
{
  my ($hash, $data) = @_;
  $data->{data} = "DELETE";
  HomeConnectConnection_request($hash, $data);
}

#####################################
sub HomeConnectConnection_CallbackRefreshToken
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  my $conn = $hash->{hcconn};
  if (!defined $conn) {
    $conn = $hash;
  } else {
    $conn = $defs{$conn};
  }

  if( $err ) {
    Log3 $name, 2, "$name: http request failed: $err";
    $hash->{lastError} = $err;
  } elsif( $data ) {
    Log3 $name, 4, "$name: RefreshTokenResponse $data";

    $data =~ s/\n//g;
    if( $data !~ m/^\{.*}$/m ) {

      Log3 $name, 2, "$name: invalid json detected: >>$data<<";

    } else {
      my $json = eval {decode_json($data)};
      if($@){
        Log3 $name, 2, "$name JSON error while reading refreshed token";
      } else {

        if( $json->{error} ) {
          $hash->{lastError} = $json->{error};
        }

        my ($gterror, $gotToken) = getKeyValue($conn->{NAME}."_accessToken"); #old token

        setKeyValue($conn->{NAME}."_accessToken",  $json->{access_token});
        setKeyValue($conn->{NAME}."_refreshToken", $json->{refresh_token});

        if( $json->{access_token} ) {
          $conn->{STATE} = "Connected";
          $conn->{expires_at} = gettimeofday();
          $conn->{expires_at} += $json->{expires_in};
          undef $conn->{refreshFailCount};
          readingsBeginUpdate($conn);
          readingsBulkUpdate($conn, "tokenExpiry", scalar localtime $conn->{expires_at});
          readingsBulkUpdate($conn, "state", $conn->{STATE});
          readingsEndUpdate($conn, 1);
          RemoveInternalTimer($conn);
          InternalTimer(gettimeofday()+$json->{expires_in}*3/4,
            "HomeConnectConnection_RefreshTokenTimer", $conn, 0);

          # no old token - init HomeConnect devices
          if (!$gotToken) {
            foreach my $key ( keys %defs ) {
              if ($defs{$key}->{TYPE} eq "HomeConnect") {
                fhem "set $key init";
              }
            }
          }

          if (defined($param->{nextcall})) {
            my $nextcall = $param->{nextcall}; 
            $nextcall->{callback}($hash, $nextcall->{data});
          }          
          return;
        }
      }
    }
  }

  $conn->{STATE} = "Refresh Error" ;

  if (defined $conn->{refreshFailCount}) {
    $conn->{refreshFailCount} += 1;
  } else {
    $conn->{refreshFailCount} = 1;
  }

  if ($conn->{refreshFailCount}==10) {
    Log3 $conn->{NAME}, 2, "$conn->{NAME}: Refreshing token failed too many times, stopping";
    $conn->{STATE} = "Login necessary";
    setKeyValue($hash->{NAME}."_refreshToken", undef);
  } else {
    RemoveInternalTimer($conn);
    InternalTimer(gettimeofday()+60, "HomeConnectConnection_RefreshTokenTimer", $conn, 0);
  }

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "state", $hash->{STATE});
  readingsEndUpdate($hash, 1);
}

#####################################
sub HomeConnectConnection_CallbackGetAuthToken
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if( $err ) {
    Log3 $name, 2, "$name http request failed: $err";
    $hash->{lastError} = $err;
    return;
  } elsif( $data ) {
    Log3 $name, 2, "$name AuthTokenResponse $data";

    $data =~ s/\n//g;
    if( $data !~ m/^\{.*}$/m ) {
      Log3 $name, 2, "$name invalid json detected: >>$data<<";
      return;
    }
  }

  my $JSON = JSON->new->utf8(0)->allow_nonref;
  my $json = eval {$JSON->decode($data)};
  if($@){
    Log3 $name, 2, "($name) - JSON error requesting tokens: $@";
    return;
  }

  if( $json->{error} ) {
    $hash->{lastError} = $json->{error};
  }

  setKeyValue($hash->{NAME}."_accessToken",$json->{access_token});
  setKeyValue($hash->{NAME}."_refreshToken", $json->{refresh_token});

  if( $json->{access_token} ) {
    $hash->{STATE} = "Connected";
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", $hash->{STATE});

    ($hash->{expires_at}) = gettimeofday();
    $hash->{expires_at} += $json->{expires_in};

    readingsBulkUpdate($hash, "tokenExpiry", scalar localtime $hash->{expires_at});
    readingsEndUpdate($hash, 1);

    foreach my $key ( keys %defs ) {
      if (($defs{$key}->{TYPE} eq "HomeConnect") && ($defs{$key}->{hcconn} eq $hash->{NAME})) {
        fhem "set $key init";
      }
    }

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$json->{expires_in}*3/4,
      "HomeConnectConnection_RefreshTokenTimer", $hash, 0);
  } else {
    $hash->{STATE} = "Error";
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", $hash->{STATE});
    readingsEndUpdate($hash, 1);
  }
}

#####################################
sub HomeConnectConnection_CallbackRequest
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if ($err) {
    Log3 $name, 2, "$name: error in request" . $err;    
  } else {
    Log3 $name, 4 , "$name: response " . $data;
  }

  if (defined($param->{nextcall})) {
    my $nextcall = $param->{nextcall};
    $nextcall->{callback}($hash, $data, $param->{path});
  }
  else {
    Log3 $name, 2 , "$name: no callback for request registered";
  } 
}

#####################################
sub HomeConnectConnection_ResponseAutocreateDevices
{
  my ($hash, $data) = @_;

  if (!defined $data) {
    return "Failed to connect to HomeConnectConnection API, see log for details";
  }

  my $appliances = eval {decode_json ($data)};
  if($@){
    Log3 $hash->{NAME}, 2, "$hash->{NAME} JSON error while reading appliances";
  } else {
    for (my $i = 0; 1; $i++) {
      my $appliance = $appliances->{data}->{homeappliances}[$i];
      if (!defined $appliance) { last };
      if (!defined $defs{$appliance->{vib}}) {
        fhem ("define $appliance->{vib} HomeConnect $hash->{NAME} $appliance->{haId}");
      }
    }
  };
}


1;

=pod
=begin html

<h3>HomeConnectConnection</h3>
<a id="HomeConnectConnection"></a>
<ul>
  <a id="HomeConnectConnection-define"></a>
  <h4>Define</h4>
  <ul>
    <code>define &lt;name&gt; HomeConnectConnection &lt;api_key&gt; &lt;redirect_url&gt; [simulator] &lt;client_secret&gt;</code>
    <br/>
    <br/>
    Defines a connection and login to Home Connect Household appliances. See <a href="http://www.home-connect.com/">Home Connect</a> for details.<br>
    <br/>
    The following steps are needed to link FHEM to Home Connect:<br/>
    <ul>
      <li>Define a static CSRF Token in FHEM using a command like <code>attr WEB.* csrfToken myToken123</code>
      <li>Create a developer account at <a href="https://developer.home-connect.com/">Home Connect for Developers</a></li>
      <li>Update your account to an <b>Advanced Account</b></li>
      <li>Create your Application under "My Applications", the REDIRECT-URL must be pointing to your local FHEM installation, e.g.<br/>
      <code>http://fhem.local:8083/fhem?cmd.Test=set%20hcconn%20auth%20&fwcsrf=myToken123</code><br/></li>
      <li>Make sure that "fhem.local" is replaced with a usable hostname for your FHEM. Setting it to an IP address is reported to fail. 
      <li>Note the Client ID and Client Secret after creating the Application
      <li>Now define the FHEM HomeConnectConnection device with your API Key, Secret and URL:<br/>
      <code>define hcconn HomeConnectConnection API-KEY REDIRECT-URL [simulator] CLIENT_SECRET</code><br/></li>
      <li>Click on the link "Home Connect Login" in the device and log in to your account.</li>
      <li>Execute the set scanDevices action to create FHEM devices for your appliances.</li>
    </ul>
	  The simulator may have an issue with the complex URL and report an "internal error". Workaround: just set http://fhem.local:8030/fhem.html as URL. After successful login the FHEM home page is called. Now check the URL line of your browser. Copy it into an editor and extract the "code=...." piece (ending at the next "&". If %3D (or other % escapes) are in the string, they need to be reverted to ASCII. %3D is "="<br>
	  Finally call "set hcconn auth code=...." - that should connect you to the simulator. This may also be a workaround if you have problems with the productive setup.<br> 
 	<br/>
	If you would like to name your HomeConnectConnection differently or if you need to connect to more than one account, the name hcconn may be changed.
	Make sure to update the new name into your REDIRECT-URL (both in FHEM and Home Connect). If you want to use more than one connection, you can list 
        both redirect-URLs in your Home Connect Application.
    <br/>
    <b>Troubleshooting tips:</b> If you see errors when logging in, you should check the following points:<ul>
      <li>Do you have an advanced Home Connect Developer account? If not, set the AccessScope attribute to <code>IdentifyAppliance Monitor</code> or update your account.</li>
      <li>Did you define a static csrf token and add it to your redirect URL?</li>
      <li>Does the redirect URL point to you FHEM and is it according to the specifications above?</li>
      <li>Is the name of your HomeConnectConnection device hcconn? If not, you need to update the URL accordingly.</li>
      <li>Is the redirect URL identically defined in your Home Connect Developer application and in you FHEM device definition?</li>
    </ul>
  </ul>
  <br/>
  
  <a id="HomeConnectConnection-set"></a>
  <h4>Set</h4>  
  <ul>
  	<li><b>set scanDevices</b><br>
		<a id="HomeConnectConnection-set-scanDevices"></a>
      Start a device scan of the Home Connect account. The registered Home Connect devices are then created automatically
      in FHEM. The device scan can be started several times and will not duplicate devices as long as they have not been
      renamed in FHEM. You should change the alias attribute instead.
      </li>
  	<li><b>set refreshToken</b><br>
		<a id="HomeConnectConnection-set-refreshToken"></a>
      Manually refresh the access token. This should be necessary only after internet connection problems.
      </li>
  	<li><b>set logout</b><br>
		<a id="HomeConnectConnection-set-logout"></a>
      Delete the access token and refresh tokens, and show the login link again.
      </li>
  </ul>
  <br/>
  <a id="HomeConnect-attr"></a>
  <h4>Attributes</h4>
  <ul>
	<li>accessScope &lt;scope list&gt;<br/>
		<a id="HomeConnectConnection-attr-accessScope"></a>
	  Change this attribute to limit the access rights given to FHEM. The default is to submit all currently available<br>
	  The individual items are separated by spaces. It is important to correctly specify them. Any typo will lead to a reject when doing the login, without any information what the offending item was.<br>
	  Minimum setting would be "IdentifyAppliance Monitor"<br>
	  <ul>
	  <b>Full list of currently available access scopes (grouped by appliances, each space separated item can be used individually):</b>
		<li>IdentifyAppliance Monitor Settings Control</li>
		<li>Oven Oven-Control Oven-Monitor Oven-Settings</li>
		<li>Dishwasher Dishwasher-Control Dishwasher-Monitor Dishwasher-Settings</li>
		<li>Washer Washer-Control Washer-Monitor Washer-Settings</li>
		<li>Dryer Dryer-Control Dryer-Monitor Dryer-Settings</li>
		<li>WasherDryer WasherDryer-Control WasherDryer-Monitor WasherDryer-Settings</li>
		<li>Refrigerator Refrigerator-Control Refrigerator-Monitor Refrigerator-Settings</li>
		<li>Freezer Freezer-Control Freezer-Monitor Freezer-Settings</li>
		<li>FridgeFreezer-Control FridgeFreezer-Monitor FridgeFreezer-Settings</li>
		<li>WineCooler WineCooler-Control WineCooler-Monitor WineCooler-Settings</li>
		<li>CoffeeMaker CoffeeMaker-Control CoffeeMaker-Monitor CoffeeMaker-Settings</li>
		<li>Hob Hob-Control Hob-Monitor Hob-Settings</li>
		<li>Hood Hood-Control Hood-Monitor Hood-Settings</li>
		<li>CleaningRobot CleaningRobot-Control CleaningRobot-Monitor CleaningRobot-Settings</li>
		<li>CookProcessor CookProcessor-Control CookProcessor-Monitor CookProcessor-Settings</li>
		</ul>
      </li>
  </ul>
  <br/>

</ul>

=end html
=cut

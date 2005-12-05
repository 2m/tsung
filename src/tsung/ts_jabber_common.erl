%%%  This code was developped by IDEALX (http://IDEALX.org/) and
%%%  contributors (their names can be found in the CONTRIBUTORS file).
%%%  Copyright (C) 2000-2001 IDEALX
%%%
%%%  This program is free software; you can redistribute it and/or modify
%%%  it under the terms of the GNU General Public License as published by
%%%  the Free Software Foundation; either version 2 of the License, or
%%%  (at your option) any later version.
%%%
%%%  This program is distributed in the hope that it will be useful,
%%%  but WITHOUT ANY WARRANTY; without even the implied warranty of
%%%  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%%  GNU General Public License for more details.
%%%
%%%  You should have received a copy of the GNU General Public License
%%%  along with this program; if not, write to the Free Software
%%%  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.
%%% 

%%%  In addition, as a special exception, you have the permission to
%%%  link the code of this program with any library released under
%%%  the EPL license and distribute linked combinations including
%%%  the two.

-module(ts_jabber_common).
-vc('$Id$ ').
-author('nicolas.niclausse@niclux.org').

-export([ get_random_params/4,  
          get_message/1
         ]). 

-include("ts_profile.hrl").
-include("ts_jabber.hrl").

%%----------------------------------------------------------------------
%% Func: get_message/1
%% Args: #jabber record
%% Returns: binary
%% Purpose: Build a message/request from a #jabber record
%%----------------------------------------------------------------------
get_message(Jabber=#jabber{type = 'connect'}) ->
    connect(Jabber);
get_message(#jabber{type = 'close', id=Id}) ->
    ts_user_server:remove_connected(Id),
    close();
get_message(#jabber{type = 'presence'}) ->
    presence();

get_message(Jabber=#jabber{type = 'presence:directed', id=Id}) ->
    case ts_user_server:get_one_connected(Id) of
        {ok, Dest} ->
            presence(directed,  Jabber#jabber{dest=Dest});
        {error, no_online} ->
            ts_mon:add({ count, error_no_online }),
            << >>
    end;

get_message(Jabber=#jabber{id=Id}) when is_integer(Id)->
    get_message(Jabber#jabber{id=integer_to_list(Id)});
get_message(Jabber=#jabber{dest=previous}) ->
    Dest = get(previous),
    get_message(Jabber#jabber{dest=Dest});
get_message(Jabber=#jabber{type = 'presence:roster'}) ->
    presence(roster, Jabber);
get_message(Jabber=#jabber{type = 'presence:subscribe'}) ->
    presence("subscribe", Jabber);
get_message(Jabber=#jabber{type = 'chat', id=Id, dest=online, domain=Domain})->
    case ts_user_server:get_one_connected(Id) of 
        {ok, Dest} ->
            message(Dest, Jabber, Domain);
        {error, no_online} ->
            ts_mon:add({ count, error_no_online }),
            << >>
    end;
        
get_message(Jabber=#jabber{type = 'chat', domain = Domain, dest=offline}) ->
    case ts_user_server:get_offline() of 
        {ok, Dest} ->
            message(Dest, Jabber, Domain);
        {error, no_offline} ->
            ts_mon:add({ count, error_no_offline }),
            << >>
    end;
get_message(Jabber=#jabber{type = 'chat', dest=random, domain=Domain}) ->
    Dest = ts_user_server:get_id(),
    message(Dest, Jabber, Domain);
get_message(Jabber=#jabber{type = 'chat', dest=unique, domain=Domain})->
    {Dest, _} = ts_user_server:get_first(),
    message(Dest, Jabber, Domain);
get_message(Jabber=#jabber{type = 'chat', id=Id, dest = Dest, domain=Domain}) ->
    ?DebugF("~w -> ~w ~n", [Id,  Dest]),
    message(Dest, Jabber, Domain);
get_message(#jabber{type = 'iq:roster:set', id=Id, dest = online,username=User,domain=Domain}) ->
    case ts_user_server:get_one_connected(Id) of 
        {ok, Dest} ->
            request(roster_set, User, Domain, Dest);
        {error, no_online} ->
            ts_mon:add({ count, error_no_online }),
            << >>
    end;
get_message(#jabber{type = 'iq:roster:set',dest = offline,username=User,domain=Domain})->
    case ts_user_server:get_offline() of 
        {ok, Dest} ->
            put(previous, Dest),
            request(roster_set, User, Domain, Dest);
        {error, no_offline} ->
            ts_mon:add({ count, error_no_offline }),
            << >>
    end;
get_message(#jabber{type = 'iq:roster:get', id = Id,username=User,domain=Domain}) ->
    request(roster_get, User, Domain, Id);

get_message(Jabber=#jabber{type = 'raw'}) ->
    raw(Jabber);


get_message(Jabber=#jabber{username = Name, passwd= Passwd, id=Id}) ->
    FullName = Name ++ Id,
    FullPasswd = Passwd ++ Id,
	get_message2(Jabber#jabber{username=FullName,passwd=FullPasswd}).


%%----------------------------------------------------------------------
%% Func: get_message2/1
%%----------------------------------------------------------------------
get_message2(Jabber=#jabber{type = 'register'}) ->
    registration(Jabber);
get_message2(Jabber=#jabber{type = 'authenticate'}) ->
    auth(Jabber).




%%----------------------------------------------------------------------
%% Func: connect/1
%%----------------------------------------------------------------------
connect(#jabber{domain=Domain}) ->
    list_to_binary([
	  "<stream:stream  id='",
	  ts_msg_server:get_id(list),
	  "' to='",
	  Domain,
	  "' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>"]).

%%----------------------------------------------------------------------
%% Func: close/0
%% Purpose: close jabber session
%%----------------------------------------------------------------------
close () -> list_to_binary("</stream:stream>").

%%----------------------------------------------------------------------
%% generic Authentication message (auth or register)
%%----------------------------------------------------------------------
auth(#jabber{username=Name,passwd=Passwd})->
	auth(Name, Passwd, "auth").

auth(Username, Passwd, Type) ->
 list_to_binary([
   "<iq id='", ts_msg_server:get_id(list),
   "' type='set' >",
   "<query xmlns='jabber:iq:", Type, "'>",
   "<username>", Username, "</username>", 
   "<resource>Tsung</resource>",
   "<password>", Passwd, "</password></query></iq>"]).

%%----------------------------------------------------------------------
%% Func: registration/1
%% Purpose: register message
%%----------------------------------------------------------------------
registration(#jabber{username=Name,passwd=Passwd})->
	auth(Name, Passwd, "register").

%%----------------------------------------------------------------------
%% Func: message/3
%% Purpose: send message to defined user at the Service (aim, ...)
%%----------------------------------------------------------------------
message(Dest, Jabber, Service) when is_integer(Dest) ->
	message(integer_to_list(Dest),Jabber, Service);
message(Dest, #jabber{size=Size,data=undefined, username=Username}, Service) when is_integer(Size) ->
    list_to_binary([
                    "<message id='",ts_msg_server:get_id(list), "' to='",
                    Username, Dest, "@", Service,
                    "'><body>",garbage(Size), "</body></message>"]);
message(Dest, #jabber{data=Data, username=Username}, Service) when is_list(Data) ->
    list_to_binary([
                    "<message id='",ts_msg_server:get_id(list), "' to='",
                    Username, Dest, "@", Service,
                    "'><body>",Data, "</body></message>"]).

%%----------------------------------------------------------------------
%% Func:    garbage/1
%% Purpose: generate list of given size. Implemented by duplicating list
%% of length 10 to be faster
%%----------------------------------------------------------------------
garbage(Size) when Size >= 10 ->
	Msg= lists:duplicate(Size div 10,"0123456789"),
	case Size rem 10 of
		0->
			Msg;
		Rest ->
			lists:append(Msg,garbage(Rest))
	end;
garbage(Size)->
	lists:duplicate(Size rem 10,"a").
	

%%----------------------------------------------------------------------
%% Func: presence/0
%%----------------------------------------------------------------------
presence() -> 
	list_to_binary([ "<presence id='",ts_msg_server:get_id(list),"' />"]).

%%----------------------------------------------------------------------
presence(Type, Jabber=#jabber{dest=Dest}) when is_integer(Dest)->
    presence(Type, Jabber#jabber{dest=integer_to_list(Dest)}) ;
presence(roster, Jabber)->
    presence(subscribed, Jabber);
presence(directed, #jabber{dest= Dest,domain=Domain, username=UserName})->
    DestName = UserName ++ Dest,
    list_to_binary([
          "<presence id='",ts_msg_server:get_id(list),
          "' to='", DestName, "@" , Domain , "'>",
          "<show>chat</show><status>tsung load gen</status></presence>"]);
presence(Type, Jabber) when is_atom(Type)->
    presence(atom_to_list(Type), Jabber);
presence(Type, #jabber{dest=Dest, domain=Domain, username=UserName})->
    DestName = UserName ++ Dest,
    list_to_binary([
	  "<presence id='",ts_msg_server:get_id(list),
	  "' to='", DestName, "@" , Domain,
	  "' type='",Type,"'/>"]).


%%----------------------------------------------------------------------
%% Func: request/4
%%----------------------------------------------------------------------
request(roster_set, UserName, Domain, Id) when is_integer(Id)->
    request(roster_set, UserName, Domain, integer_to_list(Id));
request(roster_set, UserName, Domain, Id)->
	Name = UserName ++ Id,
	list_to_binary([
		"<iq id='" ,ts_msg_server:get_id(list),
		"' type='set'>","<query xmlns='jabber:iq:roster'><item jid='",
		Name,"@",Domain,
		"' name='gg1000'/><group>Tsung</group></query></iq>"]);
request(roster_get, _UserName, _Domain, _Id)->
	list_to_binary([
	  "<iq id='" ,ts_msg_server:get_id(list),
	  "' type='get'><query xmlns='jabber:iq:roster'></query></iq>"]).

%%----------------------------------------------------------------------
%% Func: get_random_params/5
%% Args: Intensity (inverse of the mean of inter arrival of messages)
%%       N         : number of messages
%%----------------------------------------------------------------------
get_random_params(_Intensity, 1, Size, Type, L) -> 
    L ++ [#ts_request{ ack = no_ack, 
		    thinktime = ?config(messages_last_time),
		    param = #jabber {size=Size, type=Type}}];

get_random_params(Intensity, N, Size, Type, L)  ->
    get_random_params(Intensity, N-1, Size, Type, 
		      [#ts_request{ack = no_ack, 
                           thinktime = round(ts_stats:exponential(Intensity)),
                           param = #jabber {size=Size, type=Type}}
		       | L]).

get_random_params(Intensity, N, Size, Type) when is_integer(N), N >= 0 ->
    get_random_params(Intensity, N, Size, Type, []).


%%%----------------------------------------------------------------------
%%% Func: raw/1
%%%----------------------------------------------------------------------
raw(#jabber{data=undefined}) ->
    << >>;
raw(#jabber{data=Data}) when is_list(Data) ->
    list_to_binary(Data).



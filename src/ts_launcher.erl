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

%%% This module launch clients (ts_client module) given a number of
%%% clients and the intensity of the arrival process (intensity =
%%% inverse of the mean of inter arrival). The arrival process is a
%%% Poisson Process (ie, inter-arrivals are independant and exponential)

-module(ts_launcher).
-created('Date: 2000/10/23 12:09:57 nniclausse ').
-vc('$Id$ ').
-author('nicolas.niclausse@IDEALX.com').

-include("../include/ts_profile.hrl").

-behaviour(gen_fsm). %% a primitive gen_fsm with a single state ! 

%% External exports
-export([start/1]).

%% gen_fsm callbacks
-export([init/1, launcher/2,  handle_event/3,
		 handle_sync_event/4, handle_info/3, terminate/3]).

-record(state, {interarrival=[]}).

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start(Opts) ->
	?PRINTDEBUG("starting ~p~n",[[Opts]],?DEB),
	gen_fsm:start_link({local, ?MODULE}, ?MODULE, {Opts}, []).

%%%----------------------------------------------------------------------
%%% Callback functions from gen_fsm
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, StateName, StateData}          |
%%          {ok, StateName, StateData, Timeout} |
%%          ignore                              |
%%          {stop, StopReason}                   
%%----------------------------------------------------------------------
init({[Clients, Intensity]}) ->
	?PRINTDEBUG2("starting ~n",?DEB),
    {Msec, Sec, Nsec} = ts_utils:init_seed(),
    random:seed(Msec,Sec,Nsec),
	{ok, launcher, #state{interarrival=ts_stats:exponential(Intensity,Clients)},1}.

%%----------------------------------------------------------------------
%% Func: StateName/2
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                         
%%----------------------------------------------------------------------
%% no more clients to launch, stop
launcher(Event, #state{interarrival = []}) ->
	{stop, normal, #state{}};

launcher(timeout, #state{interarrival = [X |List]}) ->
    %Get one client
    Id = ts_user_server:get_idle(),
    %set the profile of the client
    Profile = ts_profile:get_client(?client_type, Id),
	ts_client_sup:start_child([Profile, {?client_type, ?parse_type, ?mes_type, ?conn_type}]),
	?PRINTDEBUG("client launched, waiting ~p msec before launching next client",
				[X],?DEB),
	{next_state, launcher, #state{interarrival= List}, round(X)}.

%%----------------------------------------------------------------------
%% Func: StateName/3
%% Returns: {next_state, NextStateName, NextStateData}            |
%%          {next_state, NextStateName, NextStateData, Timeout}   |
%%          {reply, Reply, NextStateName, NextStateData}          |
%%          {reply, Reply, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                          |
%%          {stop, Reason, Reply, NewStateData}                    
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: handle_event/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                         
%%----------------------------------------------------------------------
handle_event(Event, StateName, StateData) ->
	{next_state, StateName, StateData}.

%%----------------------------------------------------------------------
%% Func: handle_sync_event/4
%% Returns: {next_state, NextStateName, NextStateData}            |
%%          {next_state, NextStateName, NextStateData, Timeout}   |
%%          {reply, Reply, NextStateName, NextStateData}          |
%%          {reply, Reply, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                          |
%%          {stop, Reason, Reply, NewStateData}                    
%%----------------------------------------------------------------------
handle_sync_event(Event, From, StateName, StateData) ->
	Reply = ok,
	{reply, Reply, StateName, StateData}.

%%----------------------------------------------------------------------
%% Func: handle_info/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                         
%%----------------------------------------------------------------------
handle_info(Info, StateName, StateData) ->
	{next_state, StateName, StateData}.

%%----------------------------------------------------------------------
%% Func: terminate/3
%% Purpose: Shutdown the fsm
%% Returns: any
%%----------------------------------------------------------------------
terminate(Reason, StateName, StatData) ->
	ok.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------



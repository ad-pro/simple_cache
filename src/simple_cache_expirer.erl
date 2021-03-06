%%% @doc This process will expire keys.
%%%
%%% Copyright 2013 Marcelo Gornstein &lt;marcelog@@gmail.com&gt;
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%% @end
%%% @copyright Marcelo Gornstein <marcelog@gmail.com>
%%% @author Marcelo Gornstein <marcelog@gmail.com>
%%%
-module(simple_cache_expirer).
-author('marcelog@gmail.com').
-include("simple_cache.hrl").
-behavior(gen_server).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(state, {}).
-type state():: #state{}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
-export([start_link/0]).

%%% gen_server behavior
-export([
  init/1, handle_info/2, handle_call/3, handle_cast/2,
  code_change/3, terminate/2
]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Public API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Starts the gen_server.
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% gen_server API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init([]) -> {ok, state()}.
init([]) ->
  {ok, #state{}}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
  {noreply, State}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info({expire, CacheName, Key, Expiry}, State) ->
  simple_cache:flush(CacheName, Key, Expiry),
  {noreply, State};

handle_info(_Info, State) ->
  {noreply, State}.

-spec handle_call(
  term(), {pid(), reference()}, state()
) -> {reply, term() | {invalid_request, term()}, state()}.
handle_call({new, CacheName}, _From, State) ->
    Reply = new(CacheName),
    {reply, Reply, State};
handle_call(Req, _From, State) ->
  %lager:error("Invalid request: ~p", [Req]),
  {reply, {invalid_request, Req}, State}.

-spec terminate(atom(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.

-spec code_change(string(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

new(CacheName) ->
    new(CacheName, 20).

new(CacheName, 0) ->
    {error, {fail_to_init_cache, CacheName}};
new(CacheName, TriesRemaining) ->
  RealName = ?NAME(CacheName),
  Config = [
    named_table,
    {read_concurrency, true},
    public,
    {write_concurrency, true}
  ],
  try ets:new(RealName, Config) of
    _RealName ->
       ok
   catch
     error:badarg ->
       case lists:member(RealName, ets:all()) of
         true ->
           Owner = proplists:get_value(owner, ets:info(RealName)),
           case Owner == self() of
             true ->
               error_logger:info_msg("Trying to create ETS table (~p) that already exists, but we are already the owner, so that's okay.",[RealName]);
             false ->
               error_logger:error_msg("Trying to create an ETS table (~p) that exists, and we aren't the owner. We are ~p and the owner is ~p. Time to crash.",[RealName, self(), Owner])
            end;
         false ->
           error_logger:warning_msg("badarg when trying to init Cache: ~p. ~p attempts remaining",[CacheName, TriesRemaining]),
           timer:sleep(100),
           new(CacheName, TriesRemaining-1)
       end;
     E:T ->
         {error, {E, T, erlang:get_stacktrace()}}
   end.

%%  The contents of this file are subject to the Mozilla Public License
%%  Version 1.1 (the "License"); you may not use this file except in
%%  compliance with the License. You may obtain a copy of the License
%%  at http://www.mozilla.org/MPL/
%%
%%  Software distributed under the License is distributed on an "AS IS"
%%  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%%  the License for the specific language governing rights and
%%  limitations under the License.
%%
%%  The Original Code is RabbitMQ.
%%
%%  The Initial Developer of the Original Code is VMware, Inc.
%%  Copyright (c) 2007-2011 VMware, Inc.  All rights reserved.
%%

-module(rabbit_top_worker).
-behaviour(gen_server).

-define(PROCESS_INFO, [memory, current_function, current_stacktrace,
                       garbage_collection, heap_size, initial_call,
                       links, message_queue_len, monitors, reductions,
                       registered_name, stack_size, status, trap_exit,
                       total_heap_size]).

-export([start_link/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([procs/2]).

-define(SERVER, ?MODULE).
-define(MILLIS, 1000).
-define(EVERY, 5).
-define(SLEEP, ?EVERY * ?MILLIS).

-record(state, {procs}).

%%--------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

procs(Key, Count) ->
    gen_server:call(?SERVER, {procs, Key, Count}, infinity).

%%--------------------------------------------------------------------

init([]) ->
    ensure_timer(),
    {ok, #state{procs = procs(dict:new())}}.

handle_call({procs, Key, Count}, _From, State = #state{procs = Procs}) ->
    {reply, rabbit_top_util:toplist(Key, Count, flatten(Procs)), State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Msg, State = #state{procs = OldProcs}) ->
    ensure_timer(),
    {noreply, State#state{procs = procs(OldProcs)}};

handle_info(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------

ensure_timer() ->
    erlang:send_after(?SLEEP, self(), update).

procs(OldProcs) ->
    lists:foldl(
      fun(Pid, Procs) ->
              case process_info(Pid, ?PROCESS_INFO) of
                  undefined ->
                      Procs;
                  Props ->
                      Delta = (reductions(Props) -
                                   case dict:find(Pid, OldProcs) of
                                       {ok, OldProps} -> reductions(OldProps);
                                       error          -> 0
                                   end) div ?EVERY,
                      dict:store(
                        Pid, [{reduction_delta, Delta} | Props], Procs)
              end
      end, dict:new(), processes()).

reductions(Props) ->
    {reductions, R} = lists:keyfind(reductions, 1, Props),
    R.

flatten(Procs) ->
    dict:fold(fun(Pid, Props, Rest) ->
                      [[{pid, Pid} | Props] | Rest]
              end, [], Procs).
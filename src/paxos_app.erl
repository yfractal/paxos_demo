%%%-------------------------------------------------------------------
%% @doc paxos public API
%% @end
%%%-------------------------------------------------------------------

-module(paxos_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    AcceptorNum = 5,
    ProposalNum = 20,
    AcceptorPids =
        lists:map(fun(_) -> {ok, Pid} = paxos_acceptor:start_link(), Pid end,
                  lists:seq(1, AcceptorNum)),

    _ProposalPids =
        lists:map(fun(I) -> {ok, Pid} = paxos_proposer:start_link(I, AcceptorPids), Pid end,
                  lists:seq(1, ProposalNum)),
    paxos_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

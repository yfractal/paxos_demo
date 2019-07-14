-module(paxos_proposer).

-behaviour(gen_statem).

%% APIp
-export([start_link/1,
         prepare/2,
         proposal_accepted/2]).

%% gen_statem callbacks
-export([callback_mode/0, init/1, terminate/3, code_change/4]).
-export([prepare/3]).
-export([proposal/3]).

-define(SERVER, ?MODULE).

-record(data, {id}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Id) ->
    gen_statem:start_link(?MODULE, [Id], []).

prepare(Pid, {N, Proposal}) ->
    gen_statem:cast(Pid, {prepare, N, Proposal}).

proposal_accepted(Pid, {N, Proposal}) ->
    gen_statem:cast(Pid, proposal_accepted).
%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

callback_mode() ->
    [state_functions, state_enter].

init([Id]) ->
    process_flag(trap_exit, true),
    {ok, prepare, #data{id=Id}}.

prepare(enter, _Msg, Data) ->
    io:format("Enter prepare state "),
    %% send_prepare msg to all acceptor
    {keep_state, Data};
prepare(cast, {prepare, _N, _Proposal}, Data) ->
    io:format("receive prepare"),
    {next_state, proposal, Data}.

proposal(enter, _Msg, Data) ->
    %% send_prepare msg to all acceptor
    {keep_state, Data};
proposal(cast, proposal_accepted, Data) ->
    {keep_state, Data}.

terminate(_Reason, _State, _Data) ->
    void.


code_change(_OldVsn, State, Data, _Extra) ->
    {ok, State, Data}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-module(paxos_proposer).

-behaviour(gen_statem).

%% APIp
-export([start_link/2,
         prepare/2,
         proposal_accepted/2,
         consensus/3]).

%% gen_statem callbacks
-export([callback_mode/0, init/1, terminate/3, code_change/4]).
-export([prepare/3]).
-export([proposal/3]).

-define(SERVER, ?MODULE).

-record(data, {id, acceptor_pids, seq,
               current_seq_number,
               current_proposal,
               received_messag_count,
               received_proposal,
               received_proposal_seq_num}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Id, AcceptorPids) ->
    gen_statem:start_link(?MODULE, [{Id, AcceptorPids}], []).

prepare(Pid, {SeqNum, Proposal}) ->
    gen_statem:cast(Pid, {prepare, SeqNum, Proposal}).

proposal_accepted(Pid, {SeqNum, Proposal}) ->
    gen_statem:cast(Pid, {proposal_accepted, SeqNum, Proposal}).
%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

callback_mode() ->
    [state_functions, state_enter].

init([{Id, AcceptorPids}]) ->
    process_flag(trap_exit, true),
    Data = #data{id=Id, acceptor_pids=AcceptorPids, seq=0, received_messag_count=0},
    {ok, prepare, Data}.

prepare(enter, _Msg, Data) ->
    Data2 = send_prepare_to_all_acceptors(Data),
    {keep_state, Data2, [{state_timeout, 10, timeout}]};
prepare(cast, {prepare, SeqNum, Proposal},
        #data{received_messag_count=ReceivedMessagCount, current_seq_number=CurrentSeqNumber}=Data) when CurrentSeqNumber =:= SeqNum ->
    MajorityCount = majority_count(Data),
    if ReceivedMessagCount + 1 >= MajorityCount ->
            Data2 = maybe_update_received_proposal(Data, {SeqNum, Proposal}),
            Data3 = Data2#data{received_messag_count=0},
            {next_state, proposal, Data3};
       true ->
            Data2 = Data#data{received_messag_count = ReceivedMessagCount + 1},
            {keep_state, Data2, [{state_timeout, 10, timeout}]}
    end;
prepare(state_timeout, timeout, Data) ->
    Data2 = send_prepare_to_all_acceptors(Data),
    {keep_state, Data2, [{state_timeout, 10, timeout}]};
prepare(_, _, Data) ->
    {keep_state, Data}.

proposal(enter, _Msg, Data) ->
    Data2 = send_proposal_to_all_acceptors(Data),
    {keep_state, Data2, [{state_timeout, 20, timeout}]};
proposal(cast, {proposal_accepted, SeqNum, Proposal},
         #data{received_messag_count=ReceivedMessagCount,
               current_seq_number=SeqNum,
               current_proposal=Proposal} = Data) ->
    MajorityCount = majority_count(Data),
    if ReceivedMessagCount + 1 >= MajorityCount ->
            Data3 = Data#data{current_proposal=Proposal},
            {next_state, consensus, Data3};
       true ->
            Data2 = Data#data{received_messag_count = ReceivedMessagCount + 1},
            {keep_state, Data2, [{state_timeout, 10, timeout}]}
    end;
proposal(state_timeout, timeout, Data) ->
    {next_state, prepare, Data};
proposal(A, B, Data) ->
    {keep_state, Data}.

consensus(enter, _, #data{current_proposal=Proposal}=Data) ->
    {keep_state, Data};
consensus(_, _, Data) ->
    {keep_state, Data}.

terminate(_Reason, _State, _Data) ->
    void.

code_change(_OldVsn, State, Data, _Extra) ->
    {ok, State, Data}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
send_prepare_to_all_acceptors(#data{acceptor_pids=AcceptorPids, seq=Seq}=Data) ->
    SeqNumber = get_seq_number(Data),
    timer:sleep(rand:uniform(20)),
    lists:foreach(fun(AcceptorPid) ->
                          paxos_acceptor:prepare(AcceptorPid, self(), SeqNumber)
                  end, AcceptorPids),
    Data#data{seq=Seq + 1, current_seq_number=SeqNumber}.

send_proposal_to_all_acceptors(#data{acceptor_pids=AcceptorPids,
                                     current_seq_number=SeqNumber}=Data) ->
    Proposal = get_proposal(Data),
    lists:foreach(fun(AcceptorPid) ->
                          paxos_acceptor:accept(AcceptorPid, self(), {SeqNumber, Proposal})
                  end, AcceptorPids),
    Data#data{current_proposal=Proposal}.

get_proposal(#data{received_proposal=undefined, id=Id}) ->
    Id;
get_proposal(#data{received_proposal=ReceivedProposal}) ->
    ReceivedProposal.

majority_count(#data{acceptor_pids=AcceptorPids}) ->
    AcceptorCount = length(AcceptorPids),
    round(AcceptorCount/2).
maybe_update_received_proposal(#data{received_proposal_seq_num=undefined}=Data, {SeqNum, Proposal}) ->
    Data#data{received_proposal_seq_num=SeqNum,
              received_proposal=Proposal};
maybe_update_received_proposal(
  #data{received_proposal_seq_num=ReceivedProposalSeqNum}=Data, {SeqNum, Proposal})
  when (SeqNum > ReceivedProposalSeqNum) and (Proposal /= undefined) ->
    Data#data{received_proposal_seq_num=SeqNum,
              received_proposal=Proposal};
maybe_update_received_proposal(Data, _) ->
    Data.

get_seq_number(#data{seq=Seq, id=Id}) ->
    Seq + Id / 1000.

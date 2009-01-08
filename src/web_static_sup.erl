%%%-------------------------------------------------------------------
%%% File    : web_static_sup.erl
%%% Author  : asceth <machinist@asceth.com>
%%% Description : Supervisor for the GameSyn website
%%%
%%% Created :  9 Sep 2008 by asceth <machinist@asceth.com>
%%%-------------------------------------------------------------------
-module(web_static_sup).

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the supervisor
%%--------------------------------------------------------------------
start_link([Ip, Port, Domain, DocRoot, WebRouter]) ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, [Ip, Port, Domain, DocRoot, WebRouter]).


%%====================================================================
%% Supervisor callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% Func: init(Args) -> {ok,  {SupFlags,  [ChildSpec]}} |
%%                     ignore                          |
%%                     {error, Reason}
%% Description: Whenever a supervisor is started using
%% supervisor:start_link/[2,3], this function is called by the new process
%% to find out about restart strategy, maximum restart frequency and child
%% specifications.
%%--------------------------------------------------------------------
init([Ip, Port, Domain, DocRoot, WebRouter]) ->
  RestartStrategy = one_for_one,
  MaxRestarts = 10,
  MaxSecondsBetweenRestarts = 5,

  SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

  Restart = permanent,
  Shutdown = 5000,
  Type = worker,

  Timeout = 120000, % 2 minute session timeout

  WebConfig = [{ip, Ip},
               {port, Port},
               {docroot, DocRoot},
               {web_router, WebRouter}],


  WebStaticRouter = {web_static_router, {web_router, start_link, [WebRouter]},
                      Restart, Shutdown, Type, [web_router]},

  WebSessions = {web_sessions, {web_sessions, start_link, [WebRouter, Domain, Timeout]},
                 Restart, Shutdown, Type, [web_sessions]},

  WebStatic = {web_static, {web_static, start_link, [WebConfig]},
                Restart, Shutdown, Type, [web_static]},

  {ok, {SupFlags, [WebStaticRouter, WebSessions, WebStatic]}}.

%%====================================================================
%% Internal functions
%%====================================================================


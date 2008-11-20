%%%-------------------------------------------------------------------
%%% File    : web_static_app.erl
%%% Author  : asceth <machinist@asceth.com>
%%% Description : Starts all necessary components for GameSyn website
%%%
%%% Created :  9 Sep 2008 by asceth <machinist@asceth.com>
%%%-------------------------------------------------------------------
-module(web_static_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% Application callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start(Type, StartArgs) -> {ok, Pid} |
%%                                     {ok, Pid, State} |
%%                                     {error, Reason}
%% Description: This function is called whenever an application
%% is started using application:start/1,2, and should start the processes
%% of the application. If the application is structured according to the
%% OTP design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%--------------------------------------------------------------------
start(_Type, _StartArgs) ->
  Ip = case os:getenv("STATIC_IP") of
         false ->
           "0.0.0.0";
         AnyIp ->
           AnyIp
       end,
  Port = case os:getenv("STATIC_PORT") of
           false ->
             8000;
           AnyPort ->
             AnyPort
         end,
  DocRoot = case os:getenv("STATIC_ROOT") of
              false ->
                filename:join(["var", "www"]);
              AnyDocRoot ->
                AnyDocRoot
            end,
  WebRouter = case os:getenv("STATIC_ROUTER") of
                false ->
                  web_static_router;
                AnyWebRouter ->
                  AnyWebRouter
              end,
  Domain = case os:getenv("STATIC_DOMAIN") of
             false ->
               "localhost";
             AnyDomain ->
               AnyDomain
           end,

  case web_static_sup:start_link([Ip, Port, Domain, DocRoot, WebRouter]) of
    {ok, Pid} ->
      {ok, Pid};
    Error ->
      Error
  end.

%%--------------------------------------------------------------------
%% Function: stop(State) -> void()
%% Description: This function is called whenever an application
%% has stopped. It is intended to be the opposite of Module:start/2 and
%% should do any necessary cleaning up. The return value is ignored.
%%--------------------------------------------------------------------
stop(_State) ->
  ok.

%%====================================================================
%% Internal functions
%%====================================================================

